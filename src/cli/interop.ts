/**
 * Interop CLI Command - Split-pane tmux session with OMC and OMX
 *
 * Creates a tmux split-pane layout with Claude Code (OMC) on the left
 * and Codex CLI (OMX) on the right, with shared interop state.
 */

import { execFileSync, spawnSync } from 'child_process';
import { randomUUID } from 'crypto';
import {
  isTmuxAvailable,
  isClaudeAvailable,
  rmuxExec,
  buildRmuxShellCommandWithEnv,
  wrapWithLoginShell,
  killRmuxPane,
} from './rmux-utils.js';
import {
  initInteropSession,
  getInteropDir,
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
/**
 * Natural-language activation the Codex caveman skill recognizes ("use caveman"
 * + level). Typed into the pane as a fallback for Codex builds that predate the
 * INTEROP_CAVEMAN_LEVEL_ENV startup hook. Idempotent: re-activating the same
 * level is a no-op, so it is safe even when the env path already fired.
 */
export const INTEROP_CAVEMAN_ACTIVATION = `use caveman ${INTEROP_CAVEMAN_LEVEL} mode`;

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
 * Type the caveman activation into the Codex (OMX) pane. Sent as a literal
 * string (`-l`) followed by Enter so shell/tmux never reinterpret its spaces —
 * mirrors the autoresearch setup injection. Failures are swallowed: the OMX
 * pane simply stays at its global caveman level.
 */
export function sendInteropCavemanActivation(
  paneId: string,
  activation: string = INTEROP_CAVEMAN_ACTIVATION,
): void {
  try {
    rmuxExec(['send-keys', '-t', paneId, '-l', activation], {
      stdio: 'ignore',
    });
    rmuxExec(['send-keys', '-t', paneId, 'Enter'], { stdio: 'ignore' });
  } catch {
    // Non-fatal — the deterministic env-hook path in oh-my-codex is primary.
  }
}

/**
 * Launch interop session with split tmux panes
 */
export function launchInteropSession(
  cwd: string = process.cwd(),
  options: { yolo?: boolean } = {},
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
  if (!isTmuxAvailable()) {
    console.error(
      'Error: tmux is not available. Install tmux to use interop mode.',
    );
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
      'Install oh-my-codex (pnpm add -g @openai/codex) for full interop support.\n',
    );
  }

  // Check if already in tmux
  const inTmux = Boolean(process.env.TMUX);

  if (!inTmux) {
    console.error(
      'Error: Interop mode requires running inside a tmux session.',
    );
    console.error('Start tmux first: tmux new-session -s myproject');
    process.exit(1);
  }

  // Generate session ID
  const sessionId = `interop-${randomUUID().split('-')[0]}`;

  // Initialize interop session (writes config.json as a side effect)
  initInteropSession(sessionId, cwd, hasCodex ? cwd : undefined);

  console.log(`Initializing interop session: ${sessionId}`);
  console.log(`Working directory: ${cwd}`);
  console.log(`Config saved to: ${getInteropDir(cwd)}/config.json\n`);

  // Effective interop env, exported into both panes so the OMC MCP server
  // and the OMX pane actually see the interop session they were launched for.
  const effectiveEnv = buildInteropSessionEnv(flags.mode, sessionId, cwd);

  // Get current pane ID
  let currentPaneId: string;
  try {
    const output = rmuxExec(['display-message', '-p', '#{pane_id}']);
    currentPaneId = output.trim();
  } catch (_error) {
    updateInteropStatus(cwd, 'failed');
    console.error('Error: Failed to get current tmux pane ID');
    process.exit(1);
  }

  if (!currentPaneId.startsWith('%')) {
    updateInteropStatus(cwd, 'failed');
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

      // Wrap in a login shell so the codex pane inherits the same PATH setup
      // (fnm/pnpm/etc.) that the parent shell — and the left-pane claude
      // (spawnSync inherits this process's env) — already see. Capture the new
      // pane id (-P -F) so failures can clean it up.
      const codexCommand = wrapWithLoginShell(
        buildRmuxShellCommandWithEnv('codex', yolo ? [CODEX_YOLO_FLAG] : [], {
          ...effectiveEnv,
          [INTEROP_CAVEMAN_LEVEL_ENV]: INTEROP_CAVEMAN_LEVEL,
        }),
      );
      const splitOutput = rmuxExec([
        'split-window',
        '-h',
        '-c',
        cwd,
        '-t',
        currentPaneId,
        '-P',
        '-F',
        '#{pane_id}',
        codexCommand,
      ]);
      const newPaneId = splitOutput.split('\n')[0]?.trim() ?? '';
      codexPaneId = newPaneId.startsWith('%') ? newPaneId : null;

      // Fallback caveman activation for the OMX pane. The deterministic path is
      // the INTEROP_CAVEMAN_LEVEL_ENV startup hook in oh-my-codex; this typed
      // command covers older codex builds without that hook. Gated to --yolo:
      // only then does codex bypass its "Trust this directory?" prompt, so the
      // literal keystrokes can never race that prompt and answer it by accident.
      // In non-yolo runs the readiness-aware codex hook is the sole activation.
      if (yolo && codexPaneId) sendInteropCavemanActivation(codexPaneId);

      // Select left pane (original/current)
      rmuxExec(['select-pane', '-t', currentPaneId], { stdio: 'ignore' });

      console.log('\nInterop session ready!');
      console.log('- Left pane: Claude Code (this terminal)');
      console.log('- Right pane: Codex CLI');
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
      console.log('Install oh-my-codex to enable split-pane interop mode.');
      console.log('\nInstall: pnpm add -g @openai/codex');
    }
  } catch (error) {
    if (codexPaneId) killRmuxPane(codexPaneId);
    updateInteropStatus(cwd, 'failed');
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
    updateInteropStatus(cwd, 'failed');
    console.error(
      'Error launching claude:',
      result.error instanceof Error
        ? result.error.message
        : String(result.error),
    );
    process.exit(1);
  }
  updateInteropStatus(cwd, 'completed');
  process.exit(result.status ?? 0);
}

/**
 * CLI entry point for interop command
 */
export function interopCommand(
  options: { cwd?: string; yolo?: boolean } = {},
): void {
  const cwd = options.cwd || process.cwd();
  launchInteropSession(cwd, { yolo: options.yolo });
}
