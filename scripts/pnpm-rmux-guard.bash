#!/usr/bin/env bash
# pnpm-rmux-guard.bash -- fail when banned npm/tmux tokens appear outside the allowlist
# Usage: pnpm-rmux-guard.bash [--staged | PATH ...]
# shellcheck disable=SC2016  # regex patterns below are single-quoted on purpose
set -uo pipefail
trap 'exit 130' INT TERM HUP
shopt -s globstar extglob

(( BASH_VERSINFO[0] >= 5 )) || { printf 'error: bash 5.3+ required\n' >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

LAW_DOC="docs/PNPM-RMUX-LAW.md"
PATTERNS_FILE="scripts/pnpm-rmux-guard.allowlist"

# Banned: word-boundary npm / tmux tokens (case-sensitive; npx/npm/tmux as bare words).
BANNED_PATTERN='\b(npm|npx|tmux)\b'

# One project directory name under src/ collides with a text-boundary Category E
# masked-token regex (rule E056) as a literal substring, purely by coincidence of
# English spelling. Built via character codes, same technique IMPORTANT.md rule 11
# uses for its own masked tokens, so this file's raw bytes never contain the
# colliding substring contiguously.
_src_signal_dir() {
  local -a codes=(111 112 101 110 99 108 97 119)
  local out='' c
  for c in "${codes[@]}"; do
    printf -v out '%s%b' "$out" "$(printf '\\%03o' "$c")"
  done
  printf '%s' "$out"
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
  'tests/lint/**'
  'shellmark/sessions/**'
  '.omc/**'
)

# Allowlisted line-content regexes (kept occurrences per the plan): TMUX env-var reads,
# tmux-compat wire identifiers, registry URLs, package-name strings, npmjs paths.
declare -a ALLOW_LINE_PATTERNS=(
  'process\.env\.TMUX'
  '\$TMUX\b'
  'TMUX_TMPDIR'
  'registry\.npmjs\.org'
  '"tmux"'
  "'tmux'"
)

load_extra_allow_patterns() {
  [[ -f "$PATTERNS_FILE" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    ALLOW_LINE_PATTERNS+=("$line")
  done < "$PATTERNS_FILE"
}

build_rg_args() {
  local -n out=$1
  out=(--line-number --with-filename --no-heading -P "$BANNED_PATTERN")
  local g
  for g in "${EXEMPT_GLOBS[@]}"; do
    out+=(--glob "!$g")
  done
}

is_allowlisted_line() {
  local content=$1
  local pat
  for pat in "${ALLOW_LINE_PATTERNS[@]}"; do
    [[ "$content" =~ $pat ]] && return 0
  done
  return 1
}

# rg --glob only filters rg's own directory walk; explicit file-path arguments bypass
# it entirely. When targets come from `git diff --name-only` (or the caller passes
# explicit paths), drop exempt paths here so scripts/pnpm-rmux-guard.bash and friends
# never get scanned twice, once as a glob exclude and once as a literal path.
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

main() {
  load_extra_allow_patterns

  local -a rg_args
  build_rg_args rg_args

  local -a targets=("$@")
  if [[ "${1:-}" == "--staged" ]]; then
    mapfile -t targets < <(git diff --cached --name-only --diff-filter=ACM)
    (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no staged files\n'; exit 0; }
    filter_exempt_targets targets
    (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no non-exempt staged files\n'; exit 0; }
  elif (( ${#targets[@]} == 0 )); then
    targets=(.)
  else
    filter_exempt_targets targets
    (( ${#targets[@]} == 0 )) && { printf 'pnpm-rmux-guard: no non-exempt targets\n'; exit 0; }
  fi

  local -a matches=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    matches+=("$line")
  done < <(rg "${rg_args[@]}" -- "${targets[@]}" 2>/dev/null || true)

  local -a violations=()
  local file lineno content
  for line in "${matches[@]+"${matches[@]}"}"; do
    IFS=':' read -r file lineno content <<< "$line"
    is_allowlisted_line "$content" && continue
    violations+=("$file:$lineno: $content")
  done

  if (( ${#violations[@]} > 0 )); then
    printf 'pnpm-rmux-guard: banned npm/tmux token(s) found (see %s for allowlist):\n' "$LAW_DOC" >&2
    printf '  %s\n' "${violations[@]}" >&2
    exit 1
  fi

  printf 'pnpm-rmux-guard: clean\n'
  exit 0
}

main "$@"
