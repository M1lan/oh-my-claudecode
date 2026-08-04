/**
 * Multiplexer utility functions for omc native shell launch.
 *
 * rmux is the primary multiplexer; tmux is the drop-in fallback. All raw
 * multiplexer invocations in the codebase route through the centralized
 * wrappers here (rmuxExec, rmuxExecAsync, rmuxShell, …), which resolve the
 * active multiplexer once. Adapted from oh-my-codex patterns for omc.
 */

import {
  exec,
  execFile,
  execFileSync,
  execSync,
  spawnSync,
  type ExecFileSyncOptionsWithStringEncoding,
  type ExecSyncOptionsWithStringEncoding,
  type SpawnSyncOptionsWithStringEncoding,
  type SpawnSyncReturns,
} from 'child_process';
import { basename, isAbsolute, win32 as win32Path } from 'path';
import { promisify } from 'util';

// ── multiplexer environment & execution wrappers ─────────────────────────────

export interface RmuxExecOptions {
  /** Strip TMUX env var so the command targets the default tmux server.
   *  Default: false — preserves TMUX (targets the current server).
   *  Set to true for OMC-owned background sessions and cross-session scans. */
  stripTmux?: boolean;
}

export function rmuxEnv(): NodeJS.ProcessEnv {
  // Strip both TMUX (real tmux) and PSMUX_SESSION (psmux's drop-in tmux on
  // native Windows). psmux gates `new-session -d` nesting on PSMUX_SESSION,
  // not TMUX, so dropping only TMUX leaves psmux silently no-op'ing detached
  // session creation. See issue #3265.
  const { TMUX: _, PSMUX_SESSION: __, ...env } = process.env;
  return env;
}

function resolveEnv(opts?: RmuxExecOptions): NodeJS.ProcessEnv {
  return opts?.stripTmux ? rmuxEnv() : process.env;
}

interface RmuxCommandInvocation {
  command: string;
  args: string[];
}

/** How to drive an rmux server: its own binary plus explicit `-S <socket>`. */
export interface RmuxInvocation {
  bin: string;
  socketArgs: string[];
}

