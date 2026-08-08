/**
 * Interop CLI Command - Split-pane tmux session with OMC and OMX
 *
 * Creates a tmux split-pane layout with Claude Code (OMC) on the left
 * and Codex CLI (OMX) on the right, with shared interop state.
 */

import { execFileSync, spawnSync } from 'child_process';
import { randomUUID } from 'crypto';
import {
  isClaudeAvailable,
  rmuxExec,
  buildRmuxShellCommandWithEnv,
  getMultiplexerServerIdentity,
  resolveRmuxInvocation,
  wrapWithBashLoginShell,
  killRmuxPane,
} from './rmux-utils.js';
import {
  initInteropSession,
  getInteropDir,
  readInteropConfig,
  updateInteropOmxRuntime,
  updateInteropStatus,
} from '../interop/shared-state.js';

export type InteropMode = 'off' | 'observe' | 'active';

/** Bypass flag passed to Claude Code (OMC) when --yolo is set. */
const CLAUDE_YOLO_FLAG = '--dangerously-skip-permissions';
/** Bypass flag passed to Codex (OMX) when --yolo is set. */
const CODEX_YOLO_FLAG = '--dangerously-bypass-approvals-and-sandbox';

/**
 * Env var exported into the Codex (OMX) pane at interop launch. oh-my-codex
 * reads it on startup and — via its readiness-aware pane injection — activates
 * the caveman skill at this level, deterministically (the primary path).
 * Name is a cross-repo contract: it must match the reader in oh-my-codex.
 */
export const INTEROP_CAVEMAN_LEVEL_ENV = 'OMX_INTEROP_CAVEMAN_LEVEL';
/**
 * Caveman level OMX speaks inside interop: classical Chinese, max compression.
 * Must be one of oh-my-codex's INTEROP_CAVEMAN_LEVELS (interop-caveman.ts); an
 * unknown value is warned + ignored on the codex side, disabling activation.
 */
export const INTEROP_CAVEMAN_LEVEL = 'wenyan-ultra';

export interface InteropRuntimeFlags {
  enabled: boolean;
  mode: InteropMode;
  omcInteropToolsEnabled: boolean;
}

export function readInteropRuntimeFlags(
  env: NodeJS.ProcessEnv = process.env,
): InteropRuntimeFlags {
  const rawMode = (env.OMX_OMC_INTEROP_MODE || 'off').toLowerCase();
  const mode: InteropMode =
    rawMode === 'observe' || rawMode === 'active' ? rawMode : 'off';
  return {
    enabled: env.OMX_OMC_INTEROP_ENABLED === '1',
    mode,
    omcInteropToolsEnabled: env.OMC_INTEROP_TOOLS_ENABLED === '1',
  };
}

export function validateInteropRuntimeFlags(flags: InteropRuntimeFlags): {
  ok: boolean;
  reason?: string;
} {
  if (!flags.enabled && flags.mode !== 'off') {
    return {
      ok: false,
      reason:
        'OMX_OMC_INTEROP_MODE must be "off" when OMX_OMC_INTEROP_ENABLED=0.',
    };
  }

  if (flags.mode === 'active' && !flags.omcInteropToolsEnabled) {
    return {
      ok: false,
      reason: 'Active mode requires OMC_INTEROP_TOOLS_ENABLED=1.',
    };
  }

  return { ok: true };
}

/**
 * Compute the effective interop env exported into both panes at launch.
 * Names are a cross-repo contract with oh-my-codex — do not rename.
 * Launching interop implies interop is on: a mode of 'off' is promoted to
 * 'observe' so the exported env is always a valid enabled configuration.
 */
export function buildInteropSessionEnv(
  mode: InteropMode,
  sessionId: string,
  cwd: string,
): Record<string, string> {
  return {
    OMX_OMC_INTEROP_ENABLED: '1',
    OMX_OMC_INTEROP_MODE: mode === 'off' ? 'observe' : mode,
    OMC_INTEROP_TOOLS_ENABLED: '1',
    OMX_OMC_INTEROP_SESSION_ID: sessionId,
    OMX_OMC_INTEROP_DIR: getInteropDir(cwd),
  };
}

export function isRmuxInteropEnvironment(
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  return resolveRmuxInvocation(env) !== null;
}

