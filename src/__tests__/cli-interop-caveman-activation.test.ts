/**
 * Tests for the readiness-gated caveman activation: on rmux the activation is
 * preceded by a `wait-pane --quiet` readiness wait so keystrokes are not
 * swallowed while the codex TUI starts; on plain tmux the send-keys pair fires
 * immediately as before. Wait failures must never suppress the activation.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../cli/rmux-utils.js', async (importOriginal) => {
  const actual =
    await importOriginal<typeof import('../cli/rmux-utils.js')>();
  return {
    ...actual,
    rmuxExec: vi.fn(),
    resolveRmuxInvocation: vi.fn(),
  };
});

import { rmuxExec, resolveRmuxInvocation } from '../cli/rmux-utils.js';
import {
  sendInteropCavemanActivation,
  INTEROP_CAVEMAN_ACTIVATION,
} from '../cli/interop.js';

const mockedRmuxExec = vi.mocked(rmuxExec);
const mockedResolveRmuxInvocation = vi.mocked(resolveRmuxInvocation);

const RMUX_INVOCATION = { bin: '/x/rmux', socketArgs: ['-S', '/tmp/sock'] };

describe('sendInteropCavemanActivation readiness gating', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockedRmuxExec.mockReturnValue('');
  });

  it('waits for pane readiness before sending keys on rmux', () => {
    mockedResolveRmuxInvocation.mockReturnValue(RMUX_INVOCATION);

    sendInteropCavemanActivation('%5');

    expect(mockedRmuxExec).toHaveBeenCalledTimes(3);
    expect(mockedRmuxExec.mock.calls[0][0]).toEqual([
      'wait-pane',
      '-t',
      '%5',
      '--quiet',
      '--stable-for',
      '500ms',
      '--timeout',
      '15s',
    ]);
    expect(mockedRmuxExec.mock.calls[1][0]).toEqual([
      'send-keys',
      '-t',
      '%5',
      '-l',
      INTEROP_CAVEMAN_ACTIVATION,
    ]);
    expect(mockedRmuxExec.mock.calls[2][0]).toEqual([
      'send-keys',
      '-t',
      '%5',
      'Enter',
    ]);
  });

  it('still sends keys when the readiness wait fails', () => {
    mockedResolveRmuxInvocation.mockReturnValue(RMUX_INVOCATION);
    mockedRmuxExec.mockImplementationOnce(() => {
      throw new Error('wait-pane timeout');
    });

    sendInteropCavemanActivation('%5');

    expect(mockedRmuxExec).toHaveBeenCalledTimes(3);
    expect(mockedRmuxExec.mock.calls[1][0][0]).toBe('send-keys');
    expect(mockedRmuxExec.mock.calls[2][0][0]).toBe('send-keys');
  });

  it('skips the readiness wait on plain tmux', () => {
    mockedResolveRmuxInvocation.mockReturnValue(null);

    sendInteropCavemanActivation('%7');

    expect(mockedRmuxExec).toHaveBeenCalledTimes(2);
    expect(mockedRmuxExec.mock.calls[0][0]).toEqual([
      'send-keys',
      '-t',
      '%7',
      '-l',
      INTEROP_CAVEMAN_ACTIVATION,
    ]);
    expect(mockedRmuxExec.mock.calls[1][0]).toEqual([
      'send-keys',
      '-t',
      '%7',
      'Enter',
    ]);
  });
});
