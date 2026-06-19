# ── oh-my-claudecode Justfile -- TypeScript / Node multi-agent build harness ──
#
# Style (per AGENTS.md "Justfile Style Guide"):
#   - bash strict mode, kebab-case recipes, doc comments, fzf+bat previews
#   - composite recipes chain via dependencies, not shell `&&`
#   - `verify` is the full pre-push gate
#
# Quick start:
#   just                  # show grouped recipe list
#   just info             # tool versions and project status
#   just doctor           # diagnose missing tooling
#   just b / t / v        # build / test / verify aliases
#   just fzf              # interactive recipe picker (just --choose powered)
#   just menu             # curated categorized launcher
#
# Package manager: pnpm only (canonical, declared in
# package.json#packageManager). npm and yarn are not supported.

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false
set positional-arguments := true
set ignore-comments := true

export FORCE_COLOR := "1"
export NODE_OPTIONS := env_var_or_default("NODE_OPTIONS", "--enable-source-maps")

# Single-source-of-truth package manager: pnpm only.
PM := "pnpm"

# Editor for *-edit / pick / search / notepad recipes.
EDITOR_CMD := env_var_or_default("EDITOR", "vim")

# ── Aliases ──────────────────────────────────────────────────────────────────
# One-letter accelerators for the recipes you'll type 100x/day.

alias b   := build
alias bf  := build-fast
alias t   := test
alias tr  := test-run
alias tc  := test-changed
alias tf  := test-file
alias l   := lint
alias lf  := lint-fix
alias ff  := fmt-fix
alias f   := fmt
alias fc  := fmt-check
alias c   := check
alias v   := verify
alias vf  := verify-fast
alias d   := dev
alias df  := dev-full
alias h   := help
alias i   := info
alias doc := doctor
alias n   := notepad
alias p   := pick
alias s   := search
alias gs  := git-status
alias gl  := git-log
alias gb  := git-branch

# ── Meta ─────────────────────────────────────────────────────────────────────

# Default: show grouped recipe list (sorted within each group)
[group('meta')]
help:
    @just --list --list-heading $'oh-my-claudecode -- pick a recipe (group: alpha)\n'

# Print project + tooling versions in one tidy table
[group('meta')]
info: _info-header _info-runtime _info-cli _info-project

[private]
_info-header:
    @printf '── oh-my-claudecode @ %s ──\n' "$(node -p "require('./package.json').version" 2>/dev/null || echo '?')"

[private]
_info-runtime:
    @printf '%-10s %s\n' \
        "node"      "$(node -v 2>/dev/null               || echo '(missing)')" \
        "{{PM}}"    "$({{PM}} -v 2>/dev/null             || echo '(missing)')" \
        "tsc"       "$(pnpm exec tsc --version 2>/dev/null || echo '(not installed)')" \
        "vitest"    "$(pnpm exec vitest --version 2>/dev/null            || echo '(missing)')" \
        "just"      "$(just --version 2>/dev/null        || echo '?')"

[private]
_info-cli:
    @for tool in rg fd bat jq watchexec gh rmux dust rumdl shellcheck typos tokei scc knip; do \
        if command -v $tool >/dev/null 2>&1; then \
            printf '%-10s %s\n' "$tool" "$($tool --version 2>/dev/null | head -1)"; \
        else \
            printf '%-10s %s\n' "$tool" "(not installed)"; \
        fi \
    done

[private]
_info-project:
    @printf '\n── repo ──\n'
    @printf '%-10s %s\n' \
        "branch"    "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')" \
        "head"      "$(git log -1 --pretty='%h %s' 2>/dev/null     || echo '?')" \
        "dirty"     "$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') files modified"

