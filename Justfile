# --- oh-my-claudecode Justfile ---
#
# TypeScript / Node multi-agent build harness. Thin Justfile: TUI + logic live
# in .just/helpers/*.bash (GNU Bash >= 5.3). Recipes are one-liners.
#
# Start here:  bare `just`  -> info splash + launchers
#   just menu   guided command builder (gum)
#   just fzf    flat power launcher (fzf, multi-select)
#   just help   plain grouped recipe list
#   just doctor diagnose the toolchain
#
# Package manager: pnpm only (declared in package.json#packageManager).

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false
set positional-arguments := true
set ignore-comments := true

export FORCE_COLOR := "1"
export NODE_OPTIONS := env_var_or_default("NODE_OPTIONS", "--enable-source-maps")

PM := "pnpm"
EDITOR_CMD := env_var_or_default("EDITOR", "vim")
helpers := justfile_directory() / ".just" / "helpers"

# --- Aliases ---

alias m   := menu
alias f   := fzf
alias b   := build
alias bf  := build-fast
alias t   := test
alias tr  := test-run
alias tc  := test-changed
alias tf  := test-file
alias l   := lint
alias lf  := lint-fix
alias ff  := fmt-fix
alias fc  := fmt-check
alias c   := check
alias v   := verify
alias vf  := verify-fast
alias d   := dev
alias h   := help
alias i   := info
alias doc := doctor

# --- Meta ---

# Bare `just`: info splash + launchers (always shows the splash, never --list)
[private]
default:
    @'{{helpers}}/info-screen.bash'

# Guided command builder (gum): pick + parametrize + run a recipe
[no-exit-message]
[group('meta')]
menu:
    @'{{helpers}}/menu.bash'

# Flat power launcher (fzf): multi-select recipes and batch-run them
[no-exit-message]
[group('meta')]
fzf:
    @'{{helpers}}/fzf.bash'

# Plain grouped recipe list
[group('meta')]
help:
    @just --list --list-heading $'oh-my-claudecode -- pick a recipe (group: alpha)\n'

# Static info splash (no countdown) -- identity, facts, tool summary
[group('meta')]
info:
    @'{{helpers}}/info-screen.bash' --static

# Diagnose the toolchain (exits non-zero if a required tool is missing)
[group('meta')]
doctor *args:
    @'{{helpers}}/doctor.bash' "$@"

# Count recipes per group (Justfile gardening)
[group('meta')]
recipes:
    @printf 'recipes: %s\n' "$(just --summary 2>/dev/null | wc -w | tr -d ' ')"
    @printf 'groups:  %s\n' "$(just --groups 2>/dev/null | tail -n +2 | rg -c '.' || echo 0)"
    @printf 'aliases: %s\n' "$(rg -c '^alias\s' Justfile 2>/dev/null || echo 0)"

# --- Install ---

# Install dependencies (clean, reproducible from lockfile)
[group('install')]
install:
    {{PM}} install --frozen-lockfile || {{PM}} install

# Install + rebuild native modules (better-sqlite3 etc.)
[group('install')]
install-rebuild:
    {{PM}} install --frozen-lockfile
    {{PM}} rebuild

# Show outdated dependencies
[group('install')]
outdated:
    @{{PM}} outdated || true

# Interactive update -- prompts for each dependency to bump
[group('install')]
update *args:
    {{PM}} update --interactive --latest "$@"

# --- Build ---

# Full build (TS + every bundle + composed docs)
[group('build')]
build:
    {{PM}} run build

# Fast incremental build -- just tsc, no bundles, no docs (10-20x faster)
[group('build')]
build-fast: build-ts

# Compile TypeScript only (no bundling, no doc compose)
[group('build')]
build-ts:
    {{PM}} exec tsc

# Type-check without emitting
[group('build')]
typecheck:
    {{PM}} exec tsc --noEmit

# Build the unified CLI bundle
[group('build')]
build-cli:
    {{PM}} run build:cli

# Build the MCP server bundle
[group('build')]
build-mcp:
    node scripts/build-mcp-server.mjs

# Build the skill bridge bundle
[group('build')]
build-bridge:
    {{PM}} run build:bridge

# Build the bridge entry bundle
[group('build')]
build-bridge-entry:
    {{PM}} run build:bridge-entry

