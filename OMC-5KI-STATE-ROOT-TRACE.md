# bead oh-my-claudecode-5ki — `.omc` root resolution trace (session handoff)

**Date:** 2026-07-26 · **Branch:** `mymain` · **Status: TRACE ONLY — no code changed.**

Read-only survey of every `.omc` root resolver in `scripts/` and `src/`, done before
touching anything, per the bead's own precondition. Resume from "Next actions" at the
bottom.

---

## Bead summary

`oh-my-claudecode-5ki` (P2, bug, open, owner milan.santosi, created 2026-07-22):
"Centralize .omc root resolution in scripts/lib/state-root.mjs (real root cause of
nested .omc)".

Root cause per the bead (stash-verified; corrects the earlier tracer diagnosis in
bead `ob2`): ~7 `.mjs`/`.cjs` hooks anchor `.omc/` at **raw cwd** — `main()` →
`resolveOmcStateRoot(rawCwd)` → `getOmcRoot(rawCwd)`, and `getOmcRoot` honors an
explicit dir verbatim by contract. cwd = subdir ⇒ nested `.omc`, deterministic.
The TS hook layer is already correct via `resolveToWorktreeRoot()` (#576 fix).

Wanted fix: `resolveOmcStateRoot` resolution order becomes
`.omc-workspace`-marker-first → git-climb → `findGitRootByFsWalk` rescue (added in
`2e7d8fb5`), mirroring `getOmcRoot`'s internal order.

Hard constraint from the bead: MUST NOT break non-git `.omc-workspace` multi-repo
workspaces — documented contract, `worktree-paths-superproject-cache.test.ts`, 200+
`getOmcRoot` call sites. **Needs marker test coverage before the change.**

Mitigations already landed in `2e7d8fb5`: `**/.omc/` gitignore, post-tool-verifier
live fix, fs-walk rescue in the TS layer.

---

## Canonical resolvers (source of truth)

| Location | Role |
|---|---|
| `src/lib/worktree-paths.ts:619` `getOmcRoot` | OMC_STATE_DIR → `findWorkspaceRoot` → `resolveStateAnchorRoot` |
| `src/lib/worktree-paths.ts:97` `findWorkspaceRoot` | `.omc-workspace` walk-up, stops before `$HOME` |
| `src/lib/worktree-paths.ts:253` `resolveStateAnchorRoot` | **explicit arg wins verbatim** (only superproject climb) — this is the contract the bug rides on |
| `src/lib/worktree-paths.ts:270` `getGitTopLevel` | literal toplevel, no submodule climb (containment checks) |
| `src/lib/worktree-paths.ts:1065` `resolveSessionStatePaths` | session-scoped read/write pair |
| `src/lib/worktree-paths.ts:1192` `findGitRootByFsWalk` | fs rescue |
| `src/lib/worktree-paths.ts:1229` `resolveToWorktreeRoot` | what the TS hook layer uses (correct) |
| `scripts/lib/state-root.mjs` / `.cjs` | thin async delegator to `dist/lib/worktree-paths.js`; inline fallback is bare `join(directory, '.omc')` |

---

## Class 1 — raw-cwd feeders (the bead's actual bug)

These *do* call `resolveOmcStateRoot`, but hand it un-climbed cwd, so delegation is
defeated. `resolveOmcStateRoot` is a pass-through, so raw cwd flows into `getOmcRoot`.

| file:line (entry) | consumer line(s) | argument |
|---|---|---|
| `scripts/pre-tool-enforcer.mjs:1461` | `:1466`, `:678` | `extractJsonField(input,'cwd') \|\| ... \|\| process.cwd()` |
| `scripts/post-tool-verifier.mjs:1149` | — | `data.cwd \|\| data.directory \|\| process.cwd()` |
| `scripts/post-tool-use-failure.mjs:420` | `:306` | same |
| `scripts/keyword-detector.mjs:1523` | `:1525`, `:1053` | same |
| `scripts/persistent-mode.mjs:1213` | `:1217`, `:977` | same |
| `scripts/verify-deliverables.mjs:153` | `:155` | same |
| `scripts/code-simplifier.mjs:93` | `:94` | same |
| `scripts/session-start.mjs:914` | `:920` | `validateCwd()` — walks up but **returns the original candidate** (`:444`), so still raw cwd |
| `scripts/persistent-mode.cjs:814`, `:1036` | — | same, via `state-root.cjs` |

Fixing the resolver fixes all nine at once. That is exactly why the bead targets
`state-root.mjs` rather than the call sites.

---

## Class 2 — duplicate resolvers that never touch `state-root.mjs`

- `scripts/pre-tool-enforcer.mjs:486` `resolveOmcRoot` + `:451` `findGitRootByFsWalk`
- `scripts/post-tool-verifier.mjs:89` `resolveOmcRoot` + `:54` `findGitRootByFsWalk`

~95 lines, byte-identical to each other, and they **already implement** the exact
marker-first / git-climb / fs-walk order the bead wants in `state-root.mjs`. Lift from
here. Both **warn and fall through** on `OMC_STATE_DIR`
(`pre-tool-enforcer.mjs:490`, `post-tool-verifier.mjs:93`) — centralized state is
silently ignored on that path. Live callers: `post-tool-verifier.mjs:662`, `:694`,
`:986`.

- `scripts/skill-injector.mjs:102` `resolveOmcRootSync` — third, **weaker** copy:
  marker-or-`.git` walk, no `$HOME` stop, no fs-walk rescue, no `OMC_STATE_DIR`
  handling at all. Called at `:586`.

---

## Class 3 — raw literals, no resolver at all

Scripts:

- `scripts/pre-tool-enforcer.mjs:784`, `:823` — `join(directory, '.omc', 'ultragoal', 'goals.json')`
- `scripts/pre-tool-enforcer.mjs:1298` — `join(process.cwd(), '.omc', 'config.json')`
- `scripts/session-start.mjs:488` — `join(directory, '.omc', 'config.json')`

`src/team/**` — bypasses `getOmcRoot` entirely; no `OMC_STATE_DIR`, no
`.omc-workspace` anchoring:

- `src/team/state-paths.ts:35-202` — ~50 builders returning bare relative
  `` `.omc/state/team/…` ``, anchored by `join(cwd, …)` at `:247`, `:268`, `:270`
- `src/team/scaling.ts:426` — `` `${leaderCwd}/.omc/state/team/${sanitized}` ``
- `src/team/runtime.ts:143`, `:416`, `:1096`
- `src/team/runtime-cli.ts:1201`
- `src/team/tmux-comm.ts:187`

Other:

- `src/openclaw/dedupe.ts:23` + `:88` — `const STATE_DIR = ['.omc','state']` spread
  into `join(projectPath, ...STATE_DIR)`

---

## Not bypasses (global per-user config — correctly out of scope)

`scripts/lib/config-dir.{mjs,cjs}:32`, `src/utils/paths.ts:92`, `src/hud/state.ts:81`,
`scripts/code-simplifier.mjs:41`, `scripts/persistent-mode.mjs:206` and `:1219`,
`scripts/skill-injector.mjs:635`, `src/hooks/learner/bridge.ts:32`,
`src/tools/state-tools.ts:531` and `:537` — all `homedir()` / `getClaudeConfigDir()`
rooted.

Compliant consumers (leave alone): `src/lib/mode-state-io.ts`,
`src/tools/state-tools.ts`, `src/hud/elements/multi-repo.ts`,
`src/hooks/learner/bridge.ts:242`, `src/installer/index.ts:2837`.

---

## CI gate state — currently RED, and blind

`node scripts/ci/check-multirepo-paths.mjs` → **FAIL, 14 hits** as of this session.

All 14 are inside the live agent worktree
`.claude/worktrees/agent-aeb447c741d43cdbe/` plus `tests/`. Cause: the whitelist
(`scripts/ci/check-multirepo-paths.mjs:27-42`) holds absolute paths under
`REPO_ROOT`, and `SKIP_DIRS` (`:117`) omits `.claude`, so the walker descends into
registered agent worktrees and re-flags whitelisted files under their worktree copy
paths. **The gate goes red whenever an agent worktree exists** — noise, not a real
regression, but it means the gate is not gating right now.

Blind spots that let Class 3 through:

1. Patterns only match `join($_, '.omc', …)` and `` `${$_}/.omc/$$$` ``. Bare
   `` `.omc/state/team/…` `` with no leading interpolation matches nothing — the whole
   `src/team/state-paths.ts` family is invisible.
2. Array-spread (`...STATE_DIR`) is invisible — `src/openclaw/dedupe.ts`.
3. `src/team/scaling.ts:426` fits the template pattern on paper yet was **not**
   reported — ast-grep template matching is not firing there. Worth a direct probe
   before trusting that pattern.
4. `pre-tool-enforcer.mjs`, `post-tool-verifier.mjs`, `skill-injector.mjs`,
   `session-start.mjs` are file-whitelisted for their "own resolver", which also
   grants blanket cover to their Class 3 raw literals.

---

## Next actions (resume here)

1. **Marker tests first.** Land coverage for the non-git `.omc-workspace` contract.
   The bead names this as the precondition; nothing else is safe until it exists.
2. **Move the logic into `state-root.mjs`** — marker-first → git-climb → fs-walk
   rescue, lifted from `pre-tool-enforcer.mjs:486`. Class 1's nine sites then need no
   edits.
3. **Delete the duplicates** (`pre-tool-enforcer.mjs:486`, `post-tool-verifier.mjs:89`,
   `skill-injector.mjs:102`), re-pointing `post-tool-verifier.mjs:662/694/986` and
   `skill-injector.mjs:586` at the shared resolver.
   ⚠ **Sync/async mismatch:** those four call sites are synchronous;
   `resolveOmcStateRoot` is async. Needs either a sync export from `state-root.mjs` or
   a call-site refactor. Decide this before starting step 2.
4. **`src/team/**` + `src/openclaw/dedupe.ts`** — separate, larger change. Give it its
   own bead rather than letting it ride along.
5. **Gate fixes, last:** add `.claude` to `SKIP_DIRS`, add a bare-relative-literal
   pattern, verify the `` `${$_}/.omc/$$$` `` pattern actually fires, then shrink the
   four file whitelists once step 3 removes the duplicate resolvers.

## Build reminder

Anything touched under `src/**/*.ts` needs `pnpm run build` before the running plugin
sees it — it loads `dist/`, not `src/`. `.mjs`/`.cjs`/`.md` load from disk, no build.

## Related open beads

- `oh-my-claudecode-6o2` — deferred: one clean full `pnpm test` sweep for the
  2026-07-26 fixes (local-source update channel, `installMethod`, `resolve-node`).
- `oh-my-claudecode-d3v` — `hooks-command-escaping.test.ts` local timeout;
  environmental, not a regression.
- `oh-my-claudecode-ob2` — earlier, superseded diagnosis of the nested-`.omc` bug.