# Diagnose toolchain -- exits non-zero if a required tool is missing
[group('meta')]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    miss=0
    require() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  ✓ %-12s %s\n' "$1" "$($1 --version 2>/dev/null | head -1)"
        else
            printf '  ✗ %-12s MISSING -- %s\n' "$1" "$2"
            miss=$((miss + 1))
        fi
    }
    suggest() {
        if command -v "$1" >/dev/null 2>&1; then
            printf '  ✓ %-12s %s\n' "$1" "$($1 --version 2>/dev/null | head -1)"
        else
            printf '  · %-12s optional -- %s\n' "$1" "$2"
        fi
    }
    echo "── required ──"
    require node "install via nodesource or nvm"
    require {{PM}} "corepack enable && corepack prepare pnpm@latest --activate"
    require git "install via OS package manager"
    echo
    echo "── recommended ──"
    require rg "brew install ripgrep"
    require fd "brew install fd"
    require bat "brew install bat"
    require jq "brew install jq"
    require fzf "brew install fzf"
    require watchexec "brew install watchexec"
    require gh "brew install gh"
    require rmux "install rmux -- drop-in tmux replacement; this project never uses tmux (omc launch spawns rmux)"
    echo
    echo "── optional ──"
    suggest dust "brew install dust  -- for bundle-size"
    suggest rumdl "cargo install rumdl-cli  -- for mdlint"
    suggest shellcheck "brew install shellcheck"
    suggest typos "cargo install typos-cli"
    suggest tokei "brew install tokei  -- for loc"
    suggest scc "brew install scc"
    suggest knip "{{PM}} add -D knip  -- for deadcode"
    echo
    if (( miss > 0 )); then
        printf '\n%d required tool(s) missing.\n' "$miss" >&2
        exit 1
    fi
    echo "doctor: all required tools present ✓"

# Count recipes by group (useful for Justfile gardening)
[group('meta')]
recipes:
    @printf 'recipes: %s\n' "$(just --summary 2>/dev/null | tr ' ' '\n' | rg -c '.')"
    @printf 'groups:  %s\n' "$(just --groups 2>/dev/null | tail -n +2 | rg -c '.')"
    @printf 'aliases: %s\n' "$(rg -c '^alias\s' Justfile 2>/dev/null || echo 0)"
    @echo
    @just --groups | tail -n +2 | rg -o '\S+' | while read -r g; do \
        count=$(just --list 2>/dev/null | awk -v g="$g" \
            'BEGIN{pat="\\[" g "\\]"} $0 ~ pat && NF==1 {f=1;next} /^$/{f=0} f && /^[[:space:]]+[a-z]/{c++} END{print c+0}'); \
        printf '  %-12s %s\n' "$g" "$count recipes"; \
    done

# ── Install ──────────────────────────────────────────────────────────────────

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

# ── Build ────────────────────────────────────────────────────────────────────

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
    pnpm exec tsc

# Type-check without emitting
[group('build')]
typecheck:
    pnpm exec tsc --noEmit

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

# Compose docs into bundled markdown
[group('build')]
compose-docs:
    {{PM}} run compose-docs

# Show bundle sizes (uses dust if installed; falls back to du)
[group('build')]
bundle-size:
    @if [[ ! -d dist ]]; then echo "no dist/ -- run 'just build' first"; exit 0; fi
    @if command -v dust >/dev/null 2>&1; then \
        dust -d 2 dist; \
    else \
        du -sh dist/* 2>/dev/null | sort -rh; \
    fi

# ── Dev ──────────────────────────────────────────────────────────────────────

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
    @if ! command -v watchexec >/dev/null 2>&1; then \
        echo "watchexec not installed -- brew install watchexec"; exit 1; \
    fi
    watchexec --restart --clear --exts ts,mjs,cjs,js,json,md \
              --ignore 'dist/**' --ignore 'node_modules/**' --ignore '.omc/**' \
              -- just '{{recipe}}'

# ── Run ──────────────────────────────────────────────────────────────────────

# Run the compiled binary entry
[group('run')]
run *args:
    @if [[ ! -f dist/index.js ]]; then echo "dist/index.js missing -- running 'just build-fast' first"; just build-fast; fi
    node dist/index.js "$@"

# Run the local CLI shim directly (omc)
[group('run')]
cli *args:
    node bridge/cli.cjs "$@"

# Print the current omc status (smoke test)
[group('run')]
status:
    @node bridge/cli.cjs status 2>/dev/null || echo "(no status yet -- run 'just build' first)"

# Smoke-boot the MCP server -- exits cleanly if it boots, fails loudly otherwise
[group('run')]
mcp-smoke:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f bridge/mcp-server.cjs ]]; then
        echo "bridge/mcp-server.cjs missing -- run 'just build-mcp' first" >&2
        exit 1
    fi
    # MCP servers speak JSON-RPC over stdio; sending nothing and EOF should exit cleanly.
    timeout 3 node bridge/mcp-server.cjs </dev/null >/dev/null 2>&1 \
        && echo "mcp-smoke: MCP server boots ✓" \
        || { code=$?; if (( code == 124 )); then echo "mcp-smoke: server is alive (timed out as expected)"; else echo "mcp-smoke: server failed to boot (exit $code)" >&2; exit 1; fi; }

# ── Test ─────────────────────────────────────────────────────────────────────

# Run vitest in watch mode (default test runner)
[group('test')]
test *args:
    {{PM}} test "$@"

# Run the full vitest suite once (CI mode)
[group('test')]
test-run *args:
    {{PM}} run test:run -- "$@"

# Only run tests for files changed since last commit (vitest --changed)
[group('test')]
test-changed:
    pnpm exec vitest run --changed

# Run tests in files matching a glob pattern (use 'tf <glob>')
[group('test')]
test-file pattern:
    pnpm exec vitest run "{{pattern}}"

# Run tests whose test name matches a substring (vitest -t)
[group('test')]
test-filter pattern:
    pnpm exec vitest run -t "{{pattern}}"

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
    @if [[ -f coverage/index.html ]]; then \
        open coverage/index.html 2>/dev/null || xdg-open coverage/index.html 2>/dev/null || echo "open coverage/index.html manually"; \
    else \
        echo "no coverage/index.html -- run 'just test-coverage' first"; \
    fi

# ── Benchmark ────────────────────────────────────────────────────────────────

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

# ── Lint & Format ────────────────────────────────────────────────────────────

# Run eslint over src
[group('lint')]
lint:
    {{PM}} run lint

# Run eslint with auto-fix
[group('lint')]
lint-fix:
    pnpm exec eslint src --fix

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
    pnpm exec prettier --check "src/**/*.ts"

