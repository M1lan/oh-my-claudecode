import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  rmuxExec: vi.fn(),
  rmuxExecAsync: vi.fn(),
}));

vi.mock('../rmux-utils.js', () => ({
  rmuxExec: mocks.rmuxExec,
  rmuxExecAsync: mocks.rmuxExecAsync,
}));

import {
  configureTmuxClipboardForCurrentSession,
  configureTmuxClipboardForSession,
  configureTmuxClipboardForSessionAsync,
  hasUniversalClipboardTerminalFeature,
} from '../rmux-clipboard.js';

describe('tmux clipboard configuration', () => {
  beforeEach(() => {
    mocks.rmuxExec.mockReset();
    mocks.rmuxExecAsync.mockReset();
  });

  it('detects universal clipboard terminal-features entries', () => {
    expect(hasUniversalClipboardTerminalFeature('xterm*:clipboard:focus')).toBe(
      false,
    );
    expect(
      hasUniversalClipboardTerminalFeature(
        'xterm*:clipboard:focus\n*:clipboard',
      ),
    ).toBe(true);
    expect(
      hasUniversalClipboardTerminalFeature(
        'xterm*:clipboard:focus,*:clipboard',
      ),
    ).toBe(true);
    expect(hasUniversalClipboardTerminalFeature('*:clipboard:ccolour')).toBe(
      true,
    );
  });

  it('sets session-scoped clipboard options and appends universal terminal clipboard when missing', () => {
    mocks.rmuxExec.mockImplementation((args: string[]) => {
      if (args[0] === 'show-options') return 'xterm*:clipboard:focus\n';
      return '';
    });

    configureTmuxClipboardForSession('omc-session', {
      stripTmux: true,
      stdio: 'ignore',
    });

    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      ['set-option', '-t', 'omc-session', 'set-clipboard', 'on'],
      { stripTmux: true, stdio: 'ignore' },
    );
    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      ['show-options', '-t', 'omc-session', '-v', 'terminal-features'],
      { stripTmux: true, stdio: 'ignore' },
    );
    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      ['set-option', '-at', 'omc-session', 'terminal-features', ',*:clipboard'],
      { stripTmux: true, stdio: 'ignore' },
    );
  });

  it('does not append terminal-features when universal clipboard is already present', () => {
    mocks.rmuxExec.mockImplementation((args: string[]) => {
      if (args[0] === 'show-options') return '*:clipboard\n';
      return '';
    });

    configureTmuxClipboardForSession('omc-session');

    expect(mocks.rmuxExec).not.toHaveBeenCalledWith(
      ['set-option', '-at', 'omc-session', 'terminal-features', ',*:clipboard'],
      expect.anything(),
    );
  });

  it('resolves the current tmux session before applying current-session clipboard settings', () => {
    mocks.rmuxExec.mockImplementation((args: string[]) => {
      if (args[0] === 'display-message') return 'current-session\n';
      if (args[0] === 'show-options') return 'screen*:title\n';
      return '';
    });

    configureTmuxClipboardForCurrentSession({ stdio: 'ignore' });

    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      ['display-message', '-p', '#S'],
      { stdio: 'ignore' },
    );
    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      ['set-option', '-t', 'current-session', 'set-clipboard', 'on'],
      { stdio: 'ignore' },
    );
    expect(mocks.rmuxExec).toHaveBeenCalledWith(
      [
        'set-option',
        '-at',
        'current-session',
        'terminal-features',
        ',*:clipboard',
      ],
      { stdio: 'ignore' },
    );
  });

  it('supports async tmux launch paths', async () => {
    mocks.rmuxExecAsync.mockImplementation(async (args: string[]) => {
      if (args[0] === 'show-options')
        return { stdout: 'screen*:title\n', stderr: '' };
      return { stdout: '', stderr: '' };
    });

    await configureTmuxClipboardForSessionAsync('omc-team');

    expect(mocks.rmuxExecAsync).toHaveBeenCalledWith(
      ['set-option', '-t', 'omc-team', 'set-clipboard', 'on'],
      undefined,
    );
    expect(mocks.rmuxExecAsync).toHaveBeenCalledWith(
      ['set-option', '-at', 'omc-team', 'terminal-features', ',*:clipboard'],
      undefined,
    );
  });
});