/** Stable identity of the active tmux-compatible server for this process. */
export function getMultiplexerServerIdentity(
  env: NodeJS.ProcessEnv = process.env,
): string | null {
  const tmux = env.TMUX;
  if (!tmux) return null;
  const [socket, serverPid] = tmux.split(',');
  if (!socket || !serverPid) return null;
  return `${socket},${serverPid}`;
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
export function resolveRmuxInvocation(
  env: NodeJS.ProcessEnv = process.env,
): RmuxInvocation | null {
  if (process.platform === 'win32') return null;
  const program = env.TMUX_PROGRAM;
  const tmux = env.TMUX;
  const looksLikeRmux =
    env.TERM_PROGRAM === 'rmux' ||
    (typeof program === 'string' && program.includes('rmux-shim'));
  if (!looksLikeRmux || !program || !tmux) return null;
  const socket = tmux.split(',')[0];
  if (!socket) return null;
  return { bin: program, socketArgs: ['-S', socket] };
}

/**
 * Shell-command prefix for the active multiplexer (rmux `bin -S sock`, or plain
 * `tmux`). Used by the string-based shell wrappers below.
 */
function multiplexerShellCommandPrefix(): string {
  const rmux = resolveRmuxInvocation();
  if (rmux) {
    return [rmux.bin, ...rmux.socketArgs].map(quoteShellArg).join(' ');
  }
  // Prefer a plain `rmux` binary on PATH (POSIX only) as a tmux drop-in,
  // before falling back to literal tmux — mirrors resolveMultiplexerInvocation's
  // 3-tier ladder (shim -> plain rmux on PATH -> tmux).
  const rmuxBinary = resolveRmuxBinaryPath();
  if (rmuxBinary) {
    return quoteShellArg(rmuxBinary);
  }
  return 'tmux';
}

function isUnixLikeOnWindows(): boolean {
  return (
    process.platform === 'win32' &&
    !!(process.env.MSYSTEM || process.env.MINGW_PREFIX)
  );
}

export function isNativeWindowsShell(): boolean {
  return process.platform === 'win32' && !isUnixLikeOnWindows();
}

function quoteForCmd(arg: string): string {
  if (arg.length === 0) return '""';
  if (!/[\s"%^&|<>()]/.test(arg)) return arg;
  return `"${arg.replace(/(["%])/g, '$1$1')}"`;
}

function escapeForCmdSet(value: string): string {
  return value.replace(/"/g, '""');
}

/**
 * Cached result of the plain-`rmux`-on-PATH probe (`undefined` = not yet
 * probed, `string` = binary name, `null` = absent). rmux presence on PATH is
 * fixed for a process lifetime, so we memoize to avoid re-spawning `rmux -V`
 * on every multiplexer call — the readiness loops poll every ~50ms.
 */
let cachedRmuxBinaryPath: string | null | undefined;

/**
 * Discover a plain `rmux` binary on PATH (POSIX only).
 *
 * rmux is a tmux-compatible multiplexer; when a plain `rmux` is installed we
 * prefer it as the multiplexer OMC drives, even outside an rmux-launched shell
 * (that shim case is handled first by resolveRmuxInvocation). Mirrors
 * resolveTmuxBinaryPath's discovery approach — probe with the `-V` version flag
 * (`rmux -V` works; `rmux --version` only prints usage). Never applies on
 * native Windows (rmux is POSIX-only; the psmux path stays untouched).
 *
 * @returns 'rmux' when a plain rmux binary is available, else null (plain tmux).
 */
function resolveRmuxBinaryPath(): string | null {
  if (process.platform === 'win32') return null;
  if (cachedRmuxBinaryPath !== undefined) return cachedRmuxBinaryPath;
  let resolved: string | null = null;
  try {
    const result = spawnSync('rmux', ['-V'], {
      timeout: 5000,
      stdio: 'ignore',
    });
    if (result?.status === 0) resolved = 'rmux';
  } catch {
    // rmux not found or not executable; fall back to tmux resolution.
  }
  cachedRmuxBinaryPath = resolved;
  return resolved;
}

/** Test-only: reset the memoized plain-rmux discovery result. */
export function __resetRmuxBinaryPathCache(): void {
  cachedRmuxBinaryPath = undefined;
}

function resolveMultiplexerInvocation(args: string[]): RmuxCommandInvocation {
  const rmux = resolveRmuxInvocation();
  if (rmux) {
    return { command: rmux.bin, args: [...rmux.socketArgs, ...args] };
  }
  // Prefer a plain `rmux` binary on PATH (POSIX only) as a tmux drop-in,
  // before falling back to literal tmux resolution.
  const rmuxBinary = resolveRmuxBinaryPath();
  if (rmuxBinary) {
    return { command: rmuxBinary, args };
  }
  const resolvedBinary = resolveTmuxBinaryPath();
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(resolvedBinary)) {
    const comspec = process.env.COMSPEC || 'cmd.exe';
    const commandLine = [
      quoteForCmd(resolvedBinary),
      ...args.map(quoteForCmd),
    ].join(' ');
    return {
      command: comspec,
      args: ['/d', '/s', '/c', commandLine],
    };
  }

  return {
    command: resolvedBinary,
    args,
  };
}

export function rmuxExec(
  args: string[],
  opts?: RmuxExecOptions &
    Omit<ExecFileSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
      encoding?: BufferEncoding;
    },
): string {
  const { stripTmux: _, ...execOpts } = opts ?? {};
  const invocation = resolveMultiplexerInvocation(args);
  return execFileSync(invocation.command, invocation.args, {
    encoding: 'utf-8',
    ...execOpts,
    env: resolveEnv(opts),
  });
}

export async function rmuxExecAsync(
  args: string[],
  opts?: RmuxExecOptions & { timeout?: number },
): Promise<{ stdout: string; stderr: string }> {
  const { stripTmux: _, timeout, ...rest } = opts ?? {};
  const invocation = resolveMultiplexerInvocation(args);
  return promisify(execFile)(invocation.command, invocation.args, {
    encoding: 'utf-8',
    env: resolveEnv(opts),
    ...(timeout !== undefined ? { timeout } : {}),
    ...rest,
  });
}

export function rmuxShell(
  command: string,
  opts?: RmuxExecOptions &
    Omit<ExecSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
      encoding?: BufferEncoding;
    },
): string {
  const { stripTmux: _, ...execOpts } = opts ?? {};
  return execSync(`${multiplexerShellCommandPrefix()} ${command}`, {
    encoding: 'utf-8',
    ...execOpts,
    env: resolveEnv(opts),
  }) as string;
}

export async function rmuxShellAsync(
  command: string,
  opts?: RmuxExecOptions & { timeout?: number },
): Promise<{ stdout: string; stderr: string }> {
  const { stripTmux: _, timeout, ...rest } = opts ?? {};
  return promisify(exec)(`${multiplexerShellCommandPrefix()} ${command}`, {
    encoding: 'utf-8',
    env: resolveEnv(opts),
    ...(timeout !== undefined ? { timeout } : {}),
    ...rest,
  });
}

export function rmuxSpawn(
  args: string[],
  opts?: RmuxExecOptions &
    Omit<SpawnSyncOptionsWithStringEncoding, 'env' | 'encoding'> & {
      encoding?: BufferEncoding;
    },
): SpawnSyncReturns<string> {
  const { stripTmux: _, ...spawnOpts } = opts ?? {};
  const invocation = resolveMultiplexerInvocation(args);
  return spawnSync(invocation.command, invocation.args, {
    encoding: 'utf-8',
    ...spawnOpts,
    env: resolveEnv(opts),
  });
}

export async function rmuxCmdAsync(
  args: string[],
  opts?: RmuxExecOptions & { timeout?: number },
): Promise<{ stdout: string; stderr: string }> {
  if (args.some((a) => a.includes('#{')) && !isNativeWindowsShell()) {
    const escaped = args
      .map((a) => "'" + a.replace(/'/g, "'\\''") + "'")
      .join(' ');
    return rmuxShellAsync(escaped, opts);
  }
  return rmuxExecAsync(args, opts);
}

export type ClaudeLaunchPolicy = 'inside-tmux' | 'outside-tmux' | 'direct';

export interface RmuxPaneSnapshot {
  paneId: string;
  currentCommand: string;
  startCommand: string;
}

function resolveTmuxBinaryPath(): string {
  if (process.platform !== 'win32') {
    return 'tmux';
  }

  try {
    const result = spawnSync('where', ['tmux'], {
      timeout: 5000,
      encoding: 'utf8',
    });
    if (result.status !== 0) return 'tmux';

    const candidates =
      result.stdout
        ?.split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean) ?? [];
    const first = candidates[0];
    if (first && (isAbsolute(first) || win32Path.isAbsolute(first))) {
      return first;
    }
  } catch {
    // Fall back to plain tmux lookup below.
  }

  return 'tmux';
}

/**
 * Check if tmux is available on the system
 */
export function isTmuxAvailable(): boolean {
  try {
    const resolvedBinary = resolveTmuxBinaryPath();
    if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(resolvedBinary)) {
      const comspec = process.env.COMSPEC || 'cmd.exe';
      const result = spawnSync(
        comspec,
        ['/d', '/s', '/c', `"${resolvedBinary}" -V`],
        { timeout: 5000 },
      );
      return result.status === 0;
    }

    if (process.platform === 'win32') {
      const result = spawnSync(resolvedBinary, ['-V'], {
        timeout: 5000,
        shell: true,
      });
      return result.status === 0;
    }

    rmuxExec(['-V'], { stripTmux: true, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

/**
 * True when a tmux-compatible multiplexer can be driven on this host: a plain
 * `rmux` on PATH (preferred, POSIX-only) or tmux itself. rmux masquerades
 * through the tmux code path, so callers inside a cmux surface prefer this over
 * cmux's own dialect — cmux is the last resort, used only when neither rmux nor
 * tmux is usable. On native Windows rmux is absent, so this reduces to the
 * tmux/psmux probe.
 */
export function isTmuxCompatibleMultiplexerAvailable(): boolean {
  return resolveRmuxBinaryPath() !== null || isTmuxAvailable();
}

/**
 * Check if claude CLI is available on the system
 */
export function isClaudeAvailable(): boolean {
  try {
    execFileSync('claude', ['--version'], {
      stdio: 'ignore',
      shell: process.platform === 'win32',
    });
    return true;
  } catch {
    return false;
  }
}

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
export function resolveLaunchPolicy(
  env: NodeJS.ProcessEnv = process.env,
  args: string[] = [],
  options: ResolveLaunchPolicyOptions = {},
): ClaudeLaunchPolicy {
  if (args.some((arg) => arg === '--print' || arg === '-p')) {
    return 'direct';
  }
  let explicitPolicy: ClaudeLaunchPolicy | undefined;
  for (const arg of args) {
    if (arg === '--') break;
    if (arg === '--direct') explicitPolicy = 'direct';
    if (arg === '--rmux') explicitPolicy = 'outside-tmux';
  }
  if (explicitPolicy === 'direct') return 'direct';
  if (env.TMUX) return 'inside-tmux';
  if (explicitPolicy !== 'outside-tmux' && !options.requireTmux) return 'direct';
  // Terminal emulators that embed their own multiplexer (e.g. cmux, a
  // Ghostty-based terminal) set CMUX_SURFACE_ID but not TMUX. Prefer a
  // tmux-compatible multiplexer (rmux, or tmux itself) when one is usable —
  // rmux drives these surfaces cleanly through the tmux code path. Demote to
  // direct only when neither rmux nor tmux is available (cmux's own dialect is
  // the last resort, handled by the team runtime rather than this launch path).
  const multiplexerAvailable = isTmuxCompatibleMultiplexerAvailable();
  if (env.CMUX_SURFACE_ID && !options.requireTmux && !multiplexerAvailable) {
    return 'direct';
  }
  if (!multiplexerAvailable) {
    return 'direct';
  }
  return 'outside-tmux';
}

/**
 * Build tmux session name from directory, git branch, and UTC timestamp
 * Format: omc-{dir}-{branch}-{utctimestamp}
 * e.g.  omc-myproject-dev-20260221143052
 */
export function buildRmuxSessionName(cwd: string): string {
  const dirToken = sanitizeRmuxToken(basename(cwd));
  let branchToken = 'detached';

  try {
    const branch = execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], {
      cwd,
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'ignore'],
      windowsHide: true,
    }).trim();
    if (branch) {
      branchToken = sanitizeRmuxToken(branch);
    }
  } catch {
    // Non-git directory or git unavailable
  }

  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const utcTimestamp =
    `${now.getUTCFullYear()}` +
    `${pad(now.getUTCMonth() + 1)}` +
    `${pad(now.getUTCDate())}` +
    `${pad(now.getUTCHours())}` +
    `${pad(now.getUTCMinutes())}` +
    `${pad(now.getUTCSeconds())}`;

  const name = `omc-${dirToken}-${branchToken}-${utcTimestamp}`;
  return name.length > 120 ? name.slice(0, 120) : name;
}

/**
 * Sanitize string for use in tmux session/window names
 * Lowercase, alphanumeric + hyphens only
 */
export function sanitizeRmuxToken(value: string): string {
  const cleaned = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return cleaned || 'unknown';
}

/**
 * Build shell command string for tmux with proper quoting
 */
export function buildRmuxShellCommand(command: string, args: string[]): string {
  if (isNativeWindowsShell()) {
    return [command, ...args].map(quoteForCmd).join(' ');
  }
  return [quoteShellArg(command), ...args.map(quoteShellArg)].join(' ');
}

export function buildRmuxShellCommandWithEnv(
  command: string,
  args: string[],
  envVars: Record<string, string>,
): string {
  const envEntries = Object.entries(envVars);
  if (envEntries.length === 0) {
    return buildRmuxShellCommand(command, args);
  }

  if (isNativeWindowsShell()) {
    const envPrefix = envEntries
      .map(([key, value]) => `set "${key}=${escapeForCmdSet(value)}"`)
      .join(' && ');
    return `${envPrefix} && ${buildRmuxShellCommand(command, args)}`;
  }

  return buildRmuxShellCommand('env', [
    ...envEntries.map(([key, value]) => `${key}=${value}`),
    command,
    ...args,
  ]);
}

/**
 * Wrap a command string in the user's login shell with RC file sourcing.
 * Ensures PATH and other environment setup from .bashrc/.zshrc is available
 * when tmux spawns new sessions or panes with a command argument.
 *
 * tmux new-session / split-window run commands via a non-login, non-interactive
 * shell, so tools installed via nvm, pyenv, conda, etc. are invisible.
 * This wrapper starts a login shell (`-lc`) and explicitly sources the RC file.
 */
export function wrapWithLoginShell(command: string): string {
  if (isNativeWindowsShell()) {
    const comspec = process.env.COMSPEC || 'cmd.exe';
    return `${quoteForCmd(comspec)} /d /s /c ${quoteForCmd(command)}`;
  }

  const shell = process.env.SHELL || '/bin/sh';
  const shellName = basename(shell).replace(/\.(exe|cmd|bat)$/i, '');
  const rcFile = process.env.HOME ? `${process.env.HOME}/.${shellName}rc` : '';
  const sourcePrefix = rcFile
    ? `[ -f ${quoteShellArg(rcFile)} ] && . ${quoteShellArg(rcFile)}; `
    : '';
  return `exec ${quoteShellArg(shell)} -lc ${quoteShellArg(`${sourcePrefix}${command}`)}`;
}

/**
 * Run an agent command through the PATH-resolved Bash login shell.
 *
 * Agent panes use Bash regardless of the operator's interactive shell. Bash
 * owns its login startup sequence, so this wrapper deliberately does not
 * source an RC file before invoking `-lc`.
 */
export function wrapWithBashLoginShell(command: string): string {
  if (isNativeWindowsShell()) {
    const comspec = process.env.COMSPEC || 'cmd.exe';
    return `${quoteForCmd(comspec)} /d /s /c ${quoteForCmd(command)}`;
  }

  return `exec ${quoteShellArg('bash')} -lc ${quoteShellArg(command)}`;
}

/**
 * Quote shell argument for safe shell execution
 * Uses single quotes with proper escaping
 */
export function quoteShellArg(value: string): string {
  return `'${value.replace(/'/g, `'\"'\"'`)}'`;
}

/**
 * Parse tmux pane list output into structured data
 */
export function parseRmuxPaneSnapshot(output: string): RmuxPaneSnapshot[] {
  return output
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [paneId = '', currentCommand = '', ...startCommandParts] =
        line.split('\t');
      return {
        paneId: paneId.trim(),
        currentCommand: currentCommand.trim(),
        startCommand: startCommandParts.join('\t').trim(),
      };
    })
    .filter((pane) => pane.paneId.startsWith('%'));
}

