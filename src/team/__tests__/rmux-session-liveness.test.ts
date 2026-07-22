import { describe, expect, it, vi, beforeEach } from 'vitest';

const tmuxMocks = vi.hoisted(() => ({
  rmuxCmdAsync: vi.fn(),
}));

vi.mock('../../cli/rmux-utils.js', () => ({
  rmuxExec: vi.fn(),
  rmuxExecAsync: vi.fn(),
  rmuxShell: vi.fn(),
  rmuxCmdAsync: tmuxMocks.rmuxCmdAsync,
}));

import { getWorkerLiveness } from '../rmux-session.js';

describe('getWorkerLiveness', () => {
  beforeEach(() => {
    tmuxMocks.rmuxCmdAsync.mockReset();
  });

  it('returns alive when tmux reports pane_dead=0', async () => {
    tmuxMocks.rmuxCmdAsync.mockResolvedValueOnce({ stdout: '0\n', stderr: '' });

    await expect(getWorkerLiveness('%1')).resolves.toBe('alive');
  });

  it('returns dead when tmux reports pane_dead=1', async () => {
    tmuxMocks.rmuxCmdAsync.mockResolvedValueOnce({ stdout: '1\n', stderr: '' });

    await expect(getWorkerLiveness('%1')).resolves.toBe('dead');
  });

  it('treats missing pane errors as dead after successful cleanup kills', async () => {
    const error = new Error('display-message failed') as Error & {
      stderr?: string;
    };
    error.stderr = "can't find pane: %1";
    tmuxMocks.rmuxCmdAsync.mockRejectedValueOnce(error);

    await expect(getWorkerLiveness('%1')).resolves.toBe('dead');
  });

  it('keeps ambiguous tmux failures unknown', async () => {
    const error = new Error('tmux server unavailable') as Error & {
      stderr?: string;
    };
    error.stderr =
      'error connecting to /tmp/tmux-1000/default (No such file or directory)';
    tmuxMocks.rmuxCmdAsync.mockRejectedValueOnce(error);

    await expect(getWorkerLiveness('%1')).resolves.toBe('unknown');
  });
});
