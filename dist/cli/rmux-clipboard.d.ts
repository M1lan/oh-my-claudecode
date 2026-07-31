import { rmuxExec, rmuxExecAsync } from './rmux-utils.js';
type SyncTmuxClipboardOptions = Parameters<typeof rmuxExec>[1];
type AsyncTmuxClipboardOptions = Parameters<typeof rmuxExecAsync>[1];
export declare function hasUniversalClipboardTerminalFeature(features: string): boolean;
export declare function configureTmuxClipboardForSession(sessionName: string, opts?: SyncTmuxClipboardOptions): void;
export declare function configureTmuxClipboardForCurrentSession(opts?: SyncTmuxClipboardOptions): void;
export declare function configureTmuxClipboardForSessionAsync(sessionName: string, opts?: AsyncTmuxClipboardOptions): Promise<void>;
export {};
//# sourceMappingURL=rmux-clipboard.d.ts.map