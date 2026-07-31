import { rmuxExec, rmuxExecAsync } from './rmux-utils.js';
const UNIVERSAL_CLIPBOARD_FEATURE = '*:clipboard';
export function hasUniversalClipboardTerminalFeature(features) {
    return features
        .split(/\r?\n|,/)
        .map((feature) => feature.trim())
        .some((feature) => feature === UNIVERSAL_CLIPBOARD_FEATURE ||
        feature.startsWith(`${UNIVERSAL_CLIPBOARD_FEATURE}:`));
}
export function configureTmuxClipboardForSession(sessionName, opts) {
    rmuxExec(['set-option', '-t', sessionName, 'set-clipboard', 'on'], opts);
    let terminalFeatures = '';
    try {
        terminalFeatures = String(rmuxExec(['show-options', '-t', sessionName, '-v', 'terminal-features'], opts) ?? '');
    }
    catch {
        terminalFeatures = '';
    }
    if (!hasUniversalClipboardTerminalFeature(terminalFeatures)) {
        rmuxExec([
            'set-option',
            '-at',
            sessionName,
            'terminal-features',
            `,${UNIVERSAL_CLIPBOARD_FEATURE}`,
        ], opts);
    }
}
export function configureTmuxClipboardForCurrentSession(opts) {
    const sessionName = String(rmuxExec(['display-message', '-p', '#S'], opts) ?? '').trim();
    if (sessionName) {
        configureTmuxClipboardForSession(sessionName, opts);
    }
}
export async function configureTmuxClipboardForSessionAsync(sessionName, opts) {
    await rmuxExecAsync(['set-option', '-t', sessionName, 'set-clipboard', 'on'], opts);
    let terminalFeatures = '';
    try {
        const result = await rmuxExecAsync(['show-options', '-t', sessionName, '-v', 'terminal-features'], opts);
        terminalFeatures = String(result.stdout ?? '');
    }
    catch {
        terminalFeatures = '';
    }
    if (!hasUniversalClipboardTerminalFeature(terminalFeatures)) {
        await rmuxExecAsync([
            'set-option',
            '-at',
            sessionName,
            'terminal-features',
            `,${UNIVERSAL_CLIPBOARD_FEATURE}`,
        ], opts);
    }
}
//# sourceMappingURL=rmux-clipboard.js.map