# Lint markdown via rumdl (no-op when rumdl is missing)
[group('lint')]
mdlint:
    @if command -v rumdl >/dev/null 2>&1; then \
        rumdl check --respect-gitignore "**/*.md"; \
    else \
        echo "rumdl not installed -- skipping (cargo install rumdl-cli)"; \
    fi

# Run shellcheck on every .sh under scripts/ (uses fd to enumerate)
[group('lint')]
shellcheck:
    @if ! command -v shellcheck >/dev/null 2>&1; then \
        echo "shellcheck not installed -- skipping"; exit 0; \
    fi
    @if command -v fd >/dev/null 2>&1; then \
        fd -e sh . scripts -X shellcheck; \
    else \
        find scripts -type f -name '*.sh' -print0 | xargs -0 -r shellcheck; \
    fi

# Spell-check via typos (no-op when typos is missing)
[group('lint')]
typoscheck:
    @if command -v typos >/dev/null 2>&1; then \
        typos; \
    else \
        echo "typos not installed -- skipping (cargo install typos-cli)"; \
    fi

# Find unused exports / dead code (knip if installed; else hint)
[group('lint')]
deadcode:
    @if pnpm exec knip --version >/dev/null 2>&1; then \
        pnpm exec knip; \
    elif command -v knip >/dev/null 2>&1; then \
        knip; \
    else \
        echo "knip not installed -- {{PM}} add -D knip"; \
    fi

# ── Check & Verify ───────────────────────────────────────────────────────────

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
    @echo "── verify-fast: GREEN ✓ (skipped audit, mdlint, shellcheck, typoscheck)"

# Full pre-push gate -- run before opening a PR
[group('verify')]
verify: fmt-check typecheck lint test-run mdlint shellcheck typoscheck
    @echo
    @echo "═══════════════════════════════════════"
    @echo "  verify: ALL GREEN  ✓"
    @echo "═══════════════════════════════════════"

# Full CI pipeline (install + build + verify + sync gates)
[group('verify')]
ci: install build verify sync-metadata-verify sync-contributors-verify
    @echo
    @echo "═══════════════════════════════════════"
    @echo "  ci: ALL GREEN  ✓"
    @echo "═══════════════════════════════════════"

# ── Documentation ────────────────────────────────────────────────────────────

# Build composed docs bundle
[group('docs')]
docs:
    {{PM}} run compose-docs

# Open the compiled README in the default markdown viewer
[group('docs')]
docs-open:
    @if [[ -f dist/COMPOSED.md ]]; then \
        "${PAGER:-bat}" dist/COMPOSED.md; \
    else \
        echo "dist/COMPOSED.md not found -- run 'just docs' first"; \
    fi

