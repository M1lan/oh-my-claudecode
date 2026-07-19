/**
 * Global test setup: strip host env vars that leak into the suite.
 *
 * tmux-utils resolves the active multiplexer (tmux vs rmux) from process.env
 * (TMUX / TMUX_PROGRAM / TERM_PROGRAM). When the test suite is run from inside a
 * tmux or rmux session those vars leak in and make command-resolution tests
 * non-deterministic.
 *
 * Likewise, OMC's own runtime flags (DISABLE_OMC / OMC_SKIP_HOOKS) are commonly
 * exported in a developer's shell. When present they make env-sensitive checks
 * (e.g. doctor-conflicts checkEnvFlags) report a real-but-ambient conflict,
 * which flips hasConflicts and breaks tests that assert a clean baseline.
 *
 * Delete them up front so every test starts from a clean baseline; tests that
 * need one stub it explicitly with vi.stubEnv() (or an explicit child-process
 * env), which is restored after each test.
 */
for (const key of [
  'TMUX',
  'TMUX_PANE',
  'TMUX_PROGRAM',
  'RMUX',
  'RMUX_PANE',
  'TERM_PROGRAM',
  'PSMUX_SESSION',
  'CMUX_SURFACE_ID',
  'DISABLE_OMC',
  'OMC_SKIP_HOOKS',
]) {
  delete process.env[key];
}
