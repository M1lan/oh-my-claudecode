/**
 * Integration test: rmux multiplexer timing risks (real binary, no mocks)
 *
 * Every other rmux-session test in this directory mocks child_process /
 * rmux-utils entirely (see rmux-session.spawn.test.ts). This file is the
 * deliberate exception: it shells out to a REAL `rmux` binary to exercise
 * the three timing-sensitive code paths the tmux->rmux migration analysis
 * flagged as highest risk:
 *
 *  1. Capture-diff readiness polling — waitForShellReady() /
 *     getPaneCurrentCommandStatus() (rmux-session.ts, private, poll
 *     `#{pane_dead} #{pane_current_command}` every 50ms) and
 *     verifyWorkerStartCommandDelivered() (private, capture-diffs 5x50ms).
 *     Neither function is exported, so this file reaches them the only way
 *     production code does: through the exported entry points that call
 *     them — createTeamSession() (readiness wait) and spawnWorkerInPane()
 *     (delivery + submit verification).
 *  2. Layout math — applyMainVerticalLayout() (exported) sets
 *     main-pane-width=floor(window_width/2) then reapplies main-vertical.
 *  3. pane_dead transition — getWorkerLiveness() (exported) queries the
 *     same `#{pane_dead}` field getPaneCurrentCommandStatus() uses
 *     internally; combined with a real SIGKILL of a pane's shell process
 *     (remain-on-exit) this proves rmux surfaces pane death the way
 *     production code expects, and that spawnWorkerInPane() refuses to
 *     send into a pane it detects as dead.
 *
 * Skipped when a real `rmux` binary is not on PATH (CI without rmux,
 * Windows, etc.) — same skip pattern as tmux-env-forward.integration.test.ts.
 *
 * Safety note: this repo's own dev/agent shells frequently run *inside* an
 * rmux session (TMUX is set). createTeamSession()/spawnWorkerInPane() read
 * process.env.TMUX directly to decide whether to split panes in the
 * *current* pane vs. create a brand-new detached session. To guarantee this
 * test never touches whatever live, human-attended session happens to be
 * running the test process, TMUX/CMUX_SURFACE_ID are cleared for the
 * duration of the createTeamSession() call so it is forced down the
 * fresh-detached-session branch — a uniquely-named, disposable session that
 * is killed in afterAll(). The underlying tmux/rmux command invocations
 * still hit the real rmux binary throughout.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { execFileSync } from 'child_process';
import {
  createTeamSession,
  spawnWorkerInPane,
  applyMainVerticalLayout,
  captureTeamPane,
  getWorkerLiveness,
  killTeamSession,
  type TeamSession,
  type WorkerPaneConfig,
} from '../rmux-session.js';
import { rmuxCmdAsync } from '../../cli/rmux-utils.js';

function isRmuxAvailable(): boolean {
  try {
    execFileSync('rmux', ['-V'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

const HAS_RMUX = isRmuxAvailable();

/**
 * Best-effort raw cleanup, deliberately bypassing rmux-session.ts /
 * rmux-utils.ts entirely (this is test hygiene, not something under test).
 * createTeamSession() can create the session + leader pane and THEN throw
 * partway through worker-pane setup (e.g. the rmuxCmdAsync `#{...}`
 * resolution divergence documented below), in which case `session` is never
 * assigned and a normal `killTeamSession(session...)` cleanup path never
 * runs. Sweep for any session whose name carries this run's TEAM_NAME so a
 * failed beforeAll never leaks a real rmux session.
 */