# Lines of code by language (tokei > scc > wc fallback)
[group('docs')]
loc:
    @if command -v tokei >/dev/null 2>&1; then tokei .; \
    elif command -v scc >/dev/null 2>&1; then scc .; \
    else \
        echo "tokei/scc not installed -- crude fallback:"; \
        if command -v fd >/dev/null 2>&1; then \
            fd -e ts -e mjs -e cjs -e js --exclude dist --exclude node_modules -X wc -l | tail -1; \
        else \
            find . -type f \( -name '*.ts' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.js' \) -not -path './node_modules/*' -not -path './dist/*' -exec wc -l {} + | tail -1; \
        fi \
    fi

# ── Release & Publish ────────────────────────────────────────────────────────

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
    echo "── changes since $base ──"
    git log --pretty='- %s (%h)' "$base..HEAD"

# ── Clean ────────────────────────────────────────────────────────────────────

# Remove build artifacts (dist + tsbuildinfo)
[group('clean')]
clean:
    rm -rf dist
    rm -f tsconfig.tsbuildinfo
    rm -f shellcheck_output.log

# Deep clean (also node_modules + lockfile caches)
[group('clean')]
clean-deep: clean
    rm -rf node_modules .pnpm-store
    @echo "(re-install with: just install)"

# Remove only the .omc/cache, keep state and notepad
[group('clean')]
clean-cache:
    rm -rf .omc/cache .clawhip
    @echo "(state and notepad preserved)"

# Remove the omc local-state caches (cache + state + clawhip)
[group('clean')]
clean-omc:
    rm -rf .omc/cache .omc/state .clawhip

# ── Git ──────────────────────────────────────────────────────────────────────

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
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git branch --all --color=never | sed 's/^..//' | \
        fzf --preview "git log --oneline --color=always {} | head -50" || true)
    [[ -z "${branch:-}" ]] && exit 0
    git switch "$(echo "$branch" | sed 's@remotes/origin/@@')"

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

# ── OMC Install / Uninstall ──────────────────────────────────────────────────

# Uninstall all global omc installations (pnpm global remove)
[group('omc')]
omc-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    source ~/.config/sh/fnm-init.sh 2>/dev/null || true
    echo "── omc-uninstall: removing global oh-my-claude-sisyphus ──"
    if pnpm list -g --depth=0 2>/dev/null | rg -q 'oh-my-claude-sisyphus'; then
        pnpm remove -g oh-my-claude-sisyphus
        echo "omc-uninstall: removed ✓"
    else
        echo "omc-uninstall: nothing to remove (not installed globally)"
    fi
    if type -af omc 2>/dev/null | rg -q 'omc'; then
        echo "WARNING: omc still found after uninstall:" >&2
        type -af omc >&2
    else
        echo "omc-uninstall: verified not in PATH ✓"
    fi

# Install omc from this local checkout (pnpm add -g <abs-path>)
[group('omc')]
omc-install:
    #!/usr/bin/env bash
    set -euo pipefail
    source ~/.config/sh/fnm-init.sh 2>/dev/null || true
    REPO_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")")" && pwd)"
    echo "── omc-install: installing from $REPO_DIR ──"
    pnpm add -g "$REPO_DIR"
    echo "omc-install: installed ✓"
    echo "  $(type -af omc 2>/dev/null | head -1)"

# Uninstall then reinstall omc from this local checkout (full cycle)
[group('omc')]
omc-reinstall: omc-uninstall omc-install

# ── OMC Project-Specific ─────────────────────────────────────────────────────

# Open .omc/notepad.md in $EDITOR (creates if missing)
[group('omc')]
notepad:
    @mkdir -p .omc
    @[[ -f .omc/notepad.md ]] || printf '# OMC Notepad\n\n' > .omc/notepad.md
    {{EDITOR_CMD}} .omc/notepad.md

# Pretty-print every active mode-state file under .omc/state/
[group('omc')]
state:
    @if [[ ! -d .omc/state ]]; then echo "(no .omc/state directory)"; exit 0; fi
    @if command -v fd >/dev/null 2>&1; then \
        files=$(fd -e json . .omc/state 2>/dev/null); \
    else \
        files=$(find .omc/state -type f -name '*.json' 2>/dev/null); \
    fi; \
    if [[ -z "$files" ]]; then echo "(no active mode states)"; exit 0; fi; \
    for f in $files; do \
        echo "── $f ──"; \
        if command -v jq >/dev/null 2>&1; then jq . "$f"; else cat "$f"; fi; \
    done

# List every agent definition under agents/ with one-line summaries
[group('omc')]
agents-list:
    @if command -v fd >/dev/null 2>&1; then \
        fd -e md . agents -E AGENTS.md | sort | while read -r f; do \
            name=$(basename "$f" .md); \
            desc=$(rg -No '^description:\s*"?(.*?)"?$' --replace '$1' "$f" 2>/dev/null | head -1); \
            printf '  %-28s %s\n' "$name" "${desc:-(no description)}"; \
        done \
    else \
        find agents -name '*.md' -not -name 'AGENTS.md' -print | sort; \
    fi

# List every skill SKILL.md under skills/ with its name + summary
[group('omc')]
skills-list:
    @if command -v fd >/dev/null 2>&1; then \
        fd SKILL.md skills -t f | sort | while read -r f; do \
            name=$(rg -No '^name:\s*(.*)' --replace '$1' "$f" 2>/dev/null | head -1); \
            desc=$(rg -No '^description:\s*"?(.*?)"?$' --replace '$1' "$f" 2>/dev/null | head -1 | head -c 80); \
            printf '  %-28s %s\n' "${name:-?}" "${desc:-(no description)}"; \
        done \
    else \
        find skills -name 'SKILL.md' | sort; \
    fi

# Tail the most recent log file under .omc/logs
[group('omc')]
tail-log:
    @if command -v fd >/dev/null 2>&1; then \
        latest=$(fd -e log . .omc/logs 2>/dev/null | sort | tail -1); \
    else \
        latest=$(find .omc/logs -type f -name '*.log' 2>/dev/null | sort | tail -1); \
    fi; \
    if [[ -n "$latest" ]]; then \
        echo "tailing $latest"; \
        tail -f "$latest"; \
    else \
        echo "no logs under .omc/logs"; \
    fi

# ── Utilities ────────────────────────────────────────────────────────────────

# fzf-pick a source file and open it in $EDITOR (uses fd, bat preview)
[no-exit-message]
[group('util')]
pick:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(fd -e ts -e mjs -e cjs -e js -e json -e md -e toml -e yml -e yaml \
        --exclude node_modules --exclude dist --exclude .git \
        | fzf --preview "bat --color=always --style=numbers --line-range=:500 {}" || true)
    [[ -z "${file:-}" ]] && exit 0
    {{EDITOR_CMD}} "$file"

# Live-grep across the repo via fzf+rg, open match in $EDITOR
[no-exit-message]
[group('util')]
search query='':
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
    {{EDITOR_CMD}} "+${lno}" "$file"

# Edit any markdown doc via fzf
[no-exit-message]
[group('util')]
edit-doc:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(fd -e md --exclude node_modules --exclude dist \
        | fzf --preview "bat --color=always --style=numbers --line-range=:500 {}" || true)
    [[ -z "${file:-}" ]] && exit 0
    {{EDITOR_CMD}} "$file"

# Show resolved value of a Justfile variable / show recipe body
[group('util')]
show recipe:
    @just --show {{recipe}}

# ── fzf Workflows ────────────────────────────────────────────────────────────

# Auto-generated fzf picker -- uses `just --choose` so new recipes appear automatically
[no-exit-message]
[group('fzf')]
fzf:
    @just --choose --chooser "fzf --header='oh-my-claudecode -- pick a recipe' \
        --preview 'just --show {} 2>/dev/null'"

# Curated, categorized launcher (the entry point of last resort)
[no-exit-message]
[group('fzf')]
menu:
    #!/usr/bin/env bash
    set -euo pipefail
    choice=$(printf '%s\n' \
        '── INSTALL ──' \
        '* install                 -- pnpm install' \
        '  outdated                -- show outdated deps' \
        '  update                  -- interactive deps update' \
        '── BUILD ──' \
        '* build                   -- full build (TS + bundles + docs)' \
        '* build-fast              -- tsc only (incremental)' \
        '  build-cli               -- bundle cli' \
        '  build-mcp               -- bundle mcp server' \
        '  build-bridge            -- bundle skill bridge' \
        '  bundle-size             -- du-style report on dist/' \
        '  compose-docs            -- compose docs into one bundle' \
        '── DEV ──' \
        '* dev                     -- tsc --watch' \
        '  dev-full                -- all watchers concurrently' \
        '  watch                   -- rerun any recipe on change' \
        '── RUN ──' \
        '  run                     -- node dist/index.js' \
        '  cli                     -- bridge/cli.cjs' \
        '  status                  -- omc status smoke test' \
        '  mcp-smoke               -- mcp server boot smoke test' \
        '── TEST ──' \
        '* test                    -- vitest watch' \
        '* test-run                -- vitest run (CI)' \
        '* test-changed            -- only files changed since last commit' \
        '  test-file <glob>        -- file-glob filter' \
        '  test-filter <name>      -- test-name filter' \
        '  test-coverage           -- vitest run --coverage' \
        '  coverage-open           -- open html report' \
        '  test-ui                 -- vitest UI' \
        '── BENCH ──' \
        '  bench                   -- run prompt benchmarks' \
        '  bench-save              -- save baseline' \
        '  bench-compare           -- compare to baseline' \
        '── LINT & FORMAT ──' \
        '* lint                    -- eslint src' \
        '* fmt                     -- prettier write' \
        '* fmt-fix                 -- prettier + eslint --fix' \
        '  lint-fix                -- eslint --fix' \
        '  fmt-check               -- prettier check' \
        '  typecheck               -- tsc --noEmit' \
        '  mdlint                  -- rumdl check' \
        '  shellcheck              -- shellcheck scripts/' \
        '  typoscheck              -- typos' \
        '  deadcode                -- knip / unused exports' \
        '── VERIFY ──' \
        '* verify                  -- full pre-push gate' \
        '* verify-fast             -- skip slow file-type linters' \
        '* ci                      -- full CI pipeline' \
        '  check                   -- typecheck + lint + test-run' \
        '  audit                   -- dependency audit' \
        '── DOCS ──' \
        '  docs                    -- build composed docs' \
        '  docs-open               -- view dist/COMPOSED.md' \
        '  loc                     -- lines of code report' \
        '── RELEASE ──' \
        '  release                 -- interactive release' \
        '  release-notes <ref>     -- generate notes from git log' \
        '  sync-version            -- sync versions' \
        '  sync-metadata           -- sync metadata' \
        '  sync-contributors       -- sync contributor list' \
        '  prepublish              -- verify + build' \
        '── CLEAN ──' \
        '  clean                   -- rm dist' \
        '  clean-cache             -- rm .omc/cache only' \
        '  clean-deep              -- + node_modules' \
        '  clean-omc               -- rm .omc/{cache,state} .clawhip' \
        '── GIT ──' \
        '  git-status              -- short status' \
        '  git-log                 -- last 20 commits' \
        '  git-branch              -- fzf branch switch' \
        '  git-ship <msg>          -- add+commit+push' \
        '  git-amend               -- amend last commit' \
        '  git-fixup <hash>        -- fixup commit' \
        '  git-pr <title> [body]   -- gh pr create' \
        '  git-pr-checks           -- gh pr checks --watch' \
        '── OMC ──' \
        '* omc-reinstall           -- uninstall + reinstall from local repo' \
        '  omc-uninstall           -- remove all global omc installs' \
        '  omc-install             -- install omc from this local checkout' \
        '* notepad                 -- open .omc/notepad.md' \
        '  state                   -- show .omc/state/*.json' \
        '  agents-list             -- list agent definitions' \
        '  skills-list             -- list skill SKILL.md files' \
        '  tail-log                -- tail latest .omc log' \
        '── UTIL ──' \
        '  pick                    -- fzf-pick a file' \
        '  search <q>              -- live-grep' \
        '  edit-doc                -- fzf-pick a markdown doc' \
        '  show <recipe>           -- show recipe body' \
        '  info                    -- versions' \
        '  doctor                  -- diagnose toolchain' \
        '  recipes                 -- recipe count' \
        | fzf --preview='just --show "$(echo {} | tr -d "*" | awk "{print \$1}")" 2>/dev/null || echo "(section header)"' \
              --header='oh-my-claudecode -- pick a recipe' || true)
    [[ -z "${choice:-}" ]] && exit 0
    recipe=$(echo "$choice" | tr -d '*' | awk '{print $1}')
    [[ -z "${recipe:-}" || "${recipe:-}" == "──" ]] && exit 0
    just "$recipe"

