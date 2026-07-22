import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('child_process', async (importOriginal) => {
  const actual = await importOriginal<typeof import('child_process')>();
  return {
    ...actual,
    execSync: vi.fn(),
    // The tmux-command resolution ladder now probes for a plain `rmux`
    // binary on PATH (POSIX only) before falling back to literal `tmux`.
    // Pin that probe to "absent" so the 'tmux -V' assertions below stay
    // deterministic regardless of whether rmux is installed on the host
    // running the test.
    spawnSync: vi.fn(() => ({
      status: 1,
      stdout: '',
      stderr: '',
      pid: 0,
      output: [],
      signal: null,
    })),
  };
});

import { execSync } from 'child_process';
import { __resetRmuxBinaryPathCache } from '../../cli/tmux-utils.js';
import { validateTmux } from '../tmux-session.js';

const mockedExecSync = vi.mocked(execSync);

afterEach(() => {
  vi.restoreAllMocks();
  __resetRmuxBinaryPathCache();
});

describe('validateTmux', () => {
  it('skips probing when tmux context is already active', () => {
    mockedExecSync.mockImplementation(() => {
      throw new Error('should not probe');
    });

    expect(() => validateTmux(true)).not.toThrow();
    expect(mockedExecSync).not.toHaveBeenCalled();
  });

  it('probes tmux when context is absent', () => {
    mockedExecSync.mockReturnValue(Buffer.from('tmux 3.4'));

    expect(() => validateTmux(false)).not.toThrow();
    expect(mockedExecSync).toHaveBeenCalledWith(
      'tmux -V',
      expect.objectContaining({
        encoding: 'utf-8',
        timeout: 5000,
        stdio: 'pipe',
      }),
    );
  });

  it('throws install guidance when tmux is unavailable outside context', () => {
    mockedExecSync.mockImplementation(() => {
      throw new Error('tmux missing');
    });

    expect(() => validateTmux(false)).toThrow(/tmux is not available/i);
  });
});
