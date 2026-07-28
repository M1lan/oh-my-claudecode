/**
 * Regression tests for issue #2532: centralized OMC_STATE_DIR state-root resolution.
 *
 * Verifies that:
 *   1. Default behavior (no OMC_STATE_DIR) is unchanged — state lives in {dir}/.omc/
 *   2. session-start.mjs reads session state from the custom OMC_STATE_DIR location
 *   3. persistent-mode.cjs (stop hook) reads mode state from the custom OMC_STATE_DIR
 *      location and correctly blocks the stop when an active mode is present there
 *   4. pre-tool-enforcer.mjs (PreToolUse hook) reads team-state and writes
 *      skill-active-state through the centralized OMC_STATE_DIR location
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { execFileSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  realpathSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { getOmcRoot, clearWorktreeCache } from '../lib/worktree-paths.js';
import { absPath } from '../team/state-paths.js';

const NODE = process.execPath;
const REPO_ROOT = resolve(join(__dirname, '..', '..'));
const SESSION_START = join(REPO_ROOT, 'scripts', 'session-start.mjs');
const HOOK_RUNNER = join(REPO_ROOT, 'scripts', 'run.cjs');
const STOP_HOOK = join(REPO_ROOT, 'scripts', 'persistent-mode.cjs');
const PRE_TOOL_ENFORCER = join(REPO_ROOT, 'scripts', 'pre-tool-enforcer.mjs');
const STATE_ROOT_ESM = join(REPO_ROOT, 'scripts', 'lib', 'state-root.mjs');
const STATE_ROOT_CJS = join(REPO_ROOT, 'scripts', 'lib', 'state-root.cjs');
const SELF_IMPROVE_RESOLVER = join(
  REPO_ROOT,
  'skills',
  'self-improve',
  'scripts',
  'resolve-paths.mjs',
);

function buildHookEnv(
  extraEnv: Record<string, string> = {},
): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (v !== undefined) env[k] = v;
  }
  // Remove OMC_STATE_DIR from parent env so only extraEnv controls it.
  delete env.OMC_STATE_DIR;
  return { ...env, CLAUDE_PLUGIN_ROOT: REPO_ROOT, ...extraEnv };
}

/** Run a hook script synchronously and return the parsed JSON output. */
function runHook(
  scriptPath: string,
  input: Record<string, unknown>,
  extraEnv: Record<string, string> = {},
): Record<string, unknown> {
  const raw = execFileSync(NODE, [scriptPath], {
    input: JSON.stringify(input),
    encoding: 'utf-8',
    env: buildHookEnv(extraEnv),
    timeout: 15000,
  }).trim();
  return JSON.parse(raw) as Record<string, unknown>;
}

/** Run a hook script through the installed hook runner path and return parsed JSON output. */
function runHookViaRunner(
  scriptPath: string,
  input: Record<string, unknown>,
  extraEnv: Record<string, string> = {},
): Record<string, unknown> {
  const raw = execFileSync(NODE, [HOOK_RUNNER, scriptPath], {
    input: JSON.stringify(input),
    encoding: 'utf-8',
    env: buildHookEnv(extraEnv),
    timeout: 15000,
  }).trim();
  return JSON.parse(raw) as Record<string, unknown>;
}

/**
 * Compute the centralized .omc root path for a given project dir and state dir.
 * Temporarily sets OMC_STATE_DIR so getOmcRoot() returns the centralized path.
 */
function getCentralizedOmcRoot(projectDir: string, stateDir: string): string {
  const prev = process.env.OMC_STATE_DIR;
  try {
    process.env.OMC_STATE_DIR = stateDir;
    clearWorktreeCache();
    return getOmcRoot(projectDir);
  } finally {
    if (prev === undefined) {
      delete process.env.OMC_STATE_DIR;
    } else {
      process.env.OMC_STATE_DIR = prev;
    }
    clearWorktreeCache();
  }
}

