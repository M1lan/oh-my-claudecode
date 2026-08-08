/**
 * Regression tests for interop tier-1 hardening:
 *  - #1 unlocked read-modify-write races (markMessageAsRead)
 *  - #4b path-traversal guards on OMX team/worker names
 *
 * Note: direct OMX mailbox write helpers (sendOmxDirectMessage,
 * broadcastOmxMessage) were removed — the OMX mutation contract routes all
 * mailbox writes through `omx team api`. Traversal guards are exercised via
 * the remaining read paths.
 */

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  mkdtempSync,
  rmSync,
  readFileSync,
  existsSync,
  writeFileSync,
} from 'fs';
import { spawnSync } from 'child_process';
import { join } from 'path';
import { tmpdir } from 'os';

describe('omx team path traversal guards', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'omx-path-guard-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('rejects traversal in teamName', async () => {
    const { listOmxTasks } = await import('../omx-team-state.js');
    await expect(listOmxTasks('../../etc', tempDir)).rejects.toThrow(
      /OMX team boundary/,
    );
  });

  it('rejects traversal in workerName', async () => {
    const { markOmxMessageDelivered } = await import('../omx-team-state.js');
    await expect(
      markOmxMessageDelivered('alpha', '../../evil', 'msg-1', tempDir),
    ).rejects.toThrow(/OMX team boundary/);
  });

  it('allows ordinary team/worker names', async () => {
    const { listOmxMailboxMessages } = await import('../omx-team-state.js');
    const messages = await listOmxMailboxMessages(
      'alpha-team',
      'worker-1',
      tempDir,
    );
    expect(messages).toEqual([]);
  });
});

describe('shared-state markMessageAsRead locking', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'shared-msg-lock-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('markMessageAsRead wraps the read-modify-write in withFileLockSync', () => {
    const source = readFileSync(
      join(__dirname, '..', 'shared-state.ts'),
      'utf-8',
    );
    const fnMatch = source.match(
      /export function markMessageAsRead[\s\S]*?^}/m,
    );
    expect(fnMatch).toBeTruthy();
    const fnBody = fnMatch![0];
    expect(fnBody).toContain('withFileLockSync');
    expect(fnBody).toContain("messagePath + '.lock'");
  });

  it('marks a message read and leaves no lock file behind', async () => {
    const {
      addSharedMessage,
      markMessageAsRead,
      readSharedMessages,
      initInteropSession,
    } = await import('../shared-state.js');

    initInteropSession('session-1', tempDir);
    const message = addSharedMessage(tempDir, {
      source: 'omc',
      target: 'omx',
      content: 'hello',
    });

    expect(markMessageAsRead(tempDir, message.id)).toBe(true);
    const [stored] = readSharedMessages(tempDir);
    expect(stored.read).toBe(true);

    const lockPath = join(
      tempDir,
      '.omc',
      'state',
      'interop',
      'messages',
      `${message.id}.json.lock`,
    );
    expect(existsSync(lockPath)).toBe(false);
  });
});

describe('interop OMX restart state', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'interop-omx-restart-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('persists the exact launch command and pending readiness', async () => {
    const { initInteropSession, readInteropConfig } = await import(
      '../shared-state.js'
    );

    initInteropSession('session-1', tempDir, tempDir, {
      multiplexerServerId: '/socket/server-a',
      omxLaunchCommand: "exec 'bash' -lc 'codex'",
      omxReadiness: 'pending',
    });

    expect(readInteropConfig(tempDir)).toMatchObject({
      omxLaunchCommand: "exec 'bash' -lc 'codex'",
      omxReadiness: 'pending',
    });
  });

  it('records the pane without losing the stored launch command', async () => {
    const {
      initInteropSession,
      readInteropConfig,
      updateInteropOmxRuntime,
    } = await import('../shared-state.js');

    initInteropSession('session-1', tempDir, tempDir, {
      multiplexerServerId: '/socket/server-a',
      omxLaunchCommand: "exec 'bash' -lc 'codex'",
      omxReadiness: 'pending',
    });
    updateInteropOmxRuntime(tempDir, {
      omxPaneId: '%9',
      omxSessionId: '$2',
      omxWindowId: '@4',
      omxReadiness: 'pending',
    });

    expect(readInteropConfig(tempDir)).toMatchObject({
      omxPaneId: '%9',
      omxSessionId: '$2',
      omxWindowId: '@4',
      omxLaunchCommand: "exec 'bash' -lc 'codex'",
      omxReadiness: 'pending',
    });
  });

  it('reports lock contention instead of claiming runtime persistence', async () => {
    const { getInteropDir, initInteropSession, updateInteropOmxRuntime } =
      await import('../shared-state.js');

    initInteropSession('session-1', tempDir, tempDir, {
      multiplexerServerId: '/socket/server-a',
      omxLaunchCommand: "exec 'bash' -lc 'codex'",
      omxReadiness: 'pending',
    });
    const lockPath = join(getInteropDir(tempDir), 'config.json.lock');
    writeFileSync(
      lockPath,
      JSON.stringify({ pid: process.pid, timestamp: Date.now() }),
    );

    expect(() =>
      updateInteropOmxRuntime(tempDir, { omxPaneId: '%9' }),
    ).toThrow(/Failed to acquire file lock/);
  });
});

