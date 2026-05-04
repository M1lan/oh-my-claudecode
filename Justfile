# ── oh-my-claudecode Justfile -- TypeScript / Node multi-agent build harness ──
#
# Style follows the project AGENTS.md "Justfile Style Guide":
#   - bash strict mode
#   - kebab-case recipe names
#   - section headers with box-drawing comments
#   - doc comments above every recipe
#   - `verify` is the full pre-push gate
#   - fzf interactive menu uses `bat` previews
#
# Package manager: detected from env. Defaults to `pnpm` (pnpm-lock.yaml
# is canonical here). Override with `PM=npm just <recipe>` when desired.

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

export FORCE_COLOR := "1"
export NODE_OPTIONS := env_var_or_default("NODE_OPTIONS", "--enable-source-maps")

# Package manager (pnpm | npm). Detected once, used everywhere.
PM := env_var_or_default("PM", "pnpm")

# ── Meta ──

# Default: show all recipes
help:
    @just --list --unsorted

# Print project + tooling versions
info:
    @echo "── oh-my-claudecode ──"
    @node -v 2>/dev/null    | sed 's/^/node    /' || echo "node    (missing)"
    @{{PM}} -v 2>/dev/null  | sed "s/^/{{PM}}     /" || echo "{{PM}}     (missing)"
    @tsc --version 2>/dev/null    | sed 's/^/tsc     /' || echo "tsc     (via npx)"
    @just --version 2>/dev/null   | sed 's/^/just    /'
    @command -v rg && rg --version | head -1 | sed 's/^/rg      /'
    @command -v fd && fd --version       | sed 's/^/fd      /'
    @command -v bat && bat --version | head -1 | sed 's/^/bat     /'
    @command -v jq  && jq --version       | sed 's/^/jq      /'
    @command -v rumdl     >/dev/null && echo "rumdl   $(rumdl --version 2>/dev/null || echo '?')" || echo "rumdl   (not installed)"
    @command -v shellcheck >/dev/null && echo "shellc  $(shellcheck --version | sed -n 's/^version: //p')" || echo "shellc  (not installed)"

# Install dependencies (clean, reproducible from lockfile)
install:
    {{PM}} install --frozen-lockfile || {{PM}} install

# ── Build ──

# Full build (TS + all bridge bundles + composed docs)
build:
    {{PM}} run build

# Compile TypeScript only (no bundling, no doc compose)
build-ts:
    npx tsc

# Type-check without emitting
typecheck:
    npx tsc --noEmit

# Build the unified CLI bundle
build-cli:
    {{PM}} run build:cli

# Build the MCP server bundle
build-mcp:
    node scripts/build-mcp-server.mjs

# Build the skill bridge bundle
build-bridge:
    {{PM}} run build:bridge

# Build the bridge entry bundle
build-bridge-entry:
    {{PM}} run build:bridge-entry

# Build the runtime CLI bundle
build-runtime-cli:
    {{PM}} run build:runtime-cli

# Build the team MCP server bundle
build-team-server:
    {{PM}} run build:team-server

# Compose docs into bundled markdown
compose-docs:
    {{PM}} run compose-docs

# ── Dev ──

# Watch TypeScript compilation
dev:
    {{PM}} run dev

# Run all watchers concurrently (tsc + every bundler)
dev-full:
    {{PM}} run dev:full

# ── Run ──

# Run the compiled binary entry
run *args:
    node dist/index.js {{args}}

# Run the local CLI shim directly (omc)
cli *args:
    node bridge/cli.cjs {{args}}

# Print the current omc status (smoke test)
status:
    @node bridge/cli.cjs status 2>/dev/null || echo "(no status yet — run 'just build' first)"

# ── Test ──

# Run vitest in watch mode (default test runner)
test:
    {{PM}} test

# Run the full vitest suite once (CI mode)
test-run:
    {{PM}} run test:run

# Run vitest with the interactive UI
test-ui:
    {{PM}} run test:ui

# Run vitest with coverage report
test-coverage:
    {{PM}} run test:coverage

# Run a subset of tests by filter substring
test-filter pattern:
    npx vitest run -t "{{pattern}}"

# ── Benchmark ──

# Run all prompt benchmarks
bench:
    {{PM}} run bench:prompts

# Capture a new benchmark baseline
bench-save:
    {{PM}} run bench:prompts:save

# Compare current benchmarks to saved baseline
bench-compare:
    {{PM}} run bench:prompts:compare

# ── Lint & Format ──

# Run eslint over src
lint:
    {{PM}} run lint

# Run eslint with auto-fix
lint-fix:
    npx eslint src --fix

# Apply prettier formatting
fmt:
    {{PM}} run format

# Check prettier formatting (CI gate; does not modify files)
fmt-check:
    npx prettier --check "src/**/*.ts"