# Build the runtime CLI bundle
[group('build')]
build-runtime-cli:
    {{PM}} run build:runtime-cli

# Build the team MCP server bundle
[group('build')]
build-team-server:
    {{PM}} run build:team-server

# Build the CLAUDE.md coordinator bundle
[group('build')]
build-coordinator:
    {{PM}} run build:claude-md-coordinator

# Compose docs into bundled markdown
[group('build')]
compose-docs:
    {{PM}} run compose-docs

# Build the prompt SSOT projections (generated/prompt-ssot/)
[group('build')]
prompt-ssot-build:
    {{PM}} run prompt-ssot:build

# Check prompt SSOT projections are in sync (CI gate)
[group('build')]
prompt-ssot-check:
    {{PM}} run prompt-ssot:check

# Measure prompt SSOT token counts
[group('build')]
prompt-ssot-measure:
    {{PM}} run prompt-ssot:measure

# Regenerate prompt projections (generate:prompt-projections)
[group('build')]
prompt-projections:
    {{PM}} run generate:prompt-projections

# Verify prompt projections are fresh (CI gate)
[group('build')]
prompt-projections-verify:
    {{PM}} run verify:prompt-projections

# Regenerate the inventory graph (inventory/inventory-graph.json)
[group('build')]
inventory:
    {{PM}} run generate:inventory

# Verify the inventory graph is fresh (CI gate)
[group('build')]
inventory-verify:
    {{PM}} run generate:inventory:verify

# Show bundle sizes (dust if installed; falls back to du)
[group('build')]
bundle-size:
    @if [[ ! -d dist ]]; then echo "no dist/ -- run 'just build' first"; exit 0; fi
    @if command -v dust >/dev/null 2>&1; then dust -d 2 dist; else du -sh dist/* 2>/dev/null | sort -rh; fi

# --- Dev ---

# Watch TypeScript compilation
[group('dev')]
dev:
    {{PM}} run dev

# Run all watchers concurrently (tsc + every bundler)
[group('dev')]
dev-full:
    {{PM}} run dev:full

# Re-run any recipe whenever src/ or scripts/ changes (requires watchexec)
[group('dev')]
watch recipe='check':
    @if ! command -v watchexec >/dev/null 2>&1; then echo "watchexec not installed -- brew install watchexec"; exit 1; fi
    watchexec --restart --exts ts,mjs,cjs,js,json,md \
              --ignore 'dist/**' --ignore 'node_modules/**' --ignore '.omc/**' \
              -- just '{{recipe}}'

# --- Run ---

# Run the compiled binary entry
[group('run')]
run *args:
    @if [[ ! -f dist/index.js ]]; then echo "dist/index.js missing -- building first"; just build-fast; fi
    node dist/index.js "$@"

# Run the local CLI shim directly (omc)
[group('run')]
cli *args:
    node bridge/cli.cjs "$@"

# Print the local built CLI version (smoke test)
[group('run')]
status:
    @node bridge/cli.cjs --version 2>/dev/null || echo "(no status yet -- run 'just build' first)"

# Smoke-boot the MCP server -- exits cleanly if it boots, fails loudly otherwise
[group('run')]
mcp-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f bridge/mcp-server.cjs ]]; then
        echo "bridge/mcp-server.cjs missing -- run 'just build-mcp' first" >&2
        exit 1
    fi
    timeout 3 node bridge/mcp-server.cjs </dev/null >/dev/null 2>&1 \
        && echo "mcp-smoke: MCP server boots ✓" \
        || { code=$?; if (( code == 124 )); then echo "mcp-smoke: server is alive (timed out as expected)"; else echo "mcp-smoke: server failed to boot (exit $code)" >&2; exit 1; fi; }

# --- Test ---

# Run vitest in watch mode (default test runner)
[group('test')]
test *args:
    {{PM}} test "$@"

# Run the full vitest suite once (CI mode). Process-reap/wall-clock timing
# tests are split into a serialized second pass so the in-suite package build
# (npm-package-bin-surface) cannot CPU-starve their millisecond budgets.
[group('test')]
test-run *args:
    {{PM}} exec vitest run --exclude "tests/perf/**" --exclude "**/session-end-process-exit.test.ts" --exclude "**/run-cjs-generic-timeout.test.ts" --exclude "**/run-cjs-graceful-fallback.test.ts" --exclude "**/windows-prompt-hook-runner.test.ts" "$@"
    {{PM}} exec vitest run --no-file-parallelism src/__tests__/session-end-process-exit.test.ts src/__tests__/run-cjs-generic-timeout.test.ts src/__tests__/run-cjs-graceful-fallback.test.ts src/__tests__/windows-prompt-hook-runner.test.ts