export function buildCodexLaunchCommand(
  mode: InteropMode,
  sessionId: string,
  cwd: string,
  yolo: boolean,
): string {
  return wrapWithBashLoginShell(
    buildRmuxShellCommandWithEnv('codex', yolo ? [CODEX_YOLO_FLAG] : [], {
      ...buildInteropSessionEnv(mode, sessionId, cwd),
      [INTEROP_CAVEMAN_LEVEL_ENV]: INTEROP_CAVEMAN_LEVEL,
    }),
  );
}

export function buildOmxPanePersistenceArgs(paneId: string): string[] {
  return ['set-option', '-p', '-t', paneId, 'remain-on-exit', 'on'];
}

export function buildOmxRespawnArgs(
  paneId: string,
  launchCommand: string,
): string[] {
  return ['respawn-pane', '-k', '-t', paneId, launchCommand];
}

export interface OmxPaneIdentity {
  paneId: string;
  sessionId: string;
  windowId: string;
}

export interface OmxRespawnOwnership extends OmxPaneIdentity {
  multiplexerServerId: string;
}

const OMX_PANE_IDENTITY_FORMAT = '#{pane_id}\t#{session_id}\t#{window_id}';

export function parseOmxPaneIdentity(output: string): OmxPaneIdentity {
  const [paneId = '', sessionId = '', windowId = ''] = output
    .trim()
    .split('\t');
  if (
    !paneId.startsWith('%') ||
    !sessionId.startsWith('$') ||
    !windowId.startsWith('@')
  ) {
    throw new Error('Invalid Codex pane identity returned by multiplexer');
  }
  return { paneId, sessionId, windowId };
}

export function validateOmxRespawnOwnership(
  expected: OmxRespawnOwnership,
  currentServerId: string,
  observed: OmxPaneIdentity,
): void {
  if (expected.multiplexerServerId !== currentServerId) {
    throw new Error('Codex pane server identity mismatch');
  }
  if (
    expected.paneId !== observed.paneId ||
    expected.sessionId !== observed.sessionId ||
    expected.windowId !== observed.windowId
  ) {
    throw new Error('Codex pane ownership mismatch');
  }
}

export function respawnOmxPane(cwd: string = process.cwd()): void {
  const config = readInteropConfig(cwd);
  if (
    !config?.multiplexerServerId ||
    !config.omxPaneId ||
    !config.omxSessionId ||
    !config.omxWindowId ||
    !config.omxLaunchCommand
  ) {
    console.error(
      'Error: No restartable Codex pane found in interop config.json.',
    );
    process.exit(1);
  }

  try {
    if (!isRmuxInteropEnvironment()) {
      throw new Error('Interop restart requires an active rmux session');
    }
    const currentServerId = getMultiplexerServerIdentity();
    if (!currentServerId) {
      throw new Error('No active tmux-compatible server identity');
    }
    if (config.multiplexerServerId !== currentServerId) {
      throw new Error('Codex pane server identity mismatch');
    }
    const observed = parseOmxPaneIdentity(
      rmuxExec([
        'display-message',
        '-p',
        '-t',
        config.omxPaneId,
        OMX_PANE_IDENTITY_FORMAT,
      ]),
    );
    validateOmxRespawnOwnership(
      {
        multiplexerServerId: config.multiplexerServerId,
        paneId: config.omxPaneId,
        sessionId: config.omxSessionId,
        windowId: config.omxWindowId,
      },
      currentServerId,
      observed,
    );
    rmuxExec(buildOmxRespawnArgs(config.omxPaneId, config.omxLaunchCommand), {
      stdio: 'ignore',
    });
    updateInteropOmxRuntime(cwd, { omxReadiness: 'pending' }, config.sessionId);
    updateInteropStatus(cwd, 'active', config.sessionId);
    console.log(
      'Codex pane respawned with stored launch command. Startup readiness pending; inspect Codex pane for MCP startup failures.',
    );
  } catch (error) {
    try {
      updateInteropOmxRuntime(
        cwd,
        { omxReadiness: 'failed' },
        config.sessionId,
      );
    } catch {
      // Preserve the original restart or persistence error below.
    }
    console.error(
      'Error respawning Codex pane:',
      error instanceof Error ? error.message : String(error),
    );
    process.exit(1);
  }
}

