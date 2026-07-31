/**
 * `omc doctor rmux` — detect the rmux multiplexer and optionally install it.
 *
 * Read-only by default (detect + suggest a command). With `--install` it runs
 * the non-fatal installer (cargo binstall / local source / cargo). rmux is
 * POSIX-only; on native Windows this reports "not applicable" (OMC uses
 * tmux/psmux there). Never returns a non-zero exit for a missing/failed rmux —
 * rmux is optional and OMC falls back to tmux.
 */
export interface DoctorRmuxOptions {
    json?: boolean;
    install?: boolean;
}
export declare function doctorRmuxCommand(options: DoctorRmuxOptions): Promise<number>;
//# sourceMappingURL=doctor-rmux.d.ts.map