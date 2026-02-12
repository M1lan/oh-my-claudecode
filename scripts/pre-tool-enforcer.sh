#!/usr/bin/env bash
set -uo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(timeout 5 cat 2>/dev/null || true)

# Extract field from JSON with jq, fallback to regex
extract_field() {
  local field="$1"
  local default="${2:-}"
  local value=""
  if command -v jq &>/dev/null; then
    value=$(printf '%s' "$input" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)
  fi
  if [[ -z "$value" ]]; then
    value=$(printf '%s' "$input" | perl -ne "print \$1 if /\"${field}\"\\s*:\\s*\"([^\"]*)\"/" 2>/dev/null | head -1 || true)
  fi
  printf '%s' "${value:-$default}"
}

get_todo_status() {
  local directory="$1"
  local pending=0
  local in_progress=0

  for todo_file in "${directory}/.omc/todos.json" "${directory}/.claude/todos.json"; do
    if [[ -f "$todo_file" ]]; then
      if command -v jq &>/dev/null; then
        local p ip
        p=$(jq '[(.todos // .) | arrays[] | select(.status == "pending")] | length' "$todo_file" 2>/dev/null || printf '%s' 0)
        ip=$(jq '[(.todos // .) | arrays[] | select(.status == "in_progress")] | length' "$todo_file" 2>/dev/null || printf '%s' 0)
        pending=$(( pending + p ))
        in_progress=$(( in_progress + ip ))
      fi
    fi
  done

  if (( pending + in_progress > 0 )); then
    printf '[%d active, %d pending] ' "$in_progress" "$pending"
  fi
}

get_running_agents() {
  local directory="$1"
  local tracking_file="${directory}/.omc/state/subagent-tracking.json"
  if [[ -f "$tracking_file" ]] && command -v jq &>/dev/null; then
    jq '[.agents // [] | .[] | select(.status == "running")] | length' "$tracking_file" 2>/dev/null || printf '%s' 0
  else
    printf '%s\n' 0
  fi
}

tool_name=$(extract_field "tool_name")
[[ -z "$tool_name" ]] && tool_name=$(extract_field "toolName" "unknown")
directory=$(extract_field "cwd")
[[ -z "$directory" ]] && directory=$(extract_field "directory" "$(pwd)")

todo_status=$(get_todo_status "$directory")

if [[ "$tool_name" == "Task" || "$tool_name" == "TaskCreate" || "$tool_name" == "TaskUpdate" ]]; then
  # Extract from toolInput or tool_input
  if command -v jq &>/dev/null; then
    agent_type=$(printf '%s' "$input" | jq -r '(.toolInput // .tool_input // {}).subagent_type // "unknown"' 2>/dev/null || printf '%s' "unknown")
    model=$(printf '%s' "$input" | jq -r '(.toolInput // .tool_input // {}).model // "inherit"' 2>/dev/null || printf '%s' "inherit")
    desc=$(printf '%s' "$input" | jq -r '(.toolInput // .tool_input // {}).description // ""' 2>/dev/null || printf '%s' "")
    bg=$(printf '%s' "$input" | jq -r 'if (.toolInput // .tool_input // {}).run_in_background == true then " [BACKGROUND]" else "" end' 2>/dev/null || printf '%s' "")
  else
    agent_type="unknown"
    model="inherit"
    desc=""
    bg=""
  fi

  running=$(get_running_agents "$directory")

  message="${todo_status}Spawning agent: ${agent_type} (${model})${bg}"
  if [[ -n "$desc" ]]; then
    message="${message} | Task: ${desc}"
  fi
  if (( running > 0 )); then
    message="${message} | Active agents: ${running}"
  fi
else
  case "$tool_name" in
    TodoWrite)
      message="${todo_status}Mark todos in_progress BEFORE starting, completed IMMEDIATELY after finishing."
      ;;
    Bash)
      message="${todo_status}Use parallel execution for independent tasks. Use run_in_background for long operations (npm install, builds, tests)."
      ;;
    Edit|Write)
      message="${todo_status}Verify changes work after editing. Test functionality before marking complete."
      ;;
    Read)
      message="${todo_status}Read multiple files in parallel when possible for faster analysis."
      ;;
    Grep|Glob)
      message="${todo_status}Combine searches in parallel when investigating multiple patterns."
      ;;
    *)
      message="${todo_status}The boulder never stops. Continue until all tasks complete."
      ;;
  esac
fi

printf '%s\n' "$(printf '%s' "$message" | jq -Rs --arg msg "$(printf '%s' "$message")" '{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": $msg
  }
}' 2>/dev/null || printf '{"continue":true,"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}' \
  "$(printf '%s' "$message" | gsed 's/"/\\"/g')")"