# Only run tests for files changed since last commit (vitest --changed)
[group('test')]
test-changed:
    {{PM}} exec vitest run --changed

# Run tests in files matching a glob pattern (use 'tf <glob>')
[group('test')]
test-file pattern:
    {{PM}} exec vitest run "{{pattern}}"

# Run tests whose test name matches a substring (vitest -t)
[group('test')]
test-filter pattern:
    {{PM}} exec vitest run -t "{{pattern}}"

# Run vitest with the interactive UI
[group('test')]
test-ui:
    {{PM}} run test:ui

# Run vitest with coverage report
[group('test')]
test-coverage:
    {{PM}} run test:coverage

# Open the HTML coverage report (run test-coverage first)
[group('test')]
coverage-open:
    @if [[ -f coverage/index.html ]]; then open coverage/index.html 2>/dev/null || xdg-open coverage/index.html 2>/dev/null || echo "open coverage/index.html manually"; else echo "no coverage/index.html -- run 'just test-coverage' first"; fi

# Verify omc interop: targeted tests + interop tool registration in built bridge
[group('test')]
interop-verify:
    #!/usr/bin/env bash
    set -euo pipefail
    pnpm exec vitest run src/__tests__/cli-interop-flags.test.ts src/mcp/__tests__/standalone-listtools.test.ts src/interop
    [[ -f bridge/mcp-server.cjs ]] || { echo "bridge/mcp-server.cjs missing -- run 'just build' first"; exit 1; }
    count=$({ printf '%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"interop-verify","version":"0"}}}' \
      '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
      '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'; sleep 3; } \
      | OMC_INTEROP_TOOLS_ENABLED=1 node bridge/mcp-server.cjs 2>/dev/null \
      | jq -r 'select(.id==2) | [.result.tools[].name | select(startswith("interop_"))] | length')
    [[ "$count" == "8" ]] && echo "interop-verify OK: 8 interop tools registered" || { echo "interop-verify FAIL: expected 8 interop tools, got ${count:-0}"; exit 1; }

# --- Benchmark ---

# Run all prompt benchmarks
[group('bench')]
bench:
    {{PM}} run bench:prompts

# Capture a new benchmark baseline
[group('bench')]
bench-save:
    {{PM}} run bench:prompts:save

# Compare current benchmarks to saved baseline
[group('bench')]
bench-compare:
    {{PM}} run bench:prompts:compare

# --- Lint & Format ---

# Run eslint over src
[group('lint')]
lint:
    {{PM}} run lint

# Run eslint with auto-fix
[group('lint')]
lint-fix:
    {{PM}} exec eslint src --fix

# Apply prettier formatting
[group('lint')]
fmt:
    {{PM}} run format

# Apply all auto-fixes (prettier + eslint --fix)
[group('lint')]
fmt-fix: fmt lint-fix

# Check prettier formatting (CI gate; does not modify files)
[group('lint')]
fmt-check:
    {{PM}} exec prettier --check "src/**/*.ts"

# Lint markdown via rumdl (no-op when rumdl is missing)
[group('lint')]
mdlint:
    @if command -v rumdl >/dev/null 2>&1; then rumdl check --respect-gitignore "./**/*.md"; else echo "rumdl not installed -- skipping (cargo install rumdl-cli)"; fi

