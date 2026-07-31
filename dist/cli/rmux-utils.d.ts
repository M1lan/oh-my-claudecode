/**
 * Multiplexer utility functions for omc native shell launch.
 *
 * rmux is the primary multiplexer; tmux is the drop-in fallback. All raw
 * multiplexer invocations in the codebase route through the centralized
 * wrappers here (rmuxExec, rmuxExecAsync, rmuxShell, …), which resolve the
 * active multiplexer once. Adapted from oh-my-codex patterns for omc.
 */
import { type ExecFileSyncOptionsWithStringEncoding, type ExecSyncOptionsWithStringEncoding, type SpawnSyncOptionsWithStringEncoding, type SpawnSyncReturns } from 'child_process';
export interface RmuxExecOptions {
    /** Strip TMUX env var so the command targets the default tmux server.
     *  Default: false — preserves TMUX (targets the current server).
     *  Set to true for OMC-owned background sessions and cross-session scans. */
    stripTmux?: boolean;
}
export declare function rmuxEnv(): NodeJS.ProcessEnv;
/** How to drive an rmux server: its own binary plus explicit `-S <socket>`. */
export interface RmuxInvocation {
    bin: string;
    socketArgs: string[];
}
/**
 * Detect an rmux session and resolve how to drive its multiplexer server.
 *
 * rmux (a tmux-compatible multiplexer) exports TMUX_PROGRAM — the path to its
 * own binary under an `rmux-shim-*` dir — plus TMUX="<socket>,<pid>,<session>".
 * The plain `tmux` on PATH is a shim that, whenever $TMUX is set, defers to the
 * real tmux; real tmux then cannot talk to rmux's socket and dies with
 * "server exited unexpectedly" (which is what breaks `omc interop` inside rmux).
 * Driving TMUX_PROGRAM directly with an explicit `-S <socket>` bypasses the
 * shim and targets rmux's own server. rmux is POSIX-only, so this never applies
 * on native Windows.
 *
 * @returns the rmux binary + socket args when inside rmux, else null (plain tmux).
 */
export declare function resolveRmuxInvocation(env?: NodeJS.ProcessEnv): RmuxInvocation | null;
export declare function isNativeWindowsShell(): boolean;
/** Test-only: reset the memoized plain-rmux discovery result. */
export declare function __resetRmuxBinaryPathCache(): void;
export declare function rmuxExec(args: string[], opts?: RmuxExecOptions & Omit<ExecFileSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
    encoding?: BufferEncoding;
}): string;
export declare function rmuxExecAsync(args: string[], opts?: RmuxExecOptions & {
    timeout?: number;
}): Promise<{
    stdout: string;
    stderr: string;
}>;
export declare function rmuxShell(command: string, opts?: RmuxExecOptions & Omit<ExecSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
    encoding?: BufferEncoding;
}): string;
export declare function rmuxShellAsync(command: string, opts?: RmuxExecOptions & {
    timeout?: number;
}): Promise<{
    stdout: string;
    stderr: string;
}>;
export declare function rmuxSpawn(args: string[], opts?: RmuxExecOptions & Omit<SpawnSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
    encoding?: BufferEncoding;
}): SpawnSyncReturns<string>;
export declare function rmuxCmdAsync(args: string[], opts?: RmuxExecOptions & {
    timeout?: number;
}): Promise<{
    stdout: string;
    stderr: string;
}>;
export type ClaudeLaunchPolicy = 'inside-tmux' | 'outside-tmux' | 'direct';
export interface RmuxPaneSnapshot {
    paneId: string;
    currentCommand: string;
    startCommand: string;
}
/**
 * Check if tmux is available on the system
 */
export declare function isTmuxAvailable(): boolean;
/**
 * True when a tmux-compatible multiplexer can be driven on this host: a plain
 * `rmux` on PATH (preferred, POSIX-only) or tmux itself. rmux masquerades
 * through the tmux code path, so callers inside a cmux surface prefer this over
 * cmux's own dialect — cmux is the last resort, used only when neither rmux nor
 * tmux is usable. On native Windows rmux is absent, so this reduces to the
 * tmux/psmux probe.
 */
export declare function isTmuxCompatibleMultiplexerAvailable(): boolean;
/**
 * Check if claude CLI is available on the system
 */
export declare function isClaudeAvailable(): boolean;
/**
 * Options for `resolveLaunchPolicy`. `requireTmux=true` makes
 * CMUX_SURFACE_ID stop demoting to 'direct'. The caller is responsible for
 * gating on platform/flag combinations (e.g. macOS + --madmax).
 */
export interface ResolveLaunchPolicyOptions {
    requireTmux?: boolean;
}
/**
 * Resolve launch policy based on environment and args
 * - inside-tmux: Already in tmux session, split pane for HUD
 * - outside-tmux: Not in tmux, create new session
 * - direct: tmux not available, run directly
 * - direct: print mode requested so stdout can flow to parent process
 */
export declare function resolveLaunchPolicy(env?: NodeJS.ProcessEnv, args?: string[], options?: ResolveLaunchPolicyOptions): ClaudeLaunchPolicy;
/**
 * Build tmux session name from directory, git branch, and UTC timestamp
 * Format: omc-{dir}-{branch}-{utctimestamp}
 * e.g.  omc-myproject-dev-20260221143052
 */
export declare function buildRmuxSessionName(cwd: string): string;
/**
 * Sanitize string for use in tmux session/window names
 * Lowercase, alphanumeric + hyphens only
 */
export declare function sanitizeRmuxToken(value: string): string;
/**
 * Build shell command string for tmux with proper quoting
 */
export declare function buildRmuxShellCommand(command: string, args: string[]): string;
export declare function buildRmuxShellCommandWithEnv(command: string, args: string[], envVars: Record<string, string>): string;
/**
 * Wrap a command string in the user's login shell with RC file sourcing.
 * Ensures PATH and other environment setup from .bashrc/.zshrc is available
 * when tmux spawns new sessions or panes with a command argument.
 *
 * tmux new-session / split-window run commands via a non-login, non-interactive
 * shell, so tools installed via nvm, pyenv, conda, etc. are invisible.
 * This wrapper starts a login shell (`-lc`) and explicitly sources the RC file.
 */
export declare function wrapWithLoginShell(command: string): string;
/**
 * Quote shell argument for safe shell execution
 * Uses single quotes with proper escaping
 */
export declare function quoteShellArg(value: string): string;
/**
 * Parse tmux pane list output into structured data
 */
export declare function parseRmuxPaneSnapshot(output: string): RmuxPaneSnapshot[];
/**
 * Check if pane is running a HUD watch command
 */
export declare function isHudWatchPane(pane: RmuxPaneSnapshot): boolean;
/**
 * Find HUD watch pane IDs in current window
 */
export declare function findHudWatchPaneIds(panes: RmuxPaneSnapshot[], currentPaneId?: string): string[];
/**
 * List HUD watch panes in current tmux window
 */
export declare function listHudWatchPaneIdsInCurrentWindow(currentPaneId?: string): string[];
/**
 * Create HUD watch pane in current window
 * Returns pane ID or null on failure
 */
export declare function createHudWatchPane(cwd: string, hudCmd: string): string | null;
/**
 * Kill tmux pane by ID
 */
export declare function killRmuxPane(paneId: string): void;
//# sourceMappingURL=rmux-utils.d.ts.map