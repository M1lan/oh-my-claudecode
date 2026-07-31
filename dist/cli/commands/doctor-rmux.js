/**
 * `omc doctor rmux` — detect the rmux multiplexer and optionally install it.
 *
 * Read-only by default (detect + suggest a command). With `--install` it runs
 * the non-fatal installer (cargo binstall / local source / cargo). rmux is
 * POSIX-only; on native Windows this reports "not applicable" (OMC uses
 * tmux/psmux there). Never returns a non-zero exit for a missing/failed rmux —
 * rmux is optional and OMC falls back to tmux.
 */
import { colors } from '../utils/formatting.js';
import { detectRmux, ensureRmuxInstalled, planRmuxInstall, RMUX_MANUAL_INSTRUCTIONS, } from '../rmux-install.js';
export async function doctorRmuxCommand(options) {
    if (options.install) {
        const result = ensureRmuxInstalled();
        if (options.json) {
            console.log(JSON.stringify(result, null, 2));
        }
        // Install is best-effort — never hard-fail the surrounding setup flow.
        return 0;
    }
    const detected = detectRmux();
    const plan = planRmuxInstall();
    if (options.json) {
        console.log(JSON.stringify({
            installed: detected.installed,
            version: detected.version,
            method: plan.method,
            suggestedCommand: plan.command,
        }, null, 2));
        return 0;
    }
    console.log(colors.bold('rmux multiplexer — availability probe'));
    if (detected.installed) {
        console.log(`  ${colors.green('✓')} rmux: ${detected.version ?? 'installed'}`);
    }
    else if (process.platform === 'win32') {
        console.log(`  ${colors.gray('ℹ')} rmux is POSIX-only — not applicable on native Windows (OMC uses tmux/psmux).`);
    }
    else {
        console.log(`  ${colors.yellow('⚠')} rmux not found on PATH — OMC falls back to tmux.`);
        if (plan.command) {
            console.log(`    Install: ${plan.command}`);
            console.log(`    ${colors.gray('Or run: omc doctor rmux --install')}`);
        }
        else {
            console.log(colors.gray(RMUX_MANUAL_INSTRUCTIONS));
        }
    }
    return 0;
}
//# sourceMappingURL=doctor-rmux.js.map