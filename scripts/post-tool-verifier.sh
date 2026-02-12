#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C
shopt -s extglob

cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
state_file="$cfg_dir/.session-stats.json"

require_commands() {
  local missing=0 cmd
  for cmd in jq mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      printf 'error: %s is required\n' "$cmd" >&2
      missing=1
    fi
  done
  return "$missing"
}

trim_string() {
  local str=$1
  str=${str##+([[:space:]])}
  str=${str%%+([[:space:]])}
  printf '%s' "$str"
}

bash_history_enabled() {
  local config="$cfg_dir/.omc-config.json"
  if [[ ! -f $config ]]; then
    return 0
  fi
  if jq -e '(.bashHistory == false) or (.bashHistory.enabled == false)' "$config" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

append_history() {
  local cleaned
  cleaned=$(trim_string "$1")
  if [[ -z $cleaned || ${cleaned:0:1} == '#' ]]; then
    return 0
  fi
  case ${OSTYPE:-} in
    msys* | cygwin* | win32* )
      return 0
      ;;
  esac
  ( umask 077 && printf '%s\n' "$cleaned" >>"$HOME/.bash_history" ) 2>/dev/null
}

ensure_state_file() {
  if [[ ! -d $cfg_dir ]]; then
    mkdir -p "$cfg_dir" 2>/dev/null || return 1
  fi
  if [[ ! -f $state_file ]]; then
    ( umask 077 && printf '{"sessions":{}}\n' >"$state_file" ) || return 1
    return 0
  fi
  jq empty "$state_file" >/dev/null 2>&1 || ( umask 077 && printf '{"sessions":{}}\n' >"$state_file" )
}

update_stats() {
  local session=$1
  local tool=$2
  ensure_state_file || return 1

  local tmp ts
  ts=$(date +%s)
  tmp=$(mktemp "${state_file}.XXXXXX") || return 1
  if ! jq --arg session "$session" --arg tool "$tool" --argjson ts "$ts" '
      (.sessions //= {}) |
      (.sessions[$session] //= {
        tool_counts: {},
        last_tool: "",
        total_calls: 0,
        started_at: $ts
      }) |
      (.sessions[$session].tool_counts[$tool] = ((.sessions[$session].tool_counts[$tool] // 0) + 1)) |
      (.sessions[$session].last_tool = $tool) |
      (.sessions[$session].total_calls = ((.sessions[$session].total_calls // 0) + 1)) |
      (.sessions[$session].updated_at = $ts) |
      (.sessions[$session].started_at //= $ts)
    ' "$state_file" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  if ! mv "$tmp" "$state_file"; then
    rm -f "$tmp"
    return 1
  fi
  jq -r --arg session "$session" --arg tool "$tool" '.sessions[$session].tool_counts[$tool]' "$state_file" 2>/dev/null
}

contains_ci() {
  local text=${1,,}
  shift
  local needle
  for needle in "$@"; do
    local check=${needle,,}
    if [[ $text == *"$check"* ]]; then
      return 0
    fi
  done
  return 1
}

detect_bash_failure() {
  contains_ci "$1" \
    'error:' 'failed' 'cannot' 'permission denied' \
    'command not found' 'no such file' 'exit code' 'exit status' \
    'fatal:' 'abort'
}

detect_background_operation() {
  contains_ci "$1" 'started' 'running' 'background' 'async' 'task_id' 'spawned'
}

detect_write_failure() {
  contains_ci "$1" 'error' 'failed' 'permission denied' 'read-only' 'not found'
}

detect_grep_empty() {
  local text
  text=$(trim_string "$1")
  if [[ -z $text || $text == '0' ]]; then
    return 0
  fi
  contains_ci "$text" 'no matches'
}

detect_glob_empty() {
  local text
  text=$(trim_string "$1")
  if [[ -z $text ]]; then
    return 0
  fi
  contains_ci "$text" 'no files'
}

generate_message() {
  local tool_key=$1
  local count=${2:-0}
  local output=$3
  local message=''

  case $tool_key in
    bash)
      if detect_bash_failure "$output"; then
        message='Command failed. Investigate the error before continuing.'
      elif detect_background_operation "$output"; then
        message='Background operation detected. Verify its results before proceeding.'
      fi
      ;;
    task | taskcreate | taskupdate)
      if detect_write_failure "$output"; then
        message='Task delegation failed. Confirm the agent and parameters.'
      else
        message="Task delegated (${count} total). Track completion status."
        if detect_background_operation "$output"; then
          message+=' Background task detected—review TaskOutput when ready.'
        fi
      fi
      ;;
    edit)
      if detect_write_failure "$output"; then
        message='Edit operation failed. Verify the file path and expected content.'
      else
        message='Code modified. Test the change before marking complete.'
      fi
      ;;
    write)
      if detect_write_failure "$output"; then
        message='Write operation failed. Check permissions and destination directories.'
      else
        message='File written. Validate functionality before continuing.'
      fi
      ;;
    grep)
      if detect_grep_empty "$output"; then
        message='No matches found. Adjust the search pattern or broaden the scope.'
      fi
      ;;
    glob)
      if detect_glob_empty "$output"; then
        message='No files matched the glob. Verify the pattern and working directory.'
      fi
      ;;
  esac

  printf '%s' "$message"
}

print_response() {
  local message=$1
  if [[ -n $message ]]; then
    jq -n --arg msg "$message" '{
      continue: true,
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $msg
      }
    }'
  else
    printf '{"continue":true,"suppressOutput":true}\n'
  fi
}

main() {
  require_commands || return 1

  local input_json
  input_json=$(< /dev/stdin)
  if [[ -z ${input_json//[[:space:]]/} ]]; then
    print_response ''
    return 0
  fi
  if ! jq empty >/dev/null 2>&1 <<<"$input_json"; then
    print_response ''
    return 0
  fi

  local tool_name tool_output tool_input_command session_id
  tool_name=$(jq -r '(.tool_name // .toolName // "") // ""' <<<"$input_json" 2>/dev/null || printf '')
  tool_output=$(jq -r '
    (.tool_response // .toolOutput // "") as $out
    | if ($out | type) == "string" then $out else ($out | @json) end
  ' <<<"$input_json" 2>/dev/null || printf '')
  tool_input_command=$(jq -r '
    ( .tool_input // .toolInput // "" ) as $input
    | if ($input | type) == "string" then $input else ($input.command // "") end
  ' <<<"$input_json" 2>/dev/null || printf '')
  session_id=$(jq -r '(.session_id // .sessionId // "unknown")' <<<"$input_json" 2>/dev/null || printf 'unknown')

  if [[ -z $tool_name ]]; then
    tool_name='Unknown'
  fi
  local tool_key=${tool_name,,}

  local count
  count=$(update_stats "$session_id" "$tool_name" 2>/dev/null || printf '0')
  if [[ ! $count =~ ^[0-9]+$ ]]; then
    count='0'
  fi

  if [[ $tool_key == "bash" && -n $tool_input_command ]] && bash_history_enabled; then
    append_history "$tool_input_command"
  fi

  local message
  message=$(generate_message "$tool_key" "$count" "$tool_output")
  print_response "$message"
}

if ! main; then
  printf '{"continue":true,"suppressOutput":true}\n'
fi