describe('interop session ownership', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'interop-session-owner-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('refuses to replace another active session in the same workspace', async () => {
    const { initInteropSession, readInteropConfig } = await import(
      '../shared-state.js'
    );

    initInteropSession('session-a', tempDir, tempDir);

    expect(() =>
      initInteropSession('session-b', tempDir, tempDir),
    ).toThrow(/already active/);
    expect(readInteropConfig(tempDir)?.sessionId).toBe('session-a');
  });

  it('allows a new session after the previous session completed', async () => {
    const { initInteropSession, readInteropConfig, updateInteropStatus } =
      await import('../shared-state.js');

    initInteropSession('session-a', tempDir, tempDir);
    updateInteropStatus(tempDir, 'completed', 'session-a');
    initInteropSession('session-b', tempDir, tempDir);

    expect(readInteropConfig(tempDir)?.sessionId).toBe('session-b');
    expect(readInteropConfig(tempDir)?.status).toBe('active');
  });

  it('ignores teardown from a session that no longer owns config.json', async () => {
    const { initInteropSession, readInteropConfig, updateInteropStatus } =
      await import('../shared-state.js');

    initInteropSession('session-a', tempDir, tempDir);
    updateInteropStatus(tempDir, 'completed', 'session-b');

    expect(readInteropConfig(tempDir)).toMatchObject({
      sessionId: 'session-a',
      status: 'active',
    });
  });

  it('records the launcher pid in config.json', async () => {
    const { initInteropSession, readInteropConfig } = await import(
      '../shared-state.js'
    );

    initInteropSession('session-a', tempDir, tempDir);

    expect(readInteropConfig(tempDir)?.omcPid).toBe(process.pid);
  });

  it('reclaims a stale active session whose owner pid is dead', async () => {
    const { getInteropDir, initInteropSession, readInteropConfig } =
      await import('../shared-state.js');

    initInteropSession('session-a', tempDir, tempDir);

    // Simulate a crashed launcher: rewrite the config with the pid of a
    // process that has already exited.
    const exited = spawnSync(process.execPath, ['--version']);
    const configPath = join(getInteropDir(tempDir), 'config.json');
    const stale = JSON.parse(readFileSync(configPath, 'utf-8'));
    stale.omcPid = exited.pid;
    writeFileSync(configPath, JSON.stringify(stale));

    initInteropSession('session-b', tempDir, tempDir);

    expect(readInteropConfig(tempDir)).toMatchObject({
      sessionId: 'session-b',
      status: 'active',
    });
  });

  it('reclaims an active session written by a build without a recorded pid', async () => {
    const { getInteropDir, initInteropSession, readInteropConfig } =
      await import('../shared-state.js');

    initInteropSession('session-a', tempDir, tempDir);

    // Configs from pre-pid builds have no verifiable owner; a crashed
    // launcher must not block interop forever.
    const configPath = join(getInteropDir(tempDir), 'config.json');
    const legacy = JSON.parse(readFileSync(configPath, 'utf-8'));
    delete legacy.omcPid;
    writeFileSync(configPath, JSON.stringify(legacy));

    initInteropSession('session-b', tempDir, tempDir);

    expect(readInteropConfig(tempDir)?.sessionId).toBe('session-b');
  });

  it('replaces a live session when force is set', async () => {
    const { initInteropSession, readInteropConfig } = await import(
      '../shared-state.js'
    );

    initInteropSession('session-a', tempDir, tempDir);

    expect(() => initInteropSession('session-b', tempDir, tempDir)).toThrow(
      /already active/,
    );

    initInteropSession('session-b', tempDir, tempDir, {}, { force: true });

    expect(readInteropConfig(tempDir)?.sessionId).toBe('session-b');
  });
});