# Lint shell (helpers + scripts) via shellcheck (no-op when missing)
[group('lint')]
shell-lint:
    @if ! command -v shellcheck >/dev/null 2>&1; then echo "shellcheck not installed -- skipping (brew install shellcheck)"; exit 0; fi
    shellcheck -x -S warning -P '{{helpers}}' {{helpers}}/*.bash
    @if command -v fd >/dev/null 2>&1; then fd -e sh . scripts -X shellcheck || true; fi

# Check shell formatting of helpers via shfmt (no-op when missing)
[group('lint')]
shell-fmt-check:
    @if command -v shfmt >/dev/null 2>&1; then shfmt -d -i 2 -ci -sr {{helpers}}/*.bash; else echo "shfmt not installed -- skipping (brew install shfmt)"; fi

# Apply shfmt formatting to the helpers
[group('lint')]
shell-fmt:
    @if command -v shfmt >/dev/null 2>&1; then shfmt -w -i 2 -ci -sr {{helpers}}/*.bash; else echo "shfmt not installed -- skipping (brew install shfmt)"; fi

# Spell-check via typos (no-op when typos is missing)
[group('lint')]
typoscheck:
    @if command -v typos >/dev/null 2>&1; then typos; else echo "typos not installed -- skipping (cargo install typos-cli)"; fi

# Find unused exports / dead code (knip if installed; else hint)
[group('lint')]
deadcode:
    @if {{PM}} exec knip --version >/dev/null 2>&1; then {{PM}} exec knip; elif command -v knip >/dev/null 2>&1; then knip; else echo "knip not installed -- {{PM}} add -D knip"; fi

# --- Check & Verify ---

# Audit dependencies for known advisories
[group('verify')]
audit:
    @{{PM}} audit --omit=dev || true

# Lightweight composite check (typecheck + lint + tests)
[group('verify')]
check: typecheck lint test-run

# Faster verify -- skips audit and slow file-type linters
[group('verify')]
verify-fast: fmt-check typecheck lint test-run
    @echo
    @echo "verify-fast: GREEN (skipped audit, mdlint, shell-lint, typoscheck)"

# Full pre-push gate -- run before opening a PR
[group('verify')]
verify: fmt-check typecheck lint test-run mdlint shell-lint shell-fmt-check typoscheck
    @echo
    @echo "---------------------------------------"
    @echo "  verify: ALL GREEN  ✓"
    @echo "---------------------------------------"

# Full CI pipeline (install + build + verify + shipping/generation/sync gates)
[group('verify')]
ci: install build verify plugin-verify prompt-projections-verify inventory-verify sync-metadata-verify sync-contributors-verify
    @echo
    @echo "---------------------------------------"
    @echo "  ci: ALL GREEN  ✓"
    @echo "---------------------------------------"

# --- Documentation ---

# Build composed docs bundle
[group('docs')]
docs:
    {{PM}} run compose-docs

# Open the compiled README in the default markdown viewer
[group('docs')]
docs-open:
    @if [[ -f dist/COMPOSED.md ]]; then "${PAGER:-bat}" dist/COMPOSED.md; else echo "dist/COMPOSED.md not found -- run 'just docs' first"; fi

# Lines of code by language (tokei > scc > fd fallback)
[group('docs')]
loc:
    @if command -v tokei >/dev/null 2>&1; then tokei .; elif command -v scc >/dev/null 2>&1; then scc .; elif command -v fd >/dev/null 2>&1; then fd -e ts -e mjs -e cjs -e js --exclude dist --exclude node_modules -X wc -l | tail -1; else echo "install tokei or scc for a loc report"; fi

# --- Release & Publish ---

# Sync versions across package.json and shipped manifests
[group('release')]
sync-version:
    bash scripts/sync-version.sh

# Sync repo metadata (description, keywords, etc.)
[group('release')]
sync-metadata:
    {{PM}} run sync-metadata

# Verify that metadata is in sync (CI gate)
[group('release')]
sync-metadata-verify:
    {{PM}} run sync-metadata:verify

# Dry-run metadata sync (show diff only)
[group('release')]
sync-metadata-dry-run:
    {{PM}} run sync-metadata:dry-run

# Sync the featured-contributors block in README
[group('release')]
sync-contributors:
    {{PM}} run sync-featured-contributors

# Verify featured-contributors block is fresh (CI gate)
[group('release')]
sync-contributors-verify:
    {{PM}} run sync-featured-contributors:verify

# Verify the plugin shipping surface (CI gate)
[group('release')]
plugin-verify:
    {{PM}} run plugin:shipping:verify

# Check plugin shipping surface for a PR diff
[group('release')]
plugin-check-pr:
    {{PM}} run plugin:shipping:check-pr

# Stage plugin shipping surface changes
[group('release')]
plugin-stage:
    {{PM}} run plugin:shipping:stage

# Cut a release (interactive script)
[group('release')]
release:
    {{PM}} run release

# Pre-publish gate (run as part of pnpm publish)
[group('release')]
prepublish: verify build
    @echo "ready to publish"

# Generate release notes from commits since <ref> (default: last tag)
[group('release')]
release-notes ref='':
    #!/usr/bin/env bash
    set -euo pipefail
    base="{{ref}}"
    if [[ -z "$base" ]]; then
        base=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)
    fi
    echo "changes since $base"
    git log --pretty='- %s (%h)' "$base..HEAD"

# --- Clean ---

# Remove build artifacts (dist + tsbuildinfo)
[group('clean')]
clean:
    rm -rf dist
    rm -f tsconfig.tsbuildinfo
    rm -f shellcheck_output.log scripts/shellcheck_output.log

# Deep clean (also node_modules + lockfile caches)
[group('clean')]
clean-deep: clean
    rm -rf node_modules .pnpm-store
    @echo "(re-install with: just install)"

# Remove only the .omc/cache, keep state and notepad
[group('clean')]
clean-cache:
    rm -rf .omc/cache .fraumeship
    @echo "(state and notepad preserved)"

# Remove the omc local-state caches (cache + state + fraumeship)
[group('clean')]
clean-omc:
    rm -rf .omc/cache .omc/state .fraumeship

# --- Git ---

# Show repo status (short)
[group('git')]
git-status:
    @git status -sb

# Show last 20 commits, oneline
[group('git')]
git-log:
    @git log --oneline -n 20

# Switch git branches via fzf
[no-exit-message]
[group('git')]
git-branch:
    @'{{helpers}}/pick.bash' branch

# Stage everything, commit with message, push
[group('git')]
git-ship message:
    git add -A
    git commit -m "{{message}}"
    git push

# Amend last commit, keeping the existing message
[group('git')]
git-amend:
    git add -A
    git commit --amend --no-edit

# Create a fixup commit pointing at <hash> (for later autosquash rebase)
[group('git')]
git-fixup hash:
    git add -A
    git commit --fixup={{hash}}

# Create a PR via gh (title and body)
[group('git')]
git-pr title body='':
    @if ! command -v gh >/dev/null 2>&1; then echo "gh not installed -- brew install gh"; exit 1; fi
    gh pr create --title "{{title}}" --body "{{body}}"

# Watch CI checks for the current PR (gh pr checks --watch)
[group('git')]
git-pr-checks:
    @if ! command -v gh >/dev/null 2>&1; then echo "gh not installed -- brew install gh"; exit 1; fi
    gh pr checks --watch

# --- OMC ---

# Uninstall all global omc installations (pnpm global remove)
[group('omc')]
omc-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    source ~/scripts/tools/agent-shell-harness/lib/dev-shell-init.sh 2>/dev/null || true
    echo "omc-uninstall: removing global oh-my-claude-sisyphus"
    if pnpm list -g --depth=0 2>/dev/null | rg -q 'oh-my-claude-sisyphus'; then
        pnpm remove -g oh-my-claude-sisyphus
        echo "omc-uninstall: removed"
    else
        echo "omc-uninstall: nothing to remove (not installed globally)"
    fi
    if type -af omc 2>/dev/null | rg -q 'omc'; then
        echo "WARNING: omc still found after uninstall:" >&2
        type -af omc >&2
    else
        echo "omc-uninstall: verified not in PATH"
    fi

# Install omc globally from a packed tarball -- the installed copy is
# self-contained in the pnpm global store and does NOT depend on this repo
# (a dirty/mid-merge checkout can no longer break the omc on PATH).
[group('omc')]
omc-install:
    #!/usr/bin/env bash
    set -euo pipefail
    source ~/scripts/tools/agent-shell-harness/lib/dev-shell-init.sh 2>/dev/null || true
    REPO_DIR="{{justfile_directory()}}"
    echo "omc-install: building in $REPO_DIR"
    pnpm run build
    pack_dir=$(mktemp -d)
    trap 'rm -rf "$pack_dir"' EXIT
    echo "omc-install: packing tarball"
    tarball=$(pnpm pack --pack-destination "$pack_dir" | tail -1)
    [[ -f "$tarball" ]] || { echo "omc-install: pack failed ($tarball)" >&2; exit 1; }
    echo "omc-install: installing $(basename "$tarball") globally (copy, not symlink)"
    pnpm add -g "$tarball"
    echo "omc-install: installed"
    echo "  $(type -af omc 2>/dev/null | head -1)"
    if pnpm list -g --depth=0 --json 2>/dev/null | rg -q '"from":\s*"link:'; then
        echo "WARNING: global install is still a link into a checkout" >&2
        exit 1
    fi
    omc --version 2>/dev/null || echo "(omc --version failed -- check install)" >&2

# DEV ONLY: symlink-install this checkout globally (breaks whenever the repo
# is dirty or mid-merge -- prefer omc-install)
[group('omc')]
omc-link:
    #!/usr/bin/env bash
    set -euo pipefail
    source ~/scripts/tools/agent-shell-harness/lib/dev-shell-init.sh 2>/dev/null || true
    echo "omc-link: LINKING checkout into global pnpm (dev only)"
    pnpm run build
    pnpm add -g "{{justfile_directory()}}"
    echo "omc-link: linked -- installed omc now tracks this repo live"

# Uninstall then reinstall omc from a packed tarball (full cycle)
[group('omc')]
omc-reinstall: omc-uninstall omc-install

# Open .omc/notepad.md in $EDITOR (creates if missing)
[group('omc')]
notepad:
    @mkdir -p .omc
    @[[ -f .omc/notepad.md ]] || printf '# OMC Notepad\n\n' > .omc/notepad.md
    {{EDITOR_CMD}} .omc/notepad.md

# Pretty-print every active mode-state file under .omc/state/
[group('omc')]
state:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d .omc/state ]]; then echo "(no .omc/state directory)"; exit 0; fi
    mapfile -t files < <(fd -e json . .omc/state 2>/dev/null || find .omc/state -type f -name '*.json' 2>/dev/null)
    if (( ${#files[@]} == 0 )); then echo "(no active mode states)"; exit 0; fi
    for f in "${files[@]}"; do
        echo "--- $f ---"
        if command -v jq >/dev/null 2>&1; then jq . "$f"; else cat "$f"; fi
    done

# List every agent definition under agents/ with one-line summaries
[group('omc')]
agents-list:
    #!/usr/bin/env bash
    set -euo pipefail
    fd -e md . agents -E AGENTS.md | sort | while read -r f; do
        name=$(basename "$f" .md)
        desc=$(rg -No '^description:\s*"?(.*?)"?$' --replace '$1' "$f" 2>/dev/null | head -1)
        printf '  %-28s %s\n' "$name" "${desc:-(no description)}"
    done

# List every skill SKILL.md under skills/ with its name + summary
[group('omc')]
skills-list:
    #!/usr/bin/env bash
    set -euo pipefail
    fd SKILL.md skills -t f | sort | while read -r f; do
        name=$(rg -No '^name:\s*(.*)' --replace '$1' "$f" 2>/dev/null | head -1)
        desc=$(rg -No '^description:\s*"?(.*?)"?$' --replace '$1' "$f" 2>/dev/null | head -1 | head -c 80)
        printf '  %-28s %s\n' "${name:-?}" "${desc:-(no description)}"
    done

# Tail the most recent log file under .omc/logs
[group('omc')]
tail-log:
    #!/usr/bin/env bash
    set -euo pipefail
    latest=$(fd -e log . .omc/logs 2>/dev/null | sort | tail -1)
    if [[ -n "$latest" ]]; then echo "tailing $latest"; tail -f "$latest"; else echo "no logs under .omc/logs"; fi

# --- Utilities ---

# fzf-pick a source file and open it in $EDITOR (fd + bat preview)
[no-exit-message]
[group('util')]
pick:
    @'{{helpers}}/pick.bash' file

# fzf-pick a markdown doc and open it in $EDITOR
[no-exit-message]
[group('util')]
edit-doc:
    @'{{helpers}}/pick.bash' doc

# Live-grep across the repo via rg+fzf, open the match in $EDITOR
[no-exit-message]
[group('util')]
search query='':
    @'{{helpers}}/search.bash' "{{query}}"

# Show the body (and resolved values) of a recipe
[group('util')]
show recipe:
    @just --show {{recipe}}
