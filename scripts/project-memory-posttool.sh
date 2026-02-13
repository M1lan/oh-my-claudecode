#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

declare -r _PASS='{"continue":true,"suppressOutput":true}'
declare -r _MEMORY_FILE='.omc/project-memory.json'
declare -r _PROJECT_MARKERS=('.git' 'pyproject.toml' 'package.json' 'Cargo.toml' 'go.mod' '.venv')
declare -ri _MAX_HOT_PATHS=50
declare -ri _MAX_CUSTOM_NOTES=20

find_project_root() {
  local dir=$1 marker cur=$dir
  while true; do
    for marker in "${_PROJECT_MARKERS[@]}"; do
      [[ -e "${cur}/${marker}" ]] && printf '%s' "$cur" && return 0
    done
    local parent="${cur%/*}"
    [[ "$parent" == "$cur" || -z "$parent" ]] && return 1
    cur=$parent
  done
}

# returns 0 if command is a build command
is_build_command() {
  local cmd=$1
  [[ $cmd =~ ^(npm|pnpm|yarn|npx)[[:space:]]+(run[[:space:]]+)?build ]] && return 0
  [[ $cmd =~ ^tsc([[:space:]]|$) ]] && return 0
  [[ $cmd =~ ^cargo[[:space:]]+build ]] && return 0
  [[ $cmd =~ ^make([[:space:]]|$) ]] && return 0
  [[ $cmd =~ ^cmake ]] && return 0
  [[ $cmd =~ ^gradle[[:space:]]+(build|assemble) ]] && return 0
  [[ $cmd =~ ^mvn[[:space:]]+(package|install|compile) ]] && return 0
  [[ $cmd =~ ^go[[:space:]]+build ]] && return 0
  [[ $cmd =~ ^python[[:space:]]+-m[[:space:]]+build ]] && return 0
  return 1
}

# returns 0 if command is a test command
is_test_command() {
  local cmd=$1
  [[ $cmd =~ ^(npm|pnpm|yarn)[[:space:]]+(run[[:space:]]+)?test ]] && return 0
  [[ $cmd =~ ^npx[[:space:]]+.*test ]] && return 0
  [[ $cmd =~ ^pytest ]] && return 0
  [[ $cmd =~ ^python[[:space:]]+-m[[:space:]]+(pytest|unittest) ]] && return 0
  [[ $cmd =~ ^cargo[[:space:]]+test ]] && return 0
  [[ $cmd =~ ^go[[:space:]]+test ]] && return 0
  [[ $cmd =~ ^jest ]] && return 0
  [[ $cmd =~ ^vitest ]] && return 0
  [[ $cmd =~ ^mocha ]] && return 0
  return 1
}

