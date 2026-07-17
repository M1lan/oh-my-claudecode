# Fork-sync merge playbook (mymain ← main/upstream)

Repo-specific knowledge for resolving merges of upstream `main` into the
fork branch `mymain`. Captured 2026-06-15 during a `Merge branch 'main'
into mymain` with 137 conflicted paths.

## Branch / remote topology

- `mymain` — the user's working fork branch (authoritative for local work).
- `main` — local tracking of `origin/main` (the fork's main, which tracks
  `upstream/main`, i.e. the real oh-my-claudecode upstream).
- `upstream/*` — read-only upstream (qdrant-style: fetch/pull only).
- Default branch is `main` here (NOT `master`). `git pull main` /
  `git merge main` as bare commands fail: `main` is a ref, not a remote,
  and `pull`/`merge` want `git pull origin main` / `git merge main` from a
  different branch. The fork-sync flow is: `gu` (fetch+pull all) → switch
  to `mymain` → `git merge main`.

## The dominant conflict class is NOISE, not signal

`mymain` deliberately does NOT track build artifacts; upstream `main`
DOES. Every fork-sync therefore produces thousands of phantom conflicts.

`.gitignore` on `mymain` lists these as generated / never-commit:

- `dist/` — TS build output (`pnpm run build`). ~4225 files tracked on
  `main`, 0 on `mymain`.
- `bridge/` — build output. EXCEPTION: `bridge/gyoshu_bridge.py` IS source
  and tracked. Everything else under `bridge/` is generated.
- `.github/release-body.md` — generated dynamically per release.
- `package-lock.json` / `npm-shrinkwrap.json` / `yarn.lock` — pnpm is the
  ONLY supported package manager. Lockfile is `pnpm-lock.yaml`.
- `pnpm-workspace.yaml` — also untracked here.

These surface as `DU` (deleted-by-us / modified-by-them) conflicts.

### Resolution rule (100% mechanical, no judgement)

For every conflicted path matching a "never-commit / generated"
`.gitignore` rule: keep the deletion.

```bash
# remove all DU conflicts that are generated artifacts
git diff --name-only --diff-filter=U \
  | rg '^(dist/|bridge/.*\.(c?js|d\.ts)(\.map)?$|\.github/release-body\.md$|package-lock\.json$)' \
  | xargs -r git rm -f --
```

Then rebuild after the merge: `pnpm install && pnpm run build`.
Do NOT hand-merge any `dist/` / `bridge/` content — it is regenerated.

## The real conflicts (signal)

Only `UU` (both-modified) conflicts in tracked SOURCE need real attention.
In the 2026-06-15 merge that was 19 files:

- `CHANGELOG.md` — combine both sides' entries (union; keep upstream's new
  version sections + the fork's entries). Mechanical-ish, low risk.
- `skills/omc-teams/SKILL.md`
- 17 `src/**/*.ts` (team runtime, cli/commands/team, hooks, config loader,
  scaling, etc.) — these touch orchestration logic. Treat as MEANINGFUL.

### Watch for formatting-vs-content collisions

`mymain` periodically runs `prettier --write "src/**/*.ts"` (see reflog:
"format all src with Prettier"). Most `src/**/*.ts` `UU` conflicts are the
fork's reformatting (single quotes, line-wrapping) colliding with
upstream's content edits.

The recurring three-way shape (diff3, base = `deee3a44`):

- ours/HEAD (mymain): base content, prettier-reformatted, providers
  `claude/codex/gemini/grok`.
- theirs/main (upstream): base content + NEW functionality.

Upstream's new functionality in the 2026-06-15 sync:

- `cursor` added as a 5th CLI provider/agent type across ~10 files
  (loader schema enums, scaling `CLI_AGENT_TYPES`, team-status cast,
  keyword-detector patterns + priority, doctor-team-routing, bridge regex,
  runtime model routing `cursor -> undefined`, new loader test).
- `team.ts` issue #3267: `isPreauthoredScopeList` (numbered/bulleted lists
  must match explicit worker count; conjunction splits must not reshape an
  explicit worker spec).
- team runtime: pane-splitting extracted into `splitTeamWorkerPane()`
  (new export from `tmux-session.ts`), replacing inline `tmuxExecAsync`.
- team CLI gained a `--cwd` flag (reflected in `team.test.ts`).
- `session-hooks.ts`: language entries may be objects, mapped via
  `l?.name` instead of raw join.

CAUTION — do NOT blanket `git checkout --theirs` the `.ts` files. The
mymain side is NOT pure whitespace: prettier wrapping changes line
structure and mymain may carry clean-merged content elsewhere in the file.
`diff -w base ours` still reports content diffs, so the shortcut is unsafe.
Resolve per-hunk: take upstream's logic, keep mymain's style, then re-run
`pnpm run format` to normalise. Verify with `pnpm run lint` + `tsc` +
`vitest`.

### Doc conflicts (CHANGELOG.md, skills/omc-teams/SKILL.md)

Not pure formatting — mymain changed install commands `npm -> pnpm`
(pnpm-only policy), upstream bumped versions and expanded provider lists.
Union manually: keep mymain's `pnpm add -g ...` wording, take upstream's
version bump (e.g. `@4.14.7`) and expanded provider list
(`claude/codex/gemini/grok/cursor`).

## Verification gate before committing the merge

1. `pnpm install` (sync deps to merged `package.json`)
2. `pnpm run build` (regenerates dist/ + bridge/)
3. `pnpm run lint`
4. `pnpm run format` (re-apply fork style after content merges)
5. `vitest run` (or `pnpm test`)

Only commit the merge once these pass. Use zagi: `git commit` (no `-m`
override needed for a merge; if overriding, include `--prompt`).

## Decision log

- 2026-06-15: confirmed `dist/`+`bridge/`+`release-body.md`+lockfiles are
  generated via `.gitignore`; resolved all 118 `DU` conflicts by deletion
  with no per-file review. The 19 `UU` source conflicts were escalated for
  real review (delegated / asked) rather than auto-resolved.
