import { describe, expect, it } from 'vitest';
import {
  buildCodexLaunchCommand,
  buildInteropSessionEnv,
  buildOmxPanePersistenceArgs,
  buildOmxRespawnArgs,
  parseOmxPaneIdentity,
  readInteropRuntimeFlags,
  isRmuxInteropEnvironment,
  validateOmxRespawnOwnership,
  validateInteropRuntimeFlags,
  INTEROP_CAVEMAN_LEVEL_ENV,
  INTEROP_CAVEMAN_LEVEL,
} from '../cli/interop.js';
import {
  getMultiplexerServerIdentity,
  wrapWithBashLoginShell,
} from '../cli/rmux-utils.js';
import { getInteropDir } from '../interop/shared-state.js';

describe('cli interop flag validation', () => {
  it('reads defaults', () => {
    const flags = readInteropRuntimeFlags({} as NodeJS.ProcessEnv);
    expect(flags.enabled).toBe(false);
    expect(flags.mode).toBe('off');
    expect(flags.omcInteropToolsEnabled).toBe(false);
  });

  it('rejects non-off mode when interop is disabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '0',
      OMX_OMC_INTEROP_MODE: 'observe',
      OMC_INTEROP_TOOLS_ENABLED: '0',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toContain('must be "off"');
  });

  it('rejects active mode without interop tools enabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '1',
      OMX_OMC_INTEROP_MODE: 'active',
      OMC_INTEROP_TOOLS_ENABLED: '0',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(false);
    expect(verdict.reason).toContain('OMC_INTEROP_TOOLS_ENABLED=1');
  });

  it('accepts active mode when required flags are enabled', () => {
    const flags = readInteropRuntimeFlags({
      OMX_OMC_INTEROP_ENABLED: '1',
      OMX_OMC_INTEROP_MODE: 'active',
      OMC_INTEROP_TOOLS_ENABLED: '1',
    } as NodeJS.ProcessEnv);

    const verdict = validateInteropRuntimeFlags(flags);
    expect(verdict.ok).toBe(true);
  });
});

// Cross-repo contract: env var names read by oh-my-codex and OMC's own MCP
// server. Lock the shape so a rename on either side is caught here.
describe('buildInteropSessionEnv', () => {
  const sessionId = 'interop-abc123';
  const cwd = '/some/project';

  it('promotes mode off to observe', () => {
    const env = buildInteropSessionEnv('off', sessionId, cwd);
    expect(env.OMX_OMC_INTEROP_MODE).toBe('observe');
  });

  it('preserves observe and active modes', () => {
    expect(
      buildInteropSessionEnv('observe', sessionId, cwd).OMX_OMC_INTEROP_MODE,
    ).toBe('observe');
    expect(
      buildInteropSessionEnv('active', sessionId, cwd).OMX_OMC_INTEROP_MODE,
    ).toBe('active');
  });

  it('exports the full interop env contract', () => {
    const env = buildInteropSessionEnv('observe', sessionId, cwd);
    expect(env).toEqual({
      OMX_OMC_INTEROP_ENABLED: '1',
      OMX_OMC_INTEROP_MODE: 'observe',
      OMC_INTEROP_TOOLS_ENABLED: '1',
      OMX_OMC_INTEROP_SESSION_ID: sessionId,
      OMX_OMC_INTEROP_DIR: getInteropDir(cwd),
    });
  });
});

// Cross-repo contract: oh-my-codex reads OMX_INTEROP_CAVEMAN_LEVEL on startup
// and activates its caveman skill at that level (the sole activation path —
// OMC never types keystrokes into the codex pane). Lock both names so a rename
// on one side is caught here rather than silently disabling activation.
describe('interop caveman activation contract', () => {
  it('exports the env var name oh-my-codex reads', () => {
    expect(INTEROP_CAVEMAN_LEVEL_ENV).toBe('OMX_INTEROP_CAVEMAN_LEVEL');
  });

  it('uses wenyan-ultra as the interop level', () => {
    expect(INTEROP_CAVEMAN_LEVEL).toBe('wenyan-ultra');
  });
});

