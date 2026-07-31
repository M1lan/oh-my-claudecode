/**
 * Interop CLI Command - Split-pane tmux session with OMC and OMX
 *
 * Creates a tmux split-pane layout with Claude Code (OMC) on the left
 * and Codex CLI (OMX) on the right, with shared interop state.
 */
export type InteropMode = 'off' | 'observe' | 'active';
/**
 * Env var exported into the Codex (OMX) pane at interop launch. oh-my-codex
 * reads it on startup and — via its readiness-aware pane injection — activates
 * the caveman skill at this level, deterministically (the primary path).
 * Name is a cross-repo contract: it must match the reader in oh-my-codex.
 */
export declare const INTEROP_CAVEMAN_LEVEL_ENV = "OMX_INTEROP_CAVEMAN_LEVEL";
/**
 * Caveman level OMX speaks inside interop: classical Chinese, max compression.
 * Must be one of oh-my-codex's INTEROP_CAVEMAN_LEVELS (interop-caveman.ts); an
 * unknown value is warned + ignored on the codex side, disabling activation.
 */
export declare const INTEROP_CAVEMAN_LEVEL = "wenyan-ultra";
/**
 * Natural-language activation the Codex caveman skill recognizes ("use caveman"
 * + level). Typed into the pane as a fallback for Codex builds that predate the
 * INTEROP_CAVEMAN_LEVEL_ENV startup hook. Idempotent: re-activating the same
 * level is a no-op, so it is safe even when the env path already fired.
 */
export declare const INTEROP_CAVEMAN_ACTIVATION = "use caveman wenyan-ultra mode";
export interface InteropRuntimeFlags {
    enabled: boolean;
    mode: InteropMode;
    omcInteropToolsEnabled: boolean;
    failClosed: boolean;
}
export declare function readInteropRuntimeFlags(env?: NodeJS.ProcessEnv): InteropRuntimeFlags;
export declare function validateInteropRuntimeFlags(flags: InteropRuntimeFlags): {
    ok: boolean;
    reason?: string;
};
/**
 * Type the caveman activation into the Codex (OMX) pane. Sent as a literal
 * string (`-l`) followed by Enter so shell/tmux never reinterpret its spaces —
 * mirrors the autoresearch setup injection. Failures are swallowed: the OMX
 * pane simply stays at its global caveman level.
 */
export declare function sendInteropCavemanActivation(paneId: string, activation?: string): void;
/**
 * Launch interop session with split tmux panes
 */
export declare function launchInteropSession(cwd?: string, options?: {
    yolo?: boolean;
}): void;
/**
 * CLI entry point for interop command
 */
export declare function interopCommand(options?: {
    cwd?: string;
    yolo?: boolean;
}): void;
//# sourceMappingURL=interop.d.ts.map