# update hot path in memory JSON for a given file/dir path
# params: memory_json path type(file|directory)
# prints updated JSON to stdout
update_hot_path() {
  local mem=$1 fpath=$2 ptype=$3
  local now_ms=$(( EPOCHREALTIME * 1000 ))
  printf -v now_ms '%d' "$now_ms"

  jq -n \
    --argjson mem "$mem" \
    --arg path "$fpath" \
    --arg type "$ptype" \
    --argjson now "$now_ms" \
    --argjson max "$_MAX_HOT_PATHS" \
    '
    ($mem.hotPaths // []) as $hp |
    ($hp | map(select(.path == $path)) | first) as $existing |
    (if $existing != null then
      $hp | map(if .path == $path then . + {accessCount: (.accessCount + 1), lastAccessed: $now} else . end)
    else
      $hp + [{path: $path, type: $type, accessCount: 1, lastAccessed: $now}]
    end) as $updated |
    # keep top max entries by accessCount, then trim
    ($updated | sort_by(-.accessCount) | .[0:$max]) as $trimmed |
    $mem | .hotPaths = $trimmed
    '
}

# add a custom note if not already present, trimming to max 20
# params: memory_json category content
# prints updated JSON to stdout
add_custom_note() {
  local mem=$1 cat=$2 content=$3
  local now_ms=$(( EPOCHREALTIME * 1000 ))
  printf -v now_ms '%d' "$now_ms"

  jq -n \
    --argjson mem "$mem" \
    --arg cat "$cat" \
    --arg content "$content" \
    --argjson now "$now_ms" \
    --argjson max "$_MAX_CUSTOM_NOTES" \
    '
    ($mem.customNotes // []) as $notes |
    (if ($notes | any(.category == $cat and .content == $content)) then $notes
     else $notes + [{timestamp: $now, source: "learned", category: $cat, content: $content}]
     end) as $updated |
    $mem | .customNotes = ($updated | .[-($max):])'
}

# extract runtime version hints from tool output
# params: memory_json output_string
# prints updated JSON to stdout
extract_hints() {
  local mem=$1 output=$2

  # Node.js version
  if [[ $output =~ Node\.js[[:space:]]+(v?[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    mem=$(add_custom_note "$mem" "runtime" "Node.js ${BASH_REMATCH[1]}" 2>/dev/null || printf '%s' "$mem")
  fi

  # Python version
  if [[ $output =~ Python[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    mem=$(add_custom_note "$mem" "runtime" "Python ${BASH_REMATCH[1]}" 2>/dev/null || printf '%s' "$mem")
  fi

  # Rust version
  if [[ $output =~ rustc[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+) ]]; then
    mem=$(add_custom_note "$mem" "runtime" "Rust ${BASH_REMATCH[1]}" 2>/dev/null || printf '%s' "$mem")
  fi

  # Missing module
  if [[ $output =~ "Cannot find module '"([^\']+)"'" ]]; then
    mem=$(add_custom_note "$mem" "dependency" "Missing dependency: ${BASH_REMATCH[1]}" 2>/dev/null || printf '%s' "$mem")
  fi

  printf '%s' "$mem"
}

# atomically write updated memory to disk
# params: memory_file memory_json
write_memory() {
  local mfile=$1 content=$2
  local tmp
  tmp=$(mktemp "${mfile}.XXXXXX") || return 1
  printf '%s\n' "$content" > "$tmp" && mv "$tmp" "$mfile" 2>/dev/null || rm -f "$tmp"
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '%s\n' "$_PASS" && exit 0

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // .toolName // ""' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
[[ -z "$cwd" ]] && cwd="$PWD"

# only process relevant tools
case "$tool_name" in
  Read|Edit|Write|Glob|Grep|Bash) ;;
  *) printf '%s\n' "$_PASS"; exit 0 ;;
esac

project_root=$(find_project_root "$cwd" 2>/dev/null || true)
if [[ -z "${project_root:-}" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

memory_file="${project_root}/${_MEMORY_FILE}"
[[ ! -f "$memory_file" ]] && printf '%s\n' "$_PASS" && exit 0

memory=$(< "$memory_file" 2>/dev/null || true)
[[ -z "${memory:-}" ]] && printf '%s\n' "$_PASS" && exit 0

updated=false

# track file/directory accesses
case "$tool_name" in
  Read|Edit|Write)
    fpath=$(printf '%s' "$input" | jq -r '(.tool_input // .toolInput // {}) | (.file_path // .filePath // "")' 2>/dev/null || true)
    if [[ -n "$fpath" ]]; then
      # make relative to project root
      rel_path="${fpath#"${project_root}/"}"
      memory=$(update_hot_path "$memory" "$rel_path" "file" 2>/dev/null || printf '%s' "$memory")
      updated=true
    fi
    ;;
  Glob|Grep)
    dpath=$(printf '%s' "$input" | jq -r '(.tool_input // .toolInput // {}).path // ""' 2>/dev/null || true)
    if [[ -n "$dpath" ]]; then
      rel_path="${dpath#"${project_root}/"}"
      memory=$(update_hot_path "$memory" "$rel_path" "directory" 2>/dev/null || printf '%s' "$memory")
      updated=true
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '(.tool_input // .toolInput // {}).command // ""' 2>/dev/null || true)
    tool_output=$(printf '%s' "$input" | jq -r '.tool_response // .tool_output // ""' 2>/dev/null || true)

    if [[ -n "$cmd" ]]; then
      # detect and store build command
      if is_build_command "$cmd"; then
        cur_build=$(printf '%s' "$memory" | jq -r '.build.buildCommand // ""' 2>/dev/null || true)
        if [[ "$cur_build" != "$cmd" ]]; then
          memory=$(printf '%s' "$memory" | jq --arg cmd "$cmd" '.build.buildCommand = $cmd' 2>/dev/null || printf '%s' "$memory")
          updated=true
        fi
      fi

      # detect and store test command
      if is_test_command "$cmd"; then
        cur_test=$(printf '%s' "$memory" | jq -r '.build.testCommand // ""' 2>/dev/null || true)
        if [[ "$cur_test" != "$cmd" ]]; then
          memory=$(printf '%s' "$memory" | jq --arg cmd "$cmd" '.build.testCommand = $cmd' 2>/dev/null || printf '%s' "$memory")
          updated=true
        fi
      fi

      # extract environment hints from output
      if [[ -n "$tool_output" ]]; then
        new_mem=$(extract_hints "$memory" "$tool_output" 2>/dev/null || printf '%s' "$memory")
        if [[ "$new_mem" != "$memory" ]]; then
          memory="$new_mem"
          updated=true
        fi
      fi
    fi
    ;;
esac

[[ "$updated" == "true" ]] && write_memory "$memory_file" "$memory" 2>/dev/null || true

printf '%s\n' "$_PASS"