describe('Codex interop launch command', () => {
  it('accepts rmux sessions and rejects plain tmux sessions', () => {
    expect(
      isRmuxInteropEnvironment({
        TERM_PROGRAM: 'rmux',
        TMUX_PROGRAM: '/path/rmux-shim-1/tmux',
        TMUX: '/socket/rmux,123,0',
      } as NodeJS.ProcessEnv),
    ).toBe(true);
    expect(
      isRmuxInteropEnvironment({
        TMUX_PROGRAM: '/opt/homebrew/bin/tmux',
        TMUX: '/socket/tmux,456,0',
      } as NodeJS.ProcessEnv),
    ).toBe(false);
  });

  it('uses PATH-resolved Bash login shell without manually sourcing an RC file', () => {
    expect(wrapWithBashLoginShell('codex --version')).toBe(
      "exec 'bash' -lc 'codex --version'",
    );
  });

  it('builds a YOLO launch with the complete interop environment', () => {
    const command = buildCodexLaunchCommand(
      'active',
      'interop-abc123',
      '/some/project',
      true,
    );

    expect(command).toContain("exec 'bash' -lc");
    expect(command).toContain("'OMX_OMC_INTEROP_ENABLED=1'");
    expect(command).toContain("'OMX_INTEROP_CAVEMAN_LEVEL=wenyan-ultra'");
    expect(command).toContain("'--dangerously-bypass-approvals-and-sandbox'");
    expect(command).not.toContain('.bashrc');
    expect(command).not.toContain('zsh');
  });

  it('keeps dead Codex panes available without injecting startup keystrokes', () => {
    const args = buildOmxPanePersistenceArgs('%9');

    expect(args).toEqual([
      'set-option',
      '-p',
      '-t',
      '%9',
      'remain-on-exit',
      'on',
    ]);
    expect(args).not.toContain('send-keys');
  });

  it('respawns the stored pane with the stored launch command', () => {
    expect(buildOmxRespawnArgs('%9', "exec 'bash' -lc 'codex'")).toEqual([
      'respawn-pane',
      '-k',
      '-t',
      '%9',
      "exec 'bash' -lc 'codex'",
    ]);
  });

  it('derives server identity from the active multiplexer socket', () => {
    expect(
      getMultiplexerServerIdentity({
        TMUX: '/socket/server-a,123,0',
        TMUX_PROGRAM: '/path/to/rmux-shim',
      } as NodeJS.ProcessEnv),
    ).toBe('/socket/server-a,123');
  });

  it('rejects a reused pane ID from another multiplexer server', () => {
    const observed = parseOmxPaneIdentity('%9\t$2\t@4');

    expect(() =>
      validateOmxRespawnOwnership(
        {
          multiplexerServerId: '/socket/server-a',
          paneId: '%9',
          sessionId: '$2',
          windowId: '@4',
        },
        '/socket/server-b',
        observed,
      ),
    ).toThrow(/server identity mismatch/);
  });

  it('rejects a reused pane ID with different session ownership', () => {
    expect(() =>
      validateOmxRespawnOwnership(
        {
          multiplexerServerId: '/socket/server-a',
          paneId: '%9',
          sessionId: '$2',
          windowId: '@4',
        },
        '/socket/server-a',
        parseOmxPaneIdentity('%9\t$7\t@4'),
      ),
    ).toThrow(/pane ownership mismatch/);
  });

  it('rejects reused ownership after a same-socket server restart', () => {
    expect(() =>
      validateOmxRespawnOwnership(
        {
          multiplexerServerId: '/socket/server-a,123',
          paneId: '%9',
          sessionId: '$2',
          windowId: '@4',
        },
        '/socket/server-a,456',
        parseOmxPaneIdentity('%9\t$2\t@4'),
      ),
    ).toThrow(/server identity mismatch/);
  });
});