/**
 * Check if codex CLI is available
 */
function isCodexAvailable(): boolean {
  try {
    execFileSync('codex', ['--version'], {
      stdio: 'ignore',
      shell: process.platform === 'win32',
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Launch interop session with split tmux panes
 */
export function launchInteropSession(
  cwd: string = process.cwd(),
  options: { yolo?: boolean; force?: boolean } = {},
): void {
  const yolo = Boolean(options.yolo);
  const flags = readInteropRuntimeFlags();
  const flagCheck = validateInteropRuntimeFlags(flags);

  console.log(
    `[interop] mode=${flags.mode}, enabled=${flags.enabled ? '1' : '0'}, tools=${flags.omcInteropToolsEnabled ? '1' : '0'}, yolo=${yolo ? '1' : '0'}`,
  );
  if (yolo) {
    console.warn(
      '[interop] --yolo: launching Claude with --dangerously-skip-permissions and Codex with --dangerously-bypass-approvals-and-sandbox.',
    );
  }
  if (!flagCheck.ok) {
    console.error(`Error: ${flagCheck.reason}`);
    console.error('Refusing to start interop in invalid flag configuration.');
    process.exit(1);
  }

  // Check prerequisites
  if (!isRmuxInteropEnvironment()) {
    console.error('Error: Interop mode requires an active rmux session.');
    process.exit(1);
  }

  const hasCodex = isCodexAvailable();
  const hasClaude = isClaudeAvailable();

  if (!hasClaude) {
    console.error(
      'Error: claude CLI is not available. Install Claude Code CLI first.',
    );
    process.exit(1);
  }

  if (!hasCodex) {
    console.warn(
      'Warning: codex CLI is not available. Only Claude Code will be launched.',
    );
    console.warn(
      'Install the Codex CLI (`codex`) and oh-my-codex for full interop support.\n',
    );
  }

  // Generate session ID
  const sessionId = `interop-${randomUUID().split('-')[0]}`;
  const multiplexerServerId = getMultiplexerServerIdentity();
  if (!multiplexerServerId) {
    console.error('Error: Failed to identify active tmux-compatible server');
    process.exit(1);
  }

  // Effective interop env, exported into both panes so the OMC MCP server
  // and the OMX pane see the same session they were launched for.
  const effectiveEnv = buildInteropSessionEnv(flags.mode, sessionId, cwd);
  const codexCommand = hasCodex
    ? buildCodexLaunchCommand(flags.mode, sessionId, cwd, yolo)
    : undefined;

  // Initialize interop session (writes config.json as a side effect)
  try {
    initInteropSession(
      sessionId,
      cwd,
      hasCodex ? cwd : undefined,
      codexCommand
        ? {
            multiplexerServerId,
            omxLaunchCommand: codexCommand,
            omxReadiness: 'pending',
          }
        : undefined,
      { force: Boolean(options.force) },
    );
  } catch (error) {
    console.error(
      'Error:',
      error instanceof Error ? error.message : String(error),
    );
    console.error(
      'If no interop session is actually running there, re-run with --force to take over.',
    );
    process.exit(1);
  }

  console.log(`Initializing interop session: ${sessionId}`);
  console.log(`Working directory: ${cwd}`);
  console.log(`Config saved to: ${getInteropDir(cwd)}/config.json\n`);

  // Get current pane ID
  let currentPaneId: string;
  try {
    const output = rmuxExec(['display-message', '-p', '#{pane_id}']);
    currentPaneId = output.trim();
  } catch (_error) {
    updateInteropStatus(cwd, 'failed', sessionId);
    console.error('Error: Failed to get current tmux pane ID');
    process.exit(1);
  }

  if (!currentPaneId.startsWith('%')) {
    updateInteropStatus(cwd, 'failed', sessionId);
    console.error('Error: Invalid tmux pane ID format');
    process.exit(1);
  }

  // Track the codex pane so we can tear it down if launching claude fails —
  // otherwise a failed left-pane launch orphans the right-pane codex process.
  let codexPaneId: string | null = null;

  // Split pane horizontally (left: claude, right: codex)
  try {
    if (hasCodex) {
      // Create right pane with codex
      console.log('Splitting pane: Left (Claude Code) | Right (Codex)');

      // Codex runs through the PATH-resolved Bash login shell. Capture the new
      // pane id (-P -F) so failures can clean it up and restarts can reuse the
      // identical environment-wrapped command stored in config.json.
      const splitOutput = rmuxExec([
        'split-window',
        '-h',
        '-c',
        cwd,
        '-t',
        currentPaneId,
        '-P',
        '-F',
        OMX_PANE_IDENTITY_FORMAT,
        codexCommand!,
      ]);
      const paneIdentity = parseOmxPaneIdentity(
        splitOutput.split('\n')[0] ?? '',
      );
      codexPaneId = paneIdentity.paneId;
      rmuxExec(buildOmxPanePersistenceArgs(codexPaneId), { stdio: 'ignore' });
      updateInteropOmxRuntime(
        cwd,
        {
          omxPaneId: codexPaneId,
          omxSessionId: paneIdentity.sessionId,
          omxWindowId: paneIdentity.windowId,
          omxReadiness: 'pending',
        },
        sessionId,
      );

      // Caveman activation happens exclusively via the deterministic
      // INTEROP_CAVEMAN_LEVEL_ENV startup hook inside oh-my-codex (exported
      // above). No keystrokes are ever typed into the codex pane at launch:
      // live QA showed codex can still be sitting at interactive prompts
      // (trust/login/update) even under --yolo, so blind send-keys risks
      // answering an arbitrary prompt. Older codex builds without the hook
      // simply stay at their global caveman level.

      // Select left pane (original/current)
      rmuxExec(['select-pane', '-t', currentPaneId], { stdio: 'ignore' });

      console.log('\nInterop panes launched.');
      console.log('- Left pane: Claude Code (this terminal)');
      console.log(
        '- Right pane: Codex CLI startup pending; MCP startup failures appear there.',
      );
      console.log(
        '- Restart Codex with identical environment: omc interop --respawn-omx',
      );
      console.log(
        '\nYou can now use interop MCP tools to communicate between the two:',
      );
      console.log('- interop_send_task: Send tasks between tools');
      console.log('- interop_read_results: Check task results');
      console.log('- interop_send_message: Send messages');
      console.log('- interop_read_messages: Read messages');
    } else {
      // Codex not available, just inform user
      console.log('\nLaunching Claude Code in this pane.');
      console.log(
        'Install the Codex CLI (`codex`) and oh-my-codex for full interop support.',
      );
    }
  } catch (error) {
    if (codexPaneId) killRmuxPane(codexPaneId);
    updateInteropStatus(cwd, 'failed', sessionId);
    console.error(
      'Error creating split pane:',
      error instanceof Error ? error.message : String(error),
    );
    process.exit(1);
  }

  // Launch claude in the current (left) pane. spawnSync inherits stdio so
  // claude takes over this terminal until it exits, mirroring how codex
  // runs as the foreground process in the right pane.
  const claudeArgs = yolo ? [CLAUDE_YOLO_FLAG] : [];
  const result = spawnSync('claude', claudeArgs, {
    stdio: 'inherit',
    cwd,
    env: { ...process.env, ...effectiveEnv },
  });
  if (result.error) {
    // Claude never started — tear down the codex pane we just created so it
    // isn't left running headless without its OMC counterpart.
    if (codexPaneId) killRmuxPane(codexPaneId);
    updateInteropStatus(cwd, 'failed', sessionId);
    console.error(
      'Error launching claude:',
      result.error instanceof Error
        ? result.error.message
        : String(result.error),
    );
    process.exit(1);
  }
  updateInteropStatus(cwd, 'completed', sessionId);
  process.exit(result.status ?? 0);
}

/**
 * CLI entry point for interop command
 */
export function interopCommand(
  options: {
    cwd?: string;
    yolo?: boolean;
    respawnOmx?: boolean;
    force?: boolean;
  } = {},
): void {
  const cwd = options.cwd || process.cwd();
  if (options.respawnOmx) {
    respawnOmxPane(cwd);
    return;
  }
  launchInteropSession(cwd, { yolo: options.yolo, force: options.force });
}
