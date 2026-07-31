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
/** How rmux would be (or was) installed. */
export type RmuxInstallMethod = 'present' | 'local-source' | 'cargo-binstall' | 'cargo' | 'unavailable';
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
export declare const RMUX_MANUAL_INSTRUCTIONS: string;
/**
 * Detect an rmux binary on PATH via `rmux -V` (rmux prints its version to `-V`;
 * `--version` only prints usage). POSIX only — native Windows always reports
 * absent because rmux does not run there.
 */
export declare function detectRmux(): RmuxDetectResult;
/**
 * Resolve the local rmux source checkout (`~/mysrc/rmux`) when it looks like a
 * cargo project. Used to prefer installing from the operator's local source.
 */
export declare function rmuxLocalSourcePath(home?: string): string | null;
/**
 * Decide how rmux would be installed on this host without executing anything.
 */
export declare function planRmuxInstall(): RmuxInstallPlan;
/**
 * Ensure rmux is installed, non-fatally. Returns a structured result; never
 * throws for an install failure — OMC falls back to tmux when rmux is missing.
 */
export declare function ensureRmuxInstalled(options?: EnsureRmuxOptions): RmuxInstallResult;
//# sourceMappingURL=rmux-install.d.ts.map