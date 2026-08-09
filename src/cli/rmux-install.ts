/**
 * rmux installation helper.
 *
 * rmux is the preferred tmux-compatible multiplexer OMC drives on POSIX hosts
 * (phases 1-4 make OMC prefer the rmux binary everywhere it is available). This
 * module detects an existing rmux and, when asked, installs it — always
 * non-fatally: if rmux cannot be installed, OMC still falls back to tmux, so
 * setup and doctor never hard-fail on a missing rmux.
 *
 * Install precedence (POSIX only; native Windows is a no-op — rmux is
 * POSIX-only and OMC uses tmux/psmux there):
 *   1. rmux already on PATH                     → nothing to do
 *   2. ~/mysrc/rmux local source + cargo present → cargo install --path (source)
 *   3. cargo-binstall present                    → cargo binstall -y rmux
 *   4. cargo present                             → cargo install rmux --locked
 *   5. none of the above                         → warn + manual instructions
 */

import { spawnSync } from 'child_process';
import { existsSync } from 'fs';
import { homedir } from 'os';
import { join } from 'path';
import { colors } from './utils/formatting.js';

/** How rmux would be (or was) installed. */
export type RmuxInstallMethod =
  'present' | 'local-source' | 'cargo-binstall' | 'cargo' | 'unavailable';

export interface RmuxDetectResult {
  installed: boolean;
  version: string | null;
}

export interface RmuxInstallPlan {
  method: RmuxInstallMethod;
  /** Binary to spawn (null when nothing to run). */
  bin: string | null;
  /** Args for `bin` (null when nothing to run). */
  args: string[] | null;
  /** Human-readable command, e.g. `cargo binstall -y rmux` (null when N/A). */
  command: string | null;
  /** Populated for `present` — the detected version string. */
  version?: string | null;
  /** Populated for `local-source` — the resolved ~/mysrc/rmux path. */
  localSourcePath?: string;
}

export interface RmuxInstallResult {
  method: RmuxInstallMethod;
  status: 'already-installed' | 'installed' | 'failed' | 'skipped';
  version: string | null;
  message: string;
}

export interface EnsureRmuxOptions {
  /** Where to route human-readable progress/warnings. Defaults to console.log. */
  log?: (message: string) => void;
  /** When false, only plan (no install). Defaults to true. */
  execute?: boolean;
}

/** Manual install hints, printed when auto-install is impossible or fails. */
export const RMUX_MANUAL_INSTRUCTIONS = [
  'Install rmux manually (POSIX):',
  '  cargo binstall rmux      # prebuilt binary (recommended)',
  '  cargo install rmux       # build from source via cargo',
  '  brew install rmux        # macOS Homebrew',
  'rmux is optional — OMC falls back to tmux when it is absent.',
].join('\n');

/** Spawn a probe command, reporting success and captured stdout. */
function probeCommand(
  bin: string,
  args: string[],
): { ok: boolean; stdout: string } {
  try {
    const result = spawnSync(bin, args, { timeout: 5000, encoding: 'utf-8' });
    return {
      ok: result.status === 0,
      stdout: typeof result.stdout === 'string' ? result.stdout : '',
    };
  } catch {
    return { ok: false, stdout: '' };
  }
}

/**
 * Detect an rmux binary on PATH via `rmux -V` (rmux prints its version to `-V`;
 * `--version` only prints usage). POSIX only — native Windows always reports
 * absent because rmux does not run there.
 */
export function detectRmux(): RmuxDetectResult {
  if (process.platform === 'win32') return { installed: false, version: null };
  const probe = probeCommand('rmux', ['-V']);
  if (!probe.ok) return { installed: false, version: null };
  const version = probe.stdout.trim().split('\n')[0] || null;
  return { installed: true, version };
}

/**
 * Resolve the local rmux source checkout (`~/mysrc/rmux`) when it looks like a
 * cargo project. Used to prefer installing from the operator's local source.
 */
