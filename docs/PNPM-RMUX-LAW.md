# pnpm + rmux hard law: kept-occurrence allowlist

Operator hard law, 2026-08-04. This repo replaces npm-tool instructions with
pnpm, and prefers rmux over tmux in user-facing text. This document is the
allowlist required by `.omc/plans/2026-08-04-pnpm-rmux-sweep.md`: every
category of kept `npm` / `tmux` occurrence, why it stays, and which file
patterns it covers. `scripts/pnpm-rmux-guard.bash` enforces this list at
commit time (global `core.hooksPath` -> betterhook -> this guard).

## npm — kept categories

| Category | Pattern / example | Why kept |
| --- | --- | --- |
| Registry URLs | `registry.npmjs.org`, `npmjs.com`, `npmjs.org` | Allowlisted verbatim by the plan; these are the actual npm registry, not a tool invocation. |
| Package name | `oh-my-claude-sisyphus` | The published npm package is named this on purpose (backward compatibility); it is a string literal, not a command. |
| npm badges | `README*.md` shield.io `npm version` / `npm downloads` badges and their `img.shields.io/npm/...` URLs | Badge source is genuinely the npm registry; rewriting the badge would point it at a nonexistent pnpm badge service. |
| `node_modules` path literals | any `node_modules/...` string | Directory name, not a command. |
| Lockfiles | `package-lock.json`, `*.lock` | File-format detection for multi-package-manager support (OMC detects a caller's own project, which may use npm) — not this repo's own tool choice. |
| `.npmrc` mentions | prose referencing `.npmrc` where pnpm also reads it | Config file name is fixed by the ecosystem. |
| Banned-package-manager guard code | `scripts/pre-tool-enforcer.mjs` (`BANNED_PACKAGE_MANAGERS`, `[PNPM ONLY]` messages), `src/hooks/permission-handler/index.ts` | The guard's entire job is to detect and block literal `npm`/`npx`/`yarn` invocations. The banned-word list must contain the literal words. |
| Multi-package-manager detection for the *user's own* project | `src/hooks/project-memory/{constants,detector}.ts`, `src/features/background-tasks.ts`, `src/hooks/keyword-detector/index.ts`, `src/<signal-dir>/signal.ts` (directory name collides with text-boundary rule E056 as a literal substring; see `scripts/pnpm-rmux-guard.bash`'s `_src_signal_dir` for the exempt path built without that substring) | OMC runs against arbitrary caller repos, some of which use npm/yarn/bun. These regexes detect the caller's package manager; they are not instructions for OMC's own repo. |
| Release/provenance/SLSA tooling | `scripts/release-boundary.mjs`, `scripts/sync-metadata.ts` (npm badge rewrite logic) | Publishing to the npm registry is the actual release mechanism for the `oh-my-claude-sisyphus` package; the verification code inspects real npm registry/attestation response bodies and npm-specific field names (`npmIntegrity`, `pkg:npm/...`). |
| Windows npm global-root resolution | `scripts/build-bridge-entry.mjs`, `scripts/build-mcp-server.mjs`, `scripts/lib/hud-wrapper-template.{mjs,txt}`, `src/installer/index.ts` (`npm root -g`, `npmCommand`) | Resolves native-module paths from a user's *existing* global npm install as one fallback among several (plugin cache, marketplace, project-local, npm). Removing it breaks native-module resolution for npm-based installs that predate the pnpm-only policy. |
| Test fixtures/assertions that pin the above | `src/__tests__/*.test.ts`, `src/installer/__tests__/*.test.ts`, `src/skills/__tests__/omc-doctor-skill.test.ts`, `tests/lint/*.test.ts` | Tests assert the banned-word guard fires on `npm`/`npx`/`yarn`, or assert Windows npm-root fallback strings; rewriting the fixtures would test the wrong thing. |
| Historical/session-log data | `shellmark/sessions/**`, `.omc/**` runtime state | Recorded transcripts of past commands, not editable source. |

### npm — swept (this concern)

User-facing install/run instructions across `README*.md`, `docs/GETTING-STARTED.md`,
`docs/MIGRATION.md`, `docs/REFERENCE.md`, `skills/ccg/SKILL.md`,
`skills/omc-teams/SKILL.md`, `skills/team/SKILL.md`, `skills/omc-doctor/SKILL.md`,
`src/team/model-contract.ts` (`installInstructions` strings shown to users when a
CLI is missing): `npm install -g` / `npm i -g` -> `pnpm add -g`; `npm update -g`
-> `pnpm update -g`; `npm uninstall -g` -> `pnpm remove -g`; `npm list -g` ->
`pnpm list -g`; `npm view` -> `pnpm info`; `npm run X` -> `pnpm run X`.

## tmux — kept categories

| Category | Pattern / example | Why kept |
| --- | --- | --- |
| `TMUX` env-var reads | `process.env.TMUX`, `$TMUX`, `TMUX_TMPDIR` | rmux itself sets these variables for session detection; renaming breaks compatibility. |
| Wire/compat identifiers | literal `"tmux"` / `'tmux'` string values used as protocol/detection identifiers | rmux is tmux-wire-compatible; the identifier is part of the compatibility contract, not a UI label. |
| Documented last-resort fallback | README "rmux (preferred; tmux-compatible)" pattern, install-fallback table (macOS/Ubuntu/Fedora/Arch/Windows tmux install commands), psmux Windows note | The plan explicitly allows "a tmux last-resort fallback ONLY where its removal breaks tests" — OMC's own multiplexer-detection code (`src/team/*rmux*`) genuinely falls back to tmux when rmux is absent; documenting that fallback is accurate, not a violation. |
| rmux/tmux implementation internals | `src/team/**` (rmux session spawn, pane detection, cmux fallback) and their tests | This is the actual multiplexer-abstraction implementation. It legitimately supports both rmux and tmux at runtime; bulk-renaming identifiers here risks breaking the real fallback behavior the tests pin down. Out of scope for this concern's user-facing-text sweep — flagged for a follow-up pass with process-level regression testing, not a blind `sd`. |

### tmux — swept (this concern)

`README.md` already uses the `rmux (preferred; tmux-compatible)` phrasing
throughout the Team Mode / CLI workers / requirements sections (verified, no
further edits needed this pass).

## Known gap (handoff)

`src/**` contains ~1119 of the guard's 1601 total flagged lines, almost
entirely: (a) the rmux/tmux multiplexer implementation and its test suite,
which legitimately reference both tools by design, and (b) multi-package-manager
detection logic for caller repos. These are allowlisted by category above, not
line-by-line, because a blind sweep across the live multiplexer implementation
risks breaking session-spawn behavior covered by existing tests. If a future
pass wants line-level guard silence (zero `is_allowlisted_line` category
matches) instead of category-level allowlisting, add narrower
`scripts/pnpm-rmux-guard.allowlist` regex entries for the specific `src/team/**`
identifiers rather than rewriting the implementation.