function writeWorkflowTombstone(
  omcRoot: string,
  sessionId: string,
  mode: 'ralph' | 'ultrawork',
): void {
  const sessionDir = join(omcRoot, 'state', 'sessions', sessionId);
  mkdirSync(sessionDir, { recursive: true });
  writeFileSync(
    join(sessionDir, 'skill-active-state.json'),
    JSON.stringify(
      {
        version: 2,
        active_skills: {
          [mode]: {
            skill_name: mode,
            started_at: '2026-04-26T00:00:00.000Z',
            completed_at: new Date().toISOString(),
            session_id: sessionId,
            mode_state_path: `${mode}-state.json`,
            initialized_mode: mode,
            initialized_state_path: join(
              omcRoot,
              'state',
              `${mode}-state.json`,
            ),
            initialized_session_state_path: join(
              sessionDir,
              `${mode}-state.json`,
            ),
          },
        },
      },
      null,
      2,
    ),
  );
}

describe('OMC_STATE_DIR state-root resolution (issue #2532)', () => {
  let tempDir: string;
  let fakeProject: string;
  let fakeStateDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'omc-state-root-'));
    fakeProject = join(tempDir, 'project');
    fakeStateDir = join(tempDir, 'centralized-state');
    mkdirSync(fakeProject, { recursive: true });
    // session-start validateCwd requires a real workspace anchor (.git / .omc-workspace)
    mkdirSync(join(fakeProject, '.git'), { recursive: true });
    mkdirSync(fakeStateDir, { recursive: true });
    delete process.env.OMC_STATE_DIR;
    clearWorktreeCache();
  });

  afterEach(() => {
    delete process.env.OMC_STATE_DIR;
    clearWorktreeCache();
    rmSync(tempDir, { recursive: true, force: true });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 1. Default state dir (no OMC_STATE_DIR)
  // ────────────────────────────────────────────────────────────────────────────

  it('session-start reads ralph state from default .omc path when OMC_STATE_DIR is not set', () => {
    const sessionId = 'test-session-default';
    const stateDir = join(fakeProject, '.omc', 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Default-path task',
        iteration: 1,
        max_iterations: 5,
      }),
    );

    const output = runHook(SESSION_START, {
      hook_event_name: 'SessionStart',
      session_id: sessionId,
      cwd: fakeProject,
    });

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).toContain('[RALPH LOOP RESTORED]');
  });

  it('session-start ignores tombstoned stale ralph restore state after cancel', () => {
    const sessionId = 'test-session-tombstoned-ralph';
    const omcRoot = join(fakeProject, '.omc');
    const stateDir = join(omcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Tombstoned task must not restore',
        iteration: 12,
        max_iterations: 100,
      }),
    );
    writeWorkflowTombstone(omcRoot, sessionId, 'ralph');

    const output = runHook(SESSION_START, {
      hook_event_name: 'SessionStart',
      session_id: sessionId,
      cwd: fakeProject,
    });

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).not.toContain('[RALPH LOOP RESTORED]');
    expect(context).not.toContain('Tombstoned task must not restore');
  });

  it('session-start ignores tombstoned stale ultrawork restore state after cancel', () => {
    const sessionId = 'test-session-tombstoned-ultrawork';
    const omcRoot = join(fakeProject, '.omc');
    const stateDir = join(omcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ultrawork-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        started_at: '2026-04-26T00:00:00.000Z',
        original_prompt: 'Tombstoned ultrawork must not restore',
      }),
    );
    writeWorkflowTombstone(omcRoot, sessionId, 'ultrawork');

    const output = runHook(SESSION_START, {
      hook_event_name: 'SessionStart',
      session_id: sessionId,
      cwd: fakeProject,
    });

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).not.toContain('[ULTRAWORK MODE RESTORED]');
    expect(context).not.toContain('Tombstoned ultrawork must not restore');
  });

  it('session-start through run.cjs does not clean prior active state without durable abandonment evidence', () => {
    const priorSessionId = 'prior-runner-session';
    const currentSessionId = 'current-runner-session';

    const priorStateDir = join(
      fakeProject,
      '.omc',
      'state',
      'sessions',
      priorSessionId,
    );
    mkdirSync(priorStateDir, { recursive: true });
    writeFileSync(
      join(priorStateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: priorSessionId,
        prompt: 'Runner-created prior session state must survive',
        iteration: 1,
        max_iterations: 5,
      }),
    );

    runHookViaRunner(SESSION_START, {
      hook_event_name: 'SessionStart',
      session_id: priorSessionId,
      transcript_path: join(fakeProject, '.claude', 'projects', 'prior.jsonl'),
      source: 'startup',
      model: 'claude-sonnet-4-6',
      cwd: fakeProject,
    });

    const markerPath = join(priorStateDir, 'session-started.json');
    expect(existsSync(markerPath)).toBe(true);
    const marker = JSON.parse(readFileSync(markerPath, 'utf-8')) as Record<
      string,
      unknown
    >;
    expect(marker.session_id).toBe(priorSessionId);
    expect(marker.ppid).toBeUndefined();

    runHookViaRunner(SESSION_START, {
      hook_event_name: 'SessionStart',
      session_id: currentSessionId,
      transcript_path: join(
        fakeProject,
        '.claude',
        'projects',
        'current.jsonl',
      ),
      source: 'startup',
      model: 'claude-sonnet-4-6',
      cwd: fakeProject,
    });

    expect(existsSync(join(priorStateDir, 'ralph-state.json'))).toBe(true);
    expect(existsSync(markerPath)).toBe(true);
    expect(
      existsSync(
        join(
          fakeProject,
          '.omc',
          'state',
          'sessions',
          currentSessionId,
          'session-started.json',
        ),
      ),
    ).toBe(true);
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 2. Custom OMC_STATE_DIR — session-start
  // ────────────────────────────────────────────────────────────────────────────

  it('session-start reads ralph state from centralized path when OMC_STATE_DIR is set', () => {
    const sessionId = 'test-session-centralized';
    const centralizedOmcRoot = getCentralizedOmcRoot(fakeProject, fakeStateDir);
    const stateDir = join(centralizedOmcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Centralized-state task',
        iteration: 2,
        max_iterations: 10,
      }),
    );

    const output = runHook(
      SESSION_START,
      {
        hook_event_name: 'SessionStart',
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).toContain('[RALPH LOOP RESTORED]');
    expect(context).toContain('Centralized-state task');
  });

  it('session-start reads ultrawork state from centralized path when OMC_STATE_DIR is set', () => {
    const sessionId = 'test-session-uw-central';
    const centralizedOmcRoot = getCentralizedOmcRoot(fakeProject, fakeStateDir);
    const stateDir = join(centralizedOmcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ultrawork-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        started_at: '2026-01-01T00:00:00.000Z',
        original_prompt: 'Centralized ultrawork task',
      }),
    );

    const output = runHook(
      SESSION_START,
      {
        hook_event_name: 'SessionStart',
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).toContain('[ULTRAWORK MODE RESTORED]');
    expect(context).toContain('Centralized ultrawork task');
  });

  it('session-start does NOT restore state when OMC_STATE_DIR is set but state is only in default .omc', () => {
    const sessionId = 'test-session-only-default';
    // Place state ONLY in the default .omc location
    const defaultStateDir = join(
      fakeProject,
      '.omc',
      'state',
      'sessions',
      sessionId,
    );
    mkdirSync(defaultStateDir, { recursive: true });
    writeFileSync(
      join(defaultStateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Should not restore from default when OMC_STATE_DIR is set',
        iteration: 1,
        max_iterations: 5,
      }),
    );

    // Run with OMC_STATE_DIR pointing elsewhere — centralized location is empty
    const output = runHook(
      SESSION_START,
      {
        hook_event_name: 'SessionStart',
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).not.toContain('[RALPH LOOP RESTORED]');
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 3. Custom OMC_STATE_DIR — stop hook (persistent-mode.cjs)
  // ────────────────────────────────────────────────────────────────────────────

  it('stop hook blocks when active ralph state is in default .omc path (baseline)', () => {
    const sessionId = 'test-stop-default';
    const stateDir = join(fakeProject, '.omc', 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Stop hook baseline task',
        iteration: 1,
        max_iterations: 5,
        started_at: new Date().toISOString(),
        last_checked_at: new Date().toISOString(),
      }),
    );

    const output = runHook(STOP_HOOK, {
      hook_event_name: 'Stop',
      session_id: sessionId,
      cwd: fakeProject,
    });

    expect(output.decision).toBe('block');
    expect(String(output.reason)).toContain('[RALPH LOOP');
  });

  it('stop hook blocks when active ralph state is in centralized OMC_STATE_DIR path', () => {
    const sessionId = 'test-stop-centralized';
    const centralizedOmcRoot = getCentralizedOmcRoot(fakeProject, fakeStateDir);
    const stateDir = join(centralizedOmcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Stop hook centralized task',
        iteration: 1,
        max_iterations: 5,
        started_at: new Date().toISOString(),
        last_checked_at: new Date().toISOString(),
      }),
    );

    // No .omc in fakeProject — active state ONLY in centralized dir
    const output = runHook(
      STOP_HOOK,
      { hook_event_name: 'Stop', session_id: sessionId, cwd: fakeProject },
      { OMC_STATE_DIR: fakeStateDir },
    );

    expect(output.decision).toBe('block');
    expect(String(output.reason)).toContain('[RALPH LOOP');
  });

  it('stop hook does NOT block when OMC_STATE_DIR is set but state is only in default .omc', () => {
    const sessionId = 'test-stop-mismatch';
    // Place active state in default location only
    const defaultStateDir = join(
      fakeProject,
      '.omc',
      'state',
      'sessions',
      sessionId,
    );
    mkdirSync(defaultStateDir, { recursive: true });
    writeFileSync(
      join(defaultStateDir, 'ralph-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        prompt: 'Should be invisible to centralized hook',
        iteration: 1,
        max_iterations: 5,
      }),
    );

    // Run stop hook with OMC_STATE_DIR — centralized path is empty → no block
    const output = runHook(
      STOP_HOOK,
      { hook_event_name: 'Stop', session_id: sessionId, cwd: fakeProject },
      { OMC_STATE_DIR: fakeStateDir },
    );

    expect(output.decision).not.toBe('block');
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 4. pre-tool-enforcer.mjs (PreToolUse hook) — follow-up to #2532
  //    Scenario: enforcer must read team-state and write skill-active-state
  //    from the same centralized OMC_STATE_DIR location as sibling hooks.
  // ────────────────────────────────────────────────────────────────────────────

  it('pre-tool-enforcer injects [TEAM ROUTING REQUIRED] when team-state lives in default .omc (baseline)', () => {
    const sessionId = 'test-pte-team-default';
    const stateDir = join(fakeProject, '.omc', 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'team-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        team_name: 'alpha',
        current_phase: 'team-exec',
      }),
    );

    const output = runHook(PRE_TOOL_ENFORCER, {
      hook_event_name: 'PreToolUse',
      tool_name: 'Task',
      tool_input: { subagent_type: 'executor', description: 'sample task' },
      session_id: sessionId,
      cwd: fakeProject,
    });

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).toContain('[TEAM ROUTING REQUIRED]');
    expect(context).toContain('alpha');
  });

  it('pre-tool-enforcer injects [TEAM ROUTING REQUIRED] when team-state lives in centralized OMC_STATE_DIR', () => {
    const sessionId = 'test-pte-team-central';
    const centralizedOmcRoot = getCentralizedOmcRoot(fakeProject, fakeStateDir);
    const stateDir = join(centralizedOmcRoot, 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'team-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        team_name: 'beta',
        current_phase: 'team-exec',
      }),
    );

    // No .omc in fakeProject — active team-state ONLY in centralized dir
    const output = runHook(
      PRE_TOOL_ENFORCER,
      {
        hook_event_name: 'PreToolUse',
        tool_name: 'Task',
        tool_input: { subagent_type: 'executor', description: 'sample task' },
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).toContain('[TEAM ROUTING REQUIRED]');
    expect(context).toContain('beta');
  });

  it('pre-tool-enforcer ignores stale team-state in default .omc when OMC_STATE_DIR is set', () => {
    const sessionId = 'test-pte-team-mismatch';
    // Place active team-state in default location only
    const stateDir = join(fakeProject, '.omc', 'state', 'sessions', sessionId);
    mkdirSync(stateDir, { recursive: true });
    writeFileSync(
      join(stateDir, 'team-state.json'),
      JSON.stringify({
        active: true,
        session_id: sessionId,
        team_name: 'gamma',
        current_phase: 'team-exec',
      }),
    );

    // Run with OMC_STATE_DIR pointing elsewhere — centralized path is empty → no redirect
    const output = runHook(
      PRE_TOOL_ENFORCER,
      {
        hook_event_name: 'PreToolUse',
        tool_name: 'Task',
        tool_input: { subagent_type: 'executor', description: 'sample task' },
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(context).not.toContain('[TEAM ROUTING REQUIRED]');
  });

  it('pre-tool-enforcer writes skill-active-state into the centralized OMC_STATE_DIR path', () => {
    const sessionId = 'test-pte-skill-central';
    const centralizedOmcRoot = getCentralizedOmcRoot(fakeProject, fakeStateDir);

    runHook(
      PRE_TOOL_ENFORCER,
      {
        hook_event_name: 'PreToolUse',
        tool_name: 'Skill',
        // `skill` needs a non-'none' protection level. The OMC-prefixed `skill`
        // slash-command maps to 'light' protection, which triggers the write.
        tool_input: { skill: 'oh-my-claudecode:skill' },
        session_id: sessionId,
        cwd: fakeProject,
      },
      { OMC_STATE_DIR: fakeStateDir },
    );

    const centralizedPath = join(
      centralizedOmcRoot,
      'state',
      'sessions',
      sessionId,
      'skill-active-state.json',
    );
    const defaultPath = join(
      fakeProject,
      '.omc',
      'state',
      'sessions',
      sessionId,
      'skill-active-state.json',
    );
    expect(existsSync(centralizedPath)).toBe(true);
    expect(existsSync(defaultPath)).toBe(false);
  });
});

