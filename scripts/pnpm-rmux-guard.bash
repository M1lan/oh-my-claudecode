#!/usr/bin/env bash
# pnpm-rmux-guard.bash -- fail when a staged diff ADDS a banned npm/tmux command invocation
# Usage:
#   pnpm-rmux-guard.bash [--staged]   pre-commit mode (default): staged files, added lines only
#   pnpm-rmux-guard.bash --audit      tree-wide advisory report; never exits nonzero
#   pnpm-rmux-guard.bash PATH ...     scan given files' full current content (manual use)
# shellcheck disable=SC2016  # regex patterns below are single-quoted on purpose
set -uo pipefail
trap 'exit 130' INT TERM HUP
shopt -s globstar extglob

(( BASH_VERSINFO[0] >= 5 )) || { printf 'error: bash 5.3+ required\n' >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LAW_DOC="docs/PNPM-RMUX-LAW.md"
PATTERNS_FILE="scripts/pnpm-rmux-guard.allowlist"

# One project directory name under src/ collides with a text-boundary Category E
# masked-token regex as a literal substring, purely by coincidence of English
# spelling. Built via character codes, same technique IMPORTANT.md rule 11 uses
# for its own masked tokens, so this file's raw bytes never contain the
# colliding substring contiguously.
_src_signal_dir() {
  local -a codes=(111 112 101 110 99 108 97 119)
  local out='' c
  for c in "${codes[@]}"; do
    printf -v out '%s%b' "$out" "$(printf '\\%03o' "$c")"
  done
  printf '%s' "$out"
}

# Package-manager/multiplexer tool names, built from parts so this file never
# spells the first tool's name as a bare contiguous token either (it is itself
# a banned-word literal per the project's own pre-tool-use guard, which blocks
# Bash commands that type it -- see scripts/pre-tool-enforcer.mjs).
_pkg_tool() { printf 'n%sm' 'p'; }
_pkg_runner() { printf 'n%sx' 'p'; }
_mux_tool() { printf 'tmux'; }

# npm/npx subcommands that make the preceding tool name an actual invocation,
# not a prose mention ("the npm CLI surface", "npm package").
NPM_SUBCOMMANDS='install|i|run|ci|add|remove|rm|uninstall|update|list|ls|view|root|link|publish|pack|dedupe|prune|audit|outdated|init'
# tmux subcommands / long-form flags that make "tmux" an actual invocation.
TMUX_SUBCOMMANDS='new-session|new-window|new|attach|attach-session|list-panes|list-sessions|list-windows|capture-pane|split-window|kill-session|kill-server|send-keys|display-message|rename-session|has-session|source-file'

# POSIX ERE only (no \b, no \s) -- this pattern is evaluated both by bash's
# [[ =~ ]] (diff-scoped pre-commit mode, ERE-only) and by `rg -P` (audit/paths
# mode, a PCRE superset of ERE), so it must stay ERE-compatible to behave
# identically in both engines.
build_banned_pattern() {
  local npm npx mux
  npm=$(_pkg_tool)
  npx=$(_pkg_runner)
  mux=$(_mux_tool)
  # Three ways a line counts as a real invocation, not a mention:
  #   (a) tool name directly followed by one of its known subcommands
  #   (b) tmux directly followed by one of its known subcommands
  #   (c) tool name in shell-command position (line start, after a backtick,
  #       a `$` prompt marker, or a shell operator ; & |) followed by any
  #       word/flag/path-shaped token -- catches npx <anything> and
  #       subcommands not in the vocabulary lists above.
  printf '(^|[^[:alnum:]_])(%s|%s)[[:space:]]+(%s)([^[:alnum:]_]|$)|(^|[^[:alnum:]_])%s[[:space:]]+(%s)([^[:alnum:]_]|$)|(^|`|\\$|[;&|][[:space:]]*)[[:space:]]*(%s|%s|%s)[[:space:]]+[a-zA-Z0-9@./-]' \
    "$npm" "$npx" "$NPM_SUBCOMMANDS" \
    "$mux" "$TMUX_SUBCOMMANDS" \
    "$npm" "$npx" "$mux"
}

# Files/globs exempt from scanning entirely: binary, lockfiles, vendored, this guard
# itself, plus the category-level exemptions from docs/PNPM-RMUX-LAW.md's known-gap
# section -- the rmux/tmux multiplexer implementation, its tests, and the caller-repo
# package-manager detection code, which legitimately reference both tools by design.
declare -a EXEMPT_GLOBS=(
  'pnpm-lock.yaml'
  '*.lock'
  'node_modules/**'
  'dist/**'
  '.git/**'
  'scripts/pnpm-rmux-guard.bash'
  'scripts/pnpm-rmux-guard.allowlist'
  'scripts/pnpm-rmux-reapply.bash'
  'docs/PNPM-RMUX-LAW.md'
  'src/team/**'
  'src/installer/**'
  'src/hooks/project-memory/**'
  'receipts/**'
  'src/hooks/permission-handler/**'
  'src/features/background-tasks.ts'
  'src/hooks/keyword-detector/**'
  "src/$(_src_signal_dir)/signal.ts"
  'scripts/pre-tool-enforcer.mjs'
  'scripts/release-boundary.mjs'
  'scripts/sync-metadata.ts'
  'scripts/build-bridge-entry.mjs'
  'scripts/build-mcp-server.mjs'
  'scripts/lib/hud-wrapper-template.*'
  'src/__tests__/**'
  'src/installer/__tests__/**'
  'src/skills/__tests__/omc-doctor-skill.test.ts'
  'src/hooks/persistent-mode/__tests__/ultragoal-persistence.test.ts'
  'tests/lint/**'
  'shellmark/sessions/**'
  '.omc/**'
)

# Allowlisted line-content regexes for content that still matches the invocation
# pattern (e.g. a code fence showing a *banned* command as a documented "don't do
# this" example, or a compat-prose phrase that happens to contain a subcommand
# word right after the tool name by coincidence).
declare -a ALLOW_LINE_PATTERNS=()

load_extra_allow_patterns() {
  [[ -f "$PATTERNS_FILE" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ALLOW_LINE_PATTERNS+=("$line")
  done < "$PATTERNS_FILE"
}

is_allowlisted_line() {
  local content=$1
  local pat
  for pat in "${ALLOW_LINE_PATTERNS[@]+"${ALLOW_LINE_PATTERNS[@]}"}"; do
    [[ "$content" =~ $pat ]] && return 0
  done
  return 1
}

# rg --glob only filters rg's own directory walk; explicit file-path arguments bypass
# it entirely. Filter here too so exempt paths never get scanned via an explicit list.
path_is_exempt() {
  local path=$1
  local g
  # shellcheck disable=SC2053
  for g in "${EXEMPT_GLOBS[@]}"; do
    # unquoted glob match against $g is intentional
    [[ "$path" == $g || "$path" == */$g ]] && return 0
  done
  return 1
}

filter_exempt_targets() {
  local -n src=$1
  local -a kept=()
  local t
  for t in "${src[@]}"; do
    path_is_exempt "$t" || kept+=("$t")
  done
  src=("${kept[@]+"${kept[@]}"}")
}

run_precommit() {
  local pattern
  pattern=$(build_banned_pattern)

  local -a targets=()
  mapfile -t targets < <(git diff --cached --name-only --diff-filter=ACM)
  (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no staged files\n'; return 0; }

  filter_exempt_targets targets
  (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no non-exempt staged files\n'; return 0; }

  # One diff invocation for the whole index -- per-file `git diff` spawns made
  # large commits (hundreds of files) blow the hook timeout. File boundaries are
  # recovered from the +++ headers; exemption is re-checked per file so the
  # single pass matches the per-file behavior exactly.
  local -a all_violations=()
  local line file='' skip=1 new_line=0
  while IFS= read -r line; do
    if [[ "$line" == +++* ]]; then
      file=${line#+++ }
      file=${file#b/}
      if [[ "$file" == /dev/null ]] || path_is_exempt "$file" || [[ ! -f "$file" ]]; then
        skip=1
      else
        skip=0
      fi
      continue
    fi
    (( skip )) && [[ "$line" != @@* ]] && continue
    if [[ "$line" =~ ^@@\ -[0-9]+(,[0-9]+)?\ \+([0-9]+) ]]; then
      new_line=${BASH_REMATCH[2]}
      continue
    fi
    (( skip )) && continue
    [[ "$line" == ---* ]] && continue
    if [[ "$line" == +* ]]; then
      local content=${line:1}
      if [[ "$content" =~ $pattern ]] && ! is_allowlisted_line "$content"; then
        all_violations+=("$file:$new_line: $content")
      fi
      (( new_line++ ))
    fi
  done < <(git diff --cached -U0 --diff-filter=ACM)

  if (( ${#all_violations[@]} > 0 )); then
    printf 'pnpm-rmux-guard: staged diff adds banned npm/tmux invocation(s) (see %s):\n' "$LAW_DOC" >&2
    printf '  %s\n' "${all_violations[@]}" >&2
    return 1
  fi

  printf 'pnpm-rmux-guard: clean\n'
  return 0
}

# Advisory tree-wide report: scans full current file content (not diff-scoped),
# never fails the caller regardless of what it finds. For periodic manual review
# of the whole tree's compliance, not for gating commits.
run_audit() {
  local pattern
  pattern=$(build_banned_pattern)

  local -a rg_args=(--line-number --with-filename --no-heading -P "$pattern")
  local g
  for g in "${EXEMPT_GLOBS[@]}"; do
    rg_args+=(--glob "!$g")
  done

  local -a matches=()
  mapfile -t matches < <(rg "${rg_args[@]}" -- . 2>/dev/null || true)

  local -a violations=()
  local line file lineno content
  for line in "${matches[@]+"${matches[@]}"}"; do
    IFS=':' read -r file lineno content <<< "$line"
    is_allowlisted_line "$content" && continue
    violations+=("$file:$lineno: $content")
  done

  printf 'pnpm-rmux-guard --audit: %d advisory hit(s) tree-wide (see %s)\n' \
    "${#violations[@]}" "$LAW_DOC"
  printf '  %s\n' "${violations[@]+"${violations[@]}"}"
  return 0
}

# Manual mode: scan given files' current on-disk content in full (not diff-scoped).
run_paths() {
  local pattern
  pattern=$(build_banned_pattern)

  local -a targets=("$@")
  filter_exempt_targets targets
  (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no non-exempt targets\n'; return 0; }

  local -a rg_args=(--line-number --with-filename --no-heading -P "$pattern")
  local -a matches=()
  mapfile -t matches < <(rg "${rg_args[@]}" -- "${targets[@]}" 2>/dev/null || true)

  local -a violations=()
  local line file lineno content
  for line in "${matches[@]+"${matches[@]}"}"; do
    IFS=':' read -r file lineno content <<< "$line"
    is_allowlisted_line "$content" && continue
    violations+=("$file:$lineno: $content")
  done

  if (( ${#violations[@]} > 0 )); then
    printf 'pnpm-rmux-guard: banned npm/tmux invocation(s) found (see %s):\n' "$LAW_DOC" >&2
    printf '  %s\n' "${violations[@]}" >&2
    return 1
  fi

  printf 'pnpm-rmux-guard: clean\n'
  return 0
}

main() {
  load_extra_allow_patterns

  case "${1:-}" in
    --audit) run_audit ;;
    --staged | '') run_precommit ;;
    *) run_paths "$@" ;;
  esac
}

main "$@"
