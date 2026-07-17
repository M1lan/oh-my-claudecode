/**
 * Global test setup: strip host-multiplexer env vars.
 *
 * tmux-utils resolves the active multiplexer (tmux vs rmux) from process.env
 * (TMUX / TMUX_PROGRAM / TERM_PROGRAM). When the test suite is run from inside a
 * tmux or rmux session those vars leak in and make command-resolution tests
 * non-deterministic. Delete them up front so every test starts from a clean
 * "no multiplexer" baseline; tests that need one stub it explicitly with
 * vi.stubEnv(), which is restored after each test.
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
]) {
  delete process.env[key];
}