function killOrphanedTestSessions(teamName: string): void {
  try {
    const listing = execFileSync(
      'rmux',
      ['list-sessions', '-F', '#{session_name}'],
      { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    for (const name of listing.split('\n').map((l) => l.trim())) {
      if (name && name.includes(teamName)) {
        try {
          execFileSync('rmux', ['kill-session', '-t', name], {
            stdio: 'ignore',
          });
        } catch {
          /* already gone */
        }
      }
    }
  } catch {
    /* no sessions at all, or rmux server not running — nothing to sweep */
  }
}

/** Save/restore a set of env vars around an async call. Deletes keys whose
 * override value is `undefined`, restores the original value (or absence)
 * afterward regardless of success/failure. */
async function withEnvOverrides<T>(
  overrides: Record<string, string | undefined>,
  fn: () => Promise<T>,
): Promise<T> {
  const saved = new Map<string, string | undefined>();
  for (const key of Object.keys(overrides)) {
    saved.set(key, process.env[key]);
    const value = overrides[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of saved) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function pollUntil(
  check: () => Promise<boolean>,
  { timeoutMs = 5000, intervalMs = 100 } = {},
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (await check()) return true;
    if (Date.now() >= deadline) return false;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

describe.skipIf(!HAS_RMUX)(
  'rmux multiplexer timing risks — integration (real binary)',
  () => {
    const TEAM_NAME = `rmuxit${process.pid}`;
    const CWD = process.cwd();
    let session: TeamSession | undefined;

    beforeAll(async () => {
      try {
        // 2 workers: [0] stays alive for readiness/layout/delivery checks,
        // [1] is reserved for the pane-dead test and gets SIGKILLed.
        session = await withEnvOverrides(
          { TMUX: undefined, CMUX_SURFACE_ID: undefined },
          () => createTeamSession(TEAM_NAME, 2, CWD),
        );
      } catch (error) {
        // createTeamSession() can create the session + leader pane and THEN
        // throw partway through worker setup, leaving `session` unassigned.
        // Sweep for it so a failed setup never leaks a real rmux session.
        killOrphanedTestSessions(TEAM_NAME);
        throw error;
      }
    }, 30_000);

    afterAll(async () => {
      if (session) {
        try {
          await killTeamSession(
            session.sessionName,
            session.workerPaneIds,
            session.leaderPaneId,
            { sessionMode: session.sessionMode },
          );
        } catch {
          /* best-effort cleanup */
        }
      }
      killOrphanedTestSessions(TEAM_NAME);
    }, 15_000);

    it('creates a fresh detached rmux session (forced off the ambient TMUX context)', () => {
      expect(session).toBeDefined();
      expect(session!.sessionMode).toBe('detached-session');
      expect(session!.workerPaneIds).toHaveLength(2);
    });

    it('worker panes report a live, ready shell via a real pane_dead/pane_current_command query (risk 1 + risk 3 baseline)', async () => {
      // createTeamSession() awaits waitForShellReady() internally but does
      // NOT check its return value (Promise.all result is discarded — see
      // rmux-session.ts createTeamSession, worker readiness loop). A
      // successful createTeamSession() return is therefore NOT proof of
      // readiness by itself; verify independently here by issuing the same
      // `#{pane_dead} #{pane_current_command}` display-message query the
      // private getPaneCurrentCommandStatus()/waitForShellReady() use.
      for (const paneId of session!.workerPaneIds) {
        const result = await rmuxCmdAsync([
          'display-message',
          '-p',
          '-t',
          paneId,
          '#{pane_dead} #{pane_current_command}',
        ]);
        const [dead, ...commandParts] = result.stdout.trim().split(/\s+/);
        const command = commandParts.join(' ');
        expect(dead).toBe('0');
        expect(command.length).toBeGreaterThan(0);
        expect(command).toMatch(/^(sh|bash|zsh|fish|ksh|atuin)$/);

        const liveness = await getWorkerLiveness(paneId);
        expect(liveness).toBe('alive');
      }
    });

    it('spawnWorkerInPane() delivers and submits a real command end-to-end (waitForShellReady + capture-diff verifyWorkerStartCommandDelivered/Submitted)', async () => {
      const marker = `omc-rmux-itest-marker-${process.pid}`;
      const paneId = session!.workerPaneIds[0]!;
      const config: WorkerPaneConfig = {
        teamName: TEAM_NAME,
        workerName: 'itest-worker-0',
        envVars: {},
        launchBinary: '/bin/echo',
        launchArgs: [marker],
        cwd: CWD,
      };

      await expect(
        withEnvOverrides({ OMC_TEAM_NO_RC: '1' }, () =>
          spawnWorkerInPane(session!.sessionName, paneId, config),
        ),
      ).resolves.toBeUndefined();

      // spawnWorkerInPane() only resolves after verifyWorkerStartCommandSubmitted()
      // observes the command leave the prompt buffer, so the echo has already
      // been exec'd — poll briefly for its output to land in the scrollback.
      const found = await pollUntil(
        async () => (await captureTeamPane(paneId)).includes(marker),
        { timeoutMs: 5000, intervalMs: 200 },
      );
      expect(found).toBe(true);
    });

    it('applyMainVerticalLayout() sizes the main pane to floor(window_width/2) against real rmux (risk 2)', async () => {
      await applyMainVerticalLayout(session!.sessionName);

      const widthResult = await rmuxCmdAsync([
        'display-message',
        '-p',
        '-t',
        session!.sessionName,
        '#{window_width}',
      ]);
      const windowWidth = parseInt(widthResult.stdout.trim(), 10);
      expect(Number.isFinite(windowWidth)).toBe(true);
      expect(windowWidth).toBeGreaterThan(0);

      const mainWidthResult = await rmuxCmdAsync([
        'display-message',
        '-p',
        '-t',
        session!.leaderPaneId,
        '#{pane_width}',
      ]);
      const mainWidth = parseInt(mainWidthResult.stdout.trim(), 10);
      const expectedHalf = Math.floor(windowWidth / 2);
      expect(Math.abs(mainWidth - expectedHalf)).toBeLessThanOrEqual(2);

      // The main pane should also be at least as wide as each worker pane —
      // an independent sanity check that main-vertical actually put the
      // leader pane on the "main" (wide) side of the layout.
      for (const paneId of session!.workerPaneIds) {
        const workerWidthResult = await rmuxCmdAsync([
          'display-message',
          '-p',
          '-t',
          paneId,
          '#{pane_width}',
        ]);
        const workerWidth = parseInt(workerWidthResult.stdout.trim(), 10);
        expect(mainWidth).toBeGreaterThanOrEqual(workerWidth);
      }
    });

    it('a SIGKILLed worker shell transitions pane_dead 0->1 (real rmux, remain-on-exit) and spawnWorkerInPane() refuses to send into it (risk 3)', async () => {
      const deadPaneId = session!.workerPaneIds[1]!;

      // remain-on-exit keeps the pane around (rather than rmux auto-closing
      // it) once its shell process exits, so the dead state is observable —
      // mirrors what production code assumes when it later polls a pane
      // whose worker process crashed or was killed.
      await rmuxCmdAsync([
        'set-window-option',
        '-t',
        deadPaneId,
        'remain-on-exit',
        'on',
      ]);

      const before = await getWorkerLiveness(deadPaneId);
      expect(before).toBe('alive');

      const pidResult = await rmuxCmdAsync([
        'display-message',
        '-p',
        '-t',
        deadPaneId,
        '#{pane_pid}',
      ]);
      const shellPid = parseInt(pidResult.stdout.trim(), 10);
      expect(Number.isFinite(shellPid)).toBe(true);
      expect(shellPid).toBeGreaterThan(0);
      process.kill(shellPid, 'SIGKILL');

      const becameDead = await pollUntil(
        async () => (await getWorkerLiveness(deadPaneId)) === 'dead',
        { timeoutMs: 5000, intervalMs: 100 },
      );
      expect(becameDead).toBe(true);

      // Now drive the exact private readiness path (waitForShellReady ->
      // getPaneCurrentCommandStatus) that spawnWorkerInPane() depends on,
      // via its only real call site, against the now-dead pane.
      const config: WorkerPaneConfig = {
        teamName: TEAM_NAME,
        workerName: 'itest-worker-1',
        envVars: {},
        launchBinary: '/bin/echo',
        launchArgs: ['unreachable'],
        cwd: CWD,
      };

      await expect(
        withEnvOverrides(
          { OMC_TEAM_NO_RC: '1', OMC_TEAM_SHELL_READY_TIMEOUT_MS: '1500' },
          () => spawnWorkerInPane(session!.sessionName, deadPaneId, config),
        ),
      ).rejects.toThrow(/worker_start_shell_not_ready/);
    }, 20_000);
  },
);