/**
 * Check if pane is running a HUD watch command
 */
export function isHudWatchPane(pane: RmuxPaneSnapshot): boolean {
  const command = `${pane.startCommand} ${pane.currentCommand}`.toLowerCase();
  return (
    /\bhud\b/.test(command) &&
    /--watch\b/.test(command) &&
    (/\bomc(?:\.js)?\b/.test(command) || /\bnode\b/.test(command))
  );
}

/**
 * Find HUD watch pane IDs in current window
 */
export function findHudWatchPaneIds(
  panes: RmuxPaneSnapshot[],
  currentPaneId?: string,
): string[] {
  return panes
    .filter((pane) => pane.paneId !== currentPaneId)
    .filter((pane) => isHudWatchPane(pane))
    .map((pane) => pane.paneId);
}

/**
 * List HUD watch panes in current tmux window
 */
export function listHudWatchPaneIdsInCurrentWindow(
  currentPaneId?: string,
): string[] {
  try {
    const output = rmuxExec([
      'list-panes',
      '-F',
      '#{pane_id}\t#{pane_current_command}\t#{pane_start_command}',
    ]);
    return findHudWatchPaneIds(parseRmuxPaneSnapshot(output), currentPaneId);
  } catch {
    return [];
  }
}

/**
 * Create HUD watch pane in current window
 * Returns pane ID or null on failure
 */
export function createHudWatchPane(cwd: string, hudCmd: string): string | null {
  try {
    const wrappedCmd = wrapWithLoginShell(hudCmd);
    const output = rmuxExec([
      'split-window',
      '-v',
      '-l',
      '4',
      '-d',
      '-c',
      cwd,
      '-P',
      '-F',
      '#{pane_id}',
      wrappedCmd,
    ]);
    const paneId = output.split('\n')[0]?.trim() || '';
    return paneId.startsWith('%') ? paneId : null;
  } catch {
    return null;
  }
}

/**
 * Kill tmux pane by ID
 */
export function killRmuxPane(paneId: string): void {
  if (!paneId.startsWith('%')) return;
  try {
    rmuxExec(['kill-pane', '-t', paneId], { stdio: 'ignore' });
  } catch {
    // Pane may already be gone; ignore
  }
}
