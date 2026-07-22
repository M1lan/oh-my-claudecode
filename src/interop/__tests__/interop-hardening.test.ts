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
import { mkdtempSync, rmSync, readFileSync, existsSync } from 'fs';
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