# Lint markdown via rumdl (no-op when rumdl is missing)
mdlint:
    @if command -v rumdl >/dev/null 2>&1; then \
        rumdl check --respect-gitignore "**/*.md"; \
    else \
        echo "rumdl not installed -- skipping (cargo install rumdl-cli)"; \
    fi

# Run shellcheck on every .sh under scripts/
shellcheck:
    @if command -v shellcheck >/dev/null 2>&1; then \
        shopt -s globstar nullglob; \
        files=(scripts/**/*.sh); \
        if (( ${#files[@]} > 0 )); then \
            shellcheck "${files[@]}"; \
        else \
            echo "(no .sh files under scripts/)"; \
        fi; \
    else \
        echo "shellcheck not installed -- skipping"; \
    fi

# Lint TOML files (typos.toml, .clawhip configs, etc.)
typoscheck:
    @if command -v typos >/dev/null 2>&1; then \
        typos; \
    else \
        echo "typos not installed -- skipping (cargo install typos-cli)"; \
    fi

# ── Check & Verify ──

# Audit dependencies for known advisories
audit:
    @{{PM}} audit --omit=dev || true

# Lightweight composite check (typecheck + lint + tests)
check: typecheck lint test-run

# Full pre-push gate -- run before opening a PR
verify: fmt-check lint typecheck test-run mdlint shellcheck typoscheck
    @echo
    @echo "═══════════════════════════════════════"
    @echo "  verify: ALL GREEN  ✓"
    @echo "═══════════════════════════════════════"

# Full CI pipeline (install + build + verify + sync gates)
ci: install build verify sync-metadata-verify sync-contributors-verify
    @echo
    @echo "═══════════════════════════════════════"
    @echo "  ci: ALL GREEN  ✓"
    @echo "═══════════════════════════════════════"

# ── Documentation ──

# Build composed docs bundle
docs:
    {{PM}} run compose-docs

# Open the compiled README in the default markdown viewer
docs-open:
    @if [[ -f dist/COMPOSED.md ]]; then \
        "${PAGER:-bat}" dist/COMPOSED.md; \
    else \
        echo "dist/COMPOSED.md not found -- run 'just docs' first"; \
    fi

# ── Release & Publish ──

# Sync versions across package.json and shipped manifests
sync-version:
    bash scripts/sync-version.sh

# Sync repo metadata (description, keywords, etc.)
sync-metadata:
    {{PM}} run sync-metadata

# Verify that metadata is in sync (CI gate)
sync-metadata-verify:
    {{PM}} run sync-metadata:verify

# Dry-run metadata sync (show diff only)
sync-metadata-dry-run:
    {{PM}} run sync-metadata:dry-run

# Sync the featured-contributors block in README
sync-contributors:
    {{PM}} run sync-featured-contributors

# Verify featured-contributors block is fresh (CI gate)
sync-contributors-verify:
    {{PM}} run sync-featured-contributors:verify

# Cut a release (interactive script)
release:
    {{PM}} run release

# Pre-publish gate (run as part of npm publish)
prepublish: verify build
    @echo "ready to publish"

# ── Clean ──

# Remove build artifacts (dist + tsbuildinfo)
clean:
    rm -rf dist
    rm -f tsconfig.tsbuildinfo
    rm -f shellcheck_output.log

# Deep clean (also node_modules + lockfile caches)
clean-deep: clean
    rm -rf node_modules .pnpm-store
    @echo "(re-install with: just install)"

# Remove the omc local-state caches
clean-omc:
    rm -rf .omc/cache .omc/state .clawhip

# ── Git ──

# Show repo status
git-status:
    @git status -sb

# Show last 20 commits, oneline
git-log:
    @git log --oneline -n 20

# Switch git branches via fzf
[no-exit-message]
git-branch:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git branch --all --color=never | sed 's/^..//' | \
        fzf --preview "git log --oneline --color=always {} | head -50" || true)
    [[ -z "${branch:-}" ]] && exit 0
    git switch "$(echo "$branch" | sed 's@remotes/origin/@@')"

# Stage everything, commit with message, push
git-ship message:
    git add -A
    git commit -m "{{message}}"
    git push

# ── Utilities ──

# fzf-pick a source file and open it in $EDITOR
[no-exit-message]
pick:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(fd -e ts -e mjs -e cjs -e js -e json -e md -e toml -e yml -e yaml \
        --exclude node_modules --exclude dist --exclude .git \
        | fzf --preview "bat --color=always --style=numbers --line-range=:500 {}" || true)
    [[ -z "${file:-}" ]] && exit 0
    "${EDITOR:-vim}" "$file"

# Live-grep across the repo via fzf+rg, open match in $EDITOR
[no-exit-message]
search query="":
    #!/usr/bin/env bash
    set -euo pipefail
    line=$(rg --line-number --no-heading --color=never \
              --glob '!node_modules' --glob '!dist' --glob '!.git' \
              "{{query}}" 2>/dev/null \
        | fzf --delimiter=':' \
              --preview "bat --color=always --style=numbers --highlight-line {2} {1}" \
              --preview-window=right:60% || true)
    [[ -z "${line:-}" ]] && exit 0
    file=$(echo "$line" | cut -d: -f1)
    lno=$(echo  "$line" | cut -d: -f2)
    "${EDITOR:-vim}" "+${lno}" "$file"

# Edit any markdown doc via fzf
[no-exit-message]
edit-doc:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(fd -e md --exclude node_modules --exclude dist \
        | fzf --preview "bat --color=always --style=numbers --line-range=:500 {}" || true)
    [[ -z "${file:-}" ]] && exit 0
    "${EDITOR:-vim}" "$file"

# Tail the most recent log file under .omc/logs
tail-log:
    @latest=$(fd -e log . .omc/logs 2>/dev/null | sort | tail -1); \
    if [[ -n "$latest" ]]; then \
        echo "tailing $latest"; \
        tail -f "$latest"; \
    else \
        echo "no logs under .omc/logs"; \
    fi

# ── fzf Workflows ──

# Categorized interactive recipe menu (the entry point of last resort)
[no-exit-message]
fzf:
    #!/usr/bin/env bash
    set -euo pipefail
    choice=$(printf '%s\n' \
        '── INSTALL ──' \
        '* install                 -- pnpm install' \
        '── BUILD ──' \
        '* build                   -- full build (TS + bundles + docs)' \
        '  build-ts                -- tsc only' \
        '  build-cli               -- bundle cli' \
        '  build-mcp               -- bundle mcp server' \
        '  build-bridge            -- bundle skill bridge' \
        '  build-runtime-cli       -- bundle runtime cli' \
        '  build-team-server       -- bundle team mcp server' \
        '  compose-docs            -- compose docs into one bundle' \
        '── DEV ──' \
        '* dev                     -- tsc --watch' \
        '  dev-full                -- all watchers concurrently' \
        '── RUN ──' \
        '  run                     -- node dist/index.js' \
        '  cli                     -- bridge/cli.cjs' \
        '  status                  -- omc status smoke test' \
        '── TEST ──' \
        '* test                    -- vitest watch' \
        '* test-run                -- vitest run (CI)' \
        '  test-coverage           -- vitest run --coverage' \
        '  test-ui                 -- vitest UI' \
        '  test-filter <pat>       -- single-test filter' \
        '── BENCH ──' \
        '  bench                   -- run prompt benchmarks' \
        '  bench-save              -- save baseline' \
        '  bench-compare           -- compare to baseline' \
        '── LINT & FORMAT ──' \
        '* lint                    -- eslint src' \
        '* fmt                     -- prettier write' \
        '  fmt-check               -- prettier check' \
        '  typecheck               -- tsc --noEmit' \
        '  mdlint                  -- rumdl check' \
        '  shellcheck              -- shellcheck scripts/' \
        '  typoscheck              -- typos' \
        '── VERIFY ──' \
        '* verify                  -- full pre-push gate' \
        '* ci                      -- full CI pipeline' \
        '  check                   -- typecheck + lint + test-run' \
        '  audit                   -- dependency audit' \
        '── DOCS ──' \
        '  docs                    -- build composed docs' \
        '  docs-open               -- view dist/COMPOSED.md' \
        '── RELEASE ──' \
        '  release                 -- interactive release' \
        '  sync-version            -- sync versions' \
        '  sync-metadata           -- sync metadata' \
        '  sync-contributors       -- sync contributor list' \
        '  prepublish              -- verify + build' \
        '── CLEAN ──' \
        '  clean                   -- rm dist' \
        '  clean-deep              -- + node_modules' \
        '  clean-omc               -- rm .omc/cache .clawhip' \
        '── GIT ──' \
        '  git-status              -- short status' \
        '  git-log                 -- last 20 commits' \
        '  git-branch              -- fzf branch switch' \
        '  git-ship <msg>          -- add+commit+push' \
        '── UTIL ──' \
        '  pick                    -- fzf-pick a file' \
        '  search <q>              -- live-grep' \
        '  edit-doc                -- fzf-pick a markdown doc' \
        '  tail-log                -- tail latest .omc log' \
        '  info                    -- versions' \
        | fzf --preview='just --show {2} 2>/dev/null || echo "(section header)"' \
              --header='oh-my-claudecode -- pick a recipe' || true)
    [[ -z "${choice:-}" ]] && exit 0
    recipe=$(echo "$choice" | awk '{print $2}')
    [[ -z "${recipe:-}" || "${recipe:-}" == "──" ]] && exit 0
    just "$recipe"