export function rmuxLocalSourcePath(home: string = homedir()): string | null {
  const dir = join(home, 'mysrc', 'rmux');
  if (existsSync(dir) && existsSync(join(dir, 'Cargo.toml'))) return dir;
  return null;
}

/**
 * Decide how rmux would be installed on this host without executing anything.
 */
export function planRmuxInstall(): RmuxInstallPlan {
  if (process.platform === 'win32') {
    return { method: 'unavailable', bin: null, args: null, command: null };
  }

  const detected = detectRmux();
  if (detected.installed) {
    return {
      method: 'present',
      bin: null,
      args: null,
      command: null,
      version: detected.version,
    };
  }

  const localSource = rmuxLocalSourcePath();
  const hasCargo = probeCommand('cargo', ['--version']).ok;
  const hasBinstall = probeCommand('cargo-binstall', ['-V']).ok;

  // Operator preference: build from the local checkout when it exists and cargo
  // can compile it. binstall pulls from the registry, so it cannot honour the
  // local-source exception — only cargo install --path does.
  if (localSource && hasCargo) {
    const args = ['install', '--path', localSource, '--locked'];
    return {
      method: 'local-source',
      bin: 'cargo',
      args,
      command: `cargo ${args.join(' ')}`,
      localSourcePath: localSource,
    };
  }

  if (hasBinstall) {
    const args = ['binstall', '-y', 'rmux'];
    return {
      method: 'cargo-binstall',
      bin: 'cargo',
      args,
      command: `cargo ${args.join(' ')}`,
    };
  }

  if (hasCargo) {
    const args = ['install', 'rmux', '--locked'];
    return {
      method: 'cargo',
      bin: 'cargo',
      args,
      command: `cargo ${args.join(' ')}`,
    };
  }

  return { method: 'unavailable', bin: null, args: null, command: null };
}

/**
 * Ensure rmux is installed, non-fatally. Returns a structured result; never
 * throws for an install failure — OMC falls back to tmux when rmux is missing.
 */
export function ensureRmuxInstalled(
  options: EnsureRmuxOptions = {},
): RmuxInstallResult {
  const log = options.log ?? ((message: string) => console.log(message));
  const execute = options.execute ?? true;
  const plan = planRmuxInstall();

  if (plan.method === 'present') {
    const version = plan.version ?? null;
    return {
      method: 'present',
      status: 'already-installed',
      version,
      message: `rmux already installed${version ? ` (${version})` : ''}`,
    };
  }

  if (plan.method === 'unavailable') {
    const message =
      process.platform === 'win32'
        ? 'rmux is POSIX-only and unavailable on native Windows; OMC uses tmux/psmux there.'
        : 'Could not install rmux automatically (no cargo or cargo-binstall found).';
    log(colors.yellow(`⚠ ${message}`));
    log(colors.gray(RMUX_MANUAL_INSTRUCTIONS));
    return { method: 'unavailable', status: 'skipped', version: null, message };
  }

  if (!execute) {
    return {
      method: plan.method,
      status: 'skipped',
      version: null,
      message: `rmux not installed; suggested: ${plan.command}`,
    };
  }

  log(`Installing rmux via: ${plan.command}`);
  let status: number | null = null;
  try {
    const result = spawnSync(plan.bin as string, plan.args as string[], {
      stdio: 'inherit',
      timeout: 15 * 60 * 1000,
    });
    status = result.status;
  } catch {
    status = null;
  }

  if (status === 0) {
    const detected = detectRmux();
    return {
      method: plan.method,
      status: 'installed',
      version: detected.version,
      message: `rmux installed via ${plan.method}${detected.version ? ` (${detected.version})` : ''}`,
    };
  }

  const message = `rmux install failed (${plan.command}, exit ${status ?? 'signal'}). OMC will fall back to tmux.`;
  log(colors.yellow(`⚠ ${message}`));
  log(colors.gray(RMUX_MANUAL_INSTRUCTIONS));
  return { method: plan.method, status: 'failed', version: null, message };
}
