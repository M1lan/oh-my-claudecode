#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

# ERE character classes stored in variables to prevent bash re-expansion
# Matches TS: /[;&|`$()<>\n\r\t\0\\{}\[\]*?~!#]/
declare -r _DANG_META='[;&|`$()<>\\{}*?~!#]'
declare -r _DANG_BRACKET='[][]]'  # matches [ or ]

# returns 0 if command contains dangerous shell metacharacters
has_dangerous_chars() {
  local cmd=$1
  [[ $cmd =~ $_DANG_META ]] && return 0
  [[ $cmd =~ $_DANG_BRACKET ]] && return 0
  # control characters (tab, newline, carriage return)
  printf '%s' "$cmd" | $GREP -qP '[\t\n\r]' 2>/dev/null && return 0
  return 1
}

# returns 0 if command matches a known-safe pattern
is_safe_command() {
  local cmd=$1
  # ltrim / rtrim whitespace
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  [[ $cmd =~ ^git[[:space:]]+(status|diff|log|branch|show|fetch) ]] && return 0
  [[ $cmd =~ ^(npm|pnpm|yarn)[[:space:]]+(test$|run[[:space:]]+(test|lint|build|check|typecheck)) ]] && return 0
  [[ $cmd =~ ^tsc([[:space:]]|$) ]] && return 0
  [[ $cmd =~ ^eslint[[:space:]] ]] && return 0
  [[ $cmd =~ ^prettier[[:space:]] ]] && return 0
  [[ $cmd =~ ^cargo[[:space:]]+(test|check|clippy|build) ]] && return 0
  [[ $cmd =~ ^pytest ]] && return 0
  [[ $cmd =~ ^python[[:space:]]+-m[[:space:]]+pytest ]] && return 0
  [[ $cmd =~ ^ls([[:space:]]|$) ]] && return 0
  return 1
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '{"continue":true}\n' && exit 0

tool_name=$(printf '%s' "$input" \
  | jq -r '(.tool_name // .toolName // "") | ltrimstr("proxy_")' 2>/dev/null || true)

if [[ "$tool_name" != "Bash" ]]; then
  printf '{"continue":true}\n'
  exit 0
fi

command=$(printf '%s' "$input" \
  | jq -r '(.tool_input // .toolInput // {}).command // ""' 2>/dev/null || true)

if [[ -z "$command" ]]; then
  printf '{"continue":true}\n'
  exit 0
fi

if has_dangerous_chars "$command"; then
  printf '{"continue":true}\n'
  exit 0
fi

if is_safe_command "$command"; then
  printf '%s\n' '{"continue":true,"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","reason":"Safe read-only or test command"}}}'
  exit 0
fi

printf '{"continue":true}\n'