describe('state-root resolver consolidation precondition (bead 5ki.1)', () => {
  const tempRoots: string[] = [];

  function makeTempRoot(prefix: string): string {
    const root = mkdtempSync(join(tmpdir(), prefix));
    tempRoots.push(root);
    return root;
  }

  function git(cwd: string, args: string[]): string {
    return execFileSync('git', args, {
      cwd,
      encoding: 'utf-8',
      stdio: 'pipe',
      timeout: 15000,
    }).trim();
  }

  function initGitRepo(root: string, commit = false): void {
    mkdirSync(root, { recursive: true });
    git(root, ['init', '--quiet']);
    if (!commit) return;
    writeFileSync(join(root, 'fixture.txt'), 'fixture\n');
    git(root, ['add', 'fixture.txt']);
    git(root, [
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.test',
      'commit',
      '--quiet',
      '-m',
      'fixture',
    ]);
  }

  function buildResolverEnv(
    extraEnv: Record<string, string> = {},
  ): Record<string, string> {
    const env = buildHookEnv(extraEnv);
    if (!Object.hasOwn(extraEnv, 'OMC_DISABLE_MULTIREPO')) {
      delete env.OMC_DISABLE_MULTIREPO;
    }
    return env;
  }

  function runStateRootResolver(
    modulePath: string,
    cwd: string,
    extraEnv: Record<string, string> = {},
  ): string {
    const source = modulePath.endsWith('.cjs')
      ? [
          'const resolver = require(process.argv[1]);',
          'Promise.resolve(resolver.resolveOmcStateRoot(process.cwd()))',
          '  .then((value) => process.stdout.write(`${value}\\n`))',
          '  .catch((error) => { console.error(error); process.exit(1); });',
        ].join('\n')
      : [
          "const { pathToFileURL } = require('node:url');",
          'import(pathToFileURL(process.argv[1]).href)',
          '  .then((resolver) => resolver.resolveOmcStateRoot(process.cwd()))',
          '  .then((value) => process.stdout.write(`${value}\\n`))',
          '  .catch((error) => { console.error(error); process.exit(1); });',
        ].join('\n');

    return execFileSync(NODE, ['-e', source, modulePath], {
      cwd,
      encoding: 'utf-8',
      env: buildResolverEnv(extraEnv),
      timeout: 15000,
    }).trim();
  }

  function normalizeBehaviorPath(path: string): string {
    const suffix: string[] = [];
    let existing = path;
    while (!existsSync(existing)) {
      const parent = dirname(existing);
      if (parent === existing) break;
      suffix.unshift(basename(existing));
      existing = parent;
    }
    return join(realpathSync(existing), ...suffix);
  }

  function expectRoot(
    caseNumber: number,
    actual: string,
    expected: string,
    detail = '',
  ): void {
    const normalizedActual = normalizeBehaviorPath(actual);
    const normalizedExpected = normalizeBehaviorPath(expected);
    expect(
      normalizedActual,
      `case ${caseNumber}${detail ? ` (${detail})` : ''}: expected root ${normalizedExpected}; actual root ${normalizedActual}`,
    ).toBe(normalizedExpected);
  }

  function marker(root: string): void {
    writeFileSync(join(root, '.omc-workspace'), '{}\n');
  }

  afterEach(() => {
    delete process.env.OMC_STATE_DIR;
    delete process.env.OMC_DISABLE_MULTIREPO;
    clearWorktreeCache();
    while (tempRoots.length > 0) {
      rmSync(tempRoots.pop()!, { recursive: true, force: true });
    }
  });

  it('case 01: repo root without marker anchors .omc at repo root', () => {
    const fixture = makeTempRoot('omc-state-root-case-01-');
    const repoRoot = join(fixture, 'repo');
    initGitRepo(repoRoot);

    expectRoot(
      1,
      runStateRootResolver(STATE_ROOT_ESM, repoRoot),
      join(repoRoot, '.omc'),
    );
  });

  it('case 02: deep git-repo subdirectory anchors .omc at repo root', () => {
    const fixture = makeTempRoot('omc-state-root-case-02-');
    const repoRoot = join(fixture, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });

    expectRoot(
      2,
      runStateRootResolver(STATE_ROOT_ESM, cwd),
      join(repoRoot, '.omc'),
    );
  });

  it('case 03: sub-repo under marker parent anchors .omc at parent', () => {
    const workspaceRoot = makeTempRoot('omc-state-root-case-03-');
    const repoRoot = join(workspaceRoot, 'repo');
    marker(workspaceRoot);
    initGitRepo(repoRoot);

    expectRoot(
      3,
      runStateRootResolver(STATE_ROOT_ESM, repoRoot),
      join(workspaceRoot, '.omc'),
    );
  });

  it('case 04: deep subdirectory of marker-parent sub-repo anchors .omc at parent', () => {
    const workspaceRoot = makeTempRoot('omc-state-root-case-04-');
    const repoRoot = join(workspaceRoot, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    marker(workspaceRoot);
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });

    expectRoot(
      4,
      runStateRootResolver(STATE_ROOT_ESM, cwd),
      join(workspaceRoot, '.omc'),
    );
  });

  it('case 05: OMC_STATE_DIR wins when workspace marker is present', () => {
    const workspaceRoot = makeTempRoot('omc-state-root-case-05-');
    const repoRoot = join(workspaceRoot, 'repo');
    const stateDir = join(workspaceRoot, 'centralized');
    marker(workspaceRoot);
    initGitRepo(repoRoot);
    mkdirSync(stateDir, { recursive: true });

    expectRoot(
      5,
      runStateRootResolver(STATE_ROOT_ESM, repoRoot, {
        OMC_STATE_DIR: stateDir,
      }),
      getCentralizedOmcRoot(realpathSync(repoRoot), stateDir),
    );
  });

  it('case 06: OMC_STATE_DIR project identity derives from climbed repo root', () => {
    const fixture = makeTempRoot('omc-state-root-case-06-');
    const repoRoot = join(fixture, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    const stateDir = join(fixture, 'centralized');
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });
    mkdirSync(stateDir, { recursive: true });

    expectRoot(
      6,
      runStateRootResolver(STATE_ROOT_ESM, cwd, {
        OMC_STATE_DIR: stateDir,
      }),
      getCentralizedOmcRoot(realpathSync(repoRoot), stateDir),
    );
  });

  it('case 07: submodule uses superproject location and its own centralized identity', () => {
    const fixture = makeTempRoot('omc-state-root-case-07-');
    const sourceRoot = join(fixture, 'submodule-source');
    const superprojectRoot = join(fixture, 'superproject');
    const submoduleRoot = join(superprojectRoot, 'modules', 'child');
    const cwd = join(submoduleRoot, 'deep');
    const stateDir = join(fixture, 'centralized');
    initGitRepo(sourceRoot, true);
    initGitRepo(superprojectRoot, true);
    git(superprojectRoot, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      '--quiet',
      sourceRoot,
      'modules/child',
    ]);
    mkdirSync(cwd, { recursive: true });
    mkdirSync(stateDir, { recursive: true });

    const locationRoot = runStateRootResolver(STATE_ROOT_ESM, cwd);
    expect
      .soft(
        normalizeBehaviorPath(locationRoot),
        `case 7 (location): expected root ${normalizeBehaviorPath(join(superprojectRoot, '.omc'))}; actual root ${normalizeBehaviorPath(locationRoot)}`,
      )
      .toBe(normalizeBehaviorPath(join(superprojectRoot, '.omc')));

    expectRoot(
      7,
      runStateRootResolver(STATE_ROOT_ESM, cwd, {
        OMC_STATE_DIR: stateDir,
      }),
      getCentralizedOmcRoot(realpathSync(submoduleRoot), stateDir),
      'centralized identity',
    );
  });

  it('case 08: linked-worktree subdirectory anchors .omc at linked worktree root', () => {
    const fixture = makeTempRoot('omc-state-root-case-08-');
    const mainRoot = join(fixture, 'main');
    const linkedRoot = join(fixture, 'linked');
    const cwd = join(linkedRoot, 'deep', 'nested');
    initGitRepo(mainRoot, true);
    git(mainRoot, [
      'worktree',
      'add',
      '--quiet',
      '-b',
      'fixture-linked',
      linkedRoot,
    ]);
    mkdirSync(cwd, { recursive: true });

    expectRoot(
      8,
      runStateRootResolver(STATE_ROOT_ESM, cwd),
      join(linkedRoot, '.omc'),
    );
  });

  it('case 09: filesystem walk rescues repo root when git rev-parse fails', () => {
    const fixture = makeTempRoot('omc-state-root-case-09-');
    const repoRoot = join(fixture, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    const emptyPath = join(fixture, 'empty-path');
    mkdirSync(join(repoRoot, '.git'), { recursive: true });
    mkdirSync(cwd, { recursive: true });
    mkdirSync(emptyPath, { recursive: true });

    expectRoot(
      9,
      runStateRootResolver(STATE_ROOT_ESM, cwd, { PATH: emptyPath }),
      join(repoRoot, '.omc'),
    );
  });

  it('case 10: non-git directory without marker remains raw-directory anchored', () => {
    const cwd = makeTempRoot('omc-state-root-case-10-');

    expectRoot(
      10,
      runStateRootResolver(STATE_ROOT_ESM, cwd),
      join(cwd, '.omc'),
    );
  });

  it('case 11: OMC_DISABLE_MULTIREPO ignores marker but still climbs to git root', () => {
    const workspaceRoot = makeTempRoot('omc-state-root-case-11-');
    const repoRoot = join(workspaceRoot, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    marker(workspaceRoot);
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });

    expectRoot(
      11,
      runStateRootResolver(STATE_ROOT_ESM, cwd, {
        OMC_DISABLE_MULTIREPO: '1',
      }),
      join(repoRoot, '.omc'),
    );
  });

  it('case 12: state-root.cjs matches cases 1-4', () => {
    const plainFixture = makeTempRoot('omc-state-root-case-12-plain-');
    const plainRepo = join(plainFixture, 'repo');
    const plainDeep = join(plainRepo, 'deep');
    initGitRepo(plainRepo);
    mkdirSync(plainDeep, { recursive: true });

    const workspaceRoot = makeTempRoot('omc-state-root-case-12-workspace-');
    const workspaceRepo = join(workspaceRoot, 'repo');
    const workspaceDeep = join(workspaceRepo, 'deep');
    marker(workspaceRoot);
    initGitRepo(workspaceRepo);
    mkdirSync(workspaceDeep, { recursive: true });

    const scenarios = [
      [plainRepo, join(plainRepo, '.omc'), 'case 1'],
      [plainDeep, join(plainRepo, '.omc'), 'case 2'],
      [workspaceRepo, join(workspaceRoot, '.omc'), 'case 3'],
      [workspaceDeep, join(workspaceRoot, '.omc'), 'case 4'],
    ] as const;

    for (const [cwd, expected, detail] of scenarios) {
      const actual = runStateRootResolver(STATE_ROOT_CJS, cwd);
      expect
        .soft(
          normalizeBehaviorPath(actual),
          `case 12 (${detail}): expected root ${normalizeBehaviorPath(expected)}; actual root ${normalizeBehaviorPath(actual)}`,
        )
        .toBe(normalizeBehaviorPath(expected));
    }
  });

  it('case 13: marker below git root wins from deeper cwd', () => {
    const fixture = makeTempRoot('omc-state-root-case-13-');
    const repoRoot = join(fixture, 'repo');
    const markerRoot = join(repoRoot, 'packages');
    const cwd = join(markerRoot, 'service', 'deep');
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });
    marker(markerRoot);

    expectRoot(
      13,
      runStateRootResolver(STATE_ROOT_ESM, cwd),
      join(markerRoot, '.omc'),
    );
  });

  it('case 14: self-improve resolver without --project-root anchors at repo root', () => {
    const fixture = makeTempRoot('omc-state-root-case-14-');
    const repoRoot = join(fixture, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });

    const raw = execFileSync(NODE, [SELF_IMPROVE_RESOLVER], {
      cwd,
      encoding: 'utf-8',
      env: buildResolverEnv(),
      timeout: 15000,
    });
    const paths = JSON.parse(raw) as { base_root: string };
    expectRoot(14, paths.base_root, join(repoRoot, '.omc', 'self-improve'));
  });

  it('case 15: team writer and reader agree when launched from repo subdirectory', () => {
    const fixture = makeTempRoot('omc-state-root-case-15-');
    const repoRoot = join(fixture, 'repo');
    const cwd = join(repoRoot, 'deep', 'nested');
    const sessionId = 'state-root-case-15';
    initGitRepo(repoRoot);
    mkdirSync(cwd, { recursive: true });

    const writerPath = absPath(
      cwd,
      join('.omc', 'state', 'sessions', sessionId, 'team-state.json'),
    );
    mkdirSync(dirname(writerPath), { recursive: true });
    writeFileSync(
      writerPath,
      JSON.stringify({
        active: true,
        session_id: sessionId,
        team_name: 'state-root-case-15',
        current_phase: 'team-exec',
      }),
    );

    expectRoot(
      15,
      writerPath,
      join(repoRoot, '.omc', 'state', 'sessions', sessionId, 'team-state.json'),
      'writer',
    );

    const output = runHook(PRE_TOOL_ENFORCER, {
      hook_event_name: 'PreToolUse',
      tool_name: 'Task',
      tool_input: { subagent_type: 'executor', description: 'fixture task' },
      session_id: sessionId,
      cwd,
    });
    const context =
      (output as { hookSpecificOutput?: { additionalContext?: string } })
        .hookSpecificOutput?.additionalContext ?? '';
    expect(
      context,
      `case 15 (reader): expected getActiveTeamState() to find ${writerPath}; actual context ${JSON.stringify(context)}`,
    ).toContain('[TEAM ROUTING REQUIRED]');
  });
});
