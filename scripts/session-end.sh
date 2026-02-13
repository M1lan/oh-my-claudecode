#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

declare -r _OMC_CONFIG="${HOME}/.omc-config.json"

# read agent spawn/completion counts from subagent-tracking.json
# params: omc_dir
get_agent_counts() {
  local tracking="${1}/state/subagent-tracking.json"
  if [[ ! -f "$tracking" ]]; then
    printf '0 0'
    return
  fi
  jq -r '
    (.agents | length | tostring) + " " +
    (([.agents[] | select(.status == "completed")] | length) | tostring)
  ' < "$tracking" 2>/dev/null || printf '0 0'
}

# detect which modes were used (state files present)
# params: state_dir
get_modes_used() {
  local state_dir=$1
  local -a modes=()
  local -a mode_files=(
    'autopilot-state.json:autopilot'
    'ultrapilot-state.json:ultrapilot'
    'ralph-state.json:ralph'
    'ultrawork-state.json:ultrawork'
    'ecomode-state.json:ecomode'
    'swarm-state.json:swarm'
    'pipeline-state.json:pipeline'
    'ultraqa-state.json:ultraqa'
  )
  for entry in "${mode_files[@]}"; do
    local file="${entry%%:*}" mode="${entry##*:}"
    [[ -f "${state_dir}/${file}" ]] && modes+=("$mode")
  done
  printf '%s ' "${modes[@]+"${modes[@]}"}"
}

# get session start time from any state file that has started_at
# params: state_dir
get_session_start() {
  local state_dir=$1
  for f in "${state_dir}"/*.json; do
    [[ -f "$f" ]] || continue
    local ts
    ts=$(jq -r '.started_at // empty' < "$f" 2>/dev/null || true)
    [[ -n "$ts" ]] && printf '%s' "$ts" && return 0
  done
}

# clean up transient files: subagent-tracking.json, stale checkpoints (>24h), .tmp files
# params: omc_dir
cleanup_transient() {
  local omc_dir=$1
  local removed=0

  # subagent tracking
  local tracking="${omc_dir}/state/subagent-tracking.json"
  if [[ -f "$tracking" ]]; then
    rm -f "$tracking" 2>/dev/null && (( removed++ )) || true
  fi

  # stale checkpoints older than 24h
  local checkpoints_dir="${omc_dir}/checkpoints"
  if [[ -d "$checkpoints_dir" ]]; then
    local cutoff=$(( $(date +%s 2>/dev/null || printf '0') - 86400 ))
    for f in "${checkpoints_dir}"/*; do
      [[ -f "$f" ]] || continue
      local mtime
      mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || printf '0')
      (( mtime > 0 && mtime < cutoff )) && rm -f "$f" 2>/dev/null && (( removed++ )) || true
    done
  fi

  # .tmp files recursively under .omc/
  while IFS= read -r -d '' f; do
    rm -f "$f" 2>/dev/null && (( removed++ )) || true
  done < <($FIND "$omc_dir" -name '*.tmp' -print0 2>/dev/null || true)

  printf '%d' "$removed"
}

# clean up active mode state files belonging to this session
# params: state_dir session_id
cleanup_mode_states() {
  local state_dir=$1 session_id=$2
  local -a mode_files=(
    'autopilot-state.json:autopilot'
    'ultrapilot-state.json:ultrapilot'
    'ralph-state.json:ralph'
    'ultrawork-state.json:ultrawork'
    'ecomode-state.json:ecomode'
    'ultraqa-state.json:ultraqa'
    'pipeline-state.json:pipeline'
    'swarm-summary.json:swarm'
  )

  for entry in "${mode_files[@]}"; do
    local file="${entry%%:*}"
    local fpath="${state_dir}/${file}"
    [[ ! -f "$fpath" ]] && continue
    local active state_sid
    active=$(jq -r '.active // "false"' < "$fpath" 2>/dev/null || printf 'false')
    [[ "$active" != "true" ]] && continue
    state_sid=$(jq -r '.session_id // ""' < "$fpath" 2>/dev/null || true)
    # remove if session matches, or state has no session_id (legacy)
    if [[ -z "$state_sid" || -z "$session_id" || "$state_sid" == "$session_id" ]]; then
      rm -f "$fpath" 2>/dev/null || true
    fi
  done

  # swarm marker: always remove
  local marker="${state_dir}/swarm-active.marker"
  [[ -f "$marker" ]] && rm -f "$marker" 2>/dev/null || true
}

# format session summary as markdown
# params: session_id started_at ended_at reason duration_ms spawned completed modes_csv
format_summary_md() {
  local session_id=$1 started_at=$2 ended_at=$3 reason=$4
  local duration_ms=$5 spawned=$6 completed=$7 modes_csv=$8

  local duration_str='unknown'
  if [[ -n "$duration_ms" && "$duration_ms" =~ ^[0-9]+$ ]] && (( duration_ms > 0 )); then
    local secs=$(( duration_ms / 1000 ))
    local mins=$(( secs / 60 ))
    local rem=$(( secs % 60 ))
    duration_str="${mins}m ${rem}s"
  fi

  printf '# Session Ended\n\n**Session ID:** `%s`\n**Duration:** %s\n**Reason:** %s\n**Agents Spawned:** %s\n**Agents Completed:** %s\n**Modes Used:** %s\n**Started At:** %s\n**Ended At:** %s' \
    "$session_id" "$duration_str" "$reason" "$spawned" "$completed" \
    "${modes_csv:-none}" "${started_at:-unknown}" "$ended_at"
}

# send Telegram notification
# params: bot_token chat_id message
send_telegram() {
  local bot_token=$1 chat_id=$2 message=$3
  # validate token format
  [[ ! "$bot_token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] && return 1
  curl -s --max-time 10 -X POST \
    "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg chat_id "$chat_id" --arg text "$message" \
      '{chat_id:$chat_id,text:$text,parse_mode:"Markdown"}')" \
    > /dev/null 2>&1 || true
}

# send Discord webhook notification
# params: webhook_url message
send_discord() {
  local webhook_url=$1 message=$2
  # validate Discord webhook URL
  if [[ ! "$webhook_url" =~ ^https://(discord\.com|discordapp\.com)/ ]]; then
    return 1
  fi
  curl -s --max-time 10 -X POST "$webhook_url" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg content "$message" '{content:$content}')" \
    > /dev/null 2>&1 || true
}

# interpolate path template: {session_id}, {date}, {time}
# params: template session_id
interpolate_path() {
  local tmpl=$1 session_id=$2
  local date_str time_str safe_sid
  date_str=$(date -u +"%Y-%m-%d" 2>/dev/null || printf 'unknown-date')
  time_str=$(date -u +"%H-%M-%S" 2>/dev/null || printf 'unknown-time')
  # sanitize session_id: remove / \ .
  safe_sid="${session_id//[\/\\.\\]/_}"
  tmpl="${tmpl/#\~/$HOME}"
  tmpl="${tmpl//\{session_id\}/$safe_sid}"
  tmpl="${tmpl//\{date\}/$date_str}"
  tmpl="${tmpl//\{time\}/$time_str}"
  printf '%s' "$tmpl"
}

# trigger stop callbacks from config
# params: session_id summary_md
trigger_callbacks() {
  local session_id=$1 summary=$2
  [[ ! -f "$_OMC_CONFIG" ]] && return 0

  local callbacks
  callbacks=$(jq -r '.stopHookCallbacks // empty' < "$_OMC_CONFIG" 2>/dev/null || true)
  [[ -z "${callbacks:-}" ]] && return 0

  # file callback
  local file_enabled file_path file_format
  file_enabled=$(printf '%s' "$callbacks" | jq -r '.file.enabled // false' 2>/dev/null || printf 'false')
  if [[ "$file_enabled" == "true" ]]; then
    file_path=$(printf '%s' "$callbacks" | jq -r '.file.path // ""' 2>/dev/null || true)
    file_format=$(printf '%s' "$callbacks" | jq -r '.file.format // "markdown"' 2>/dev/null || printf 'markdown')
    if [[ -n "$file_path" ]]; then
      local resolved
      resolved=$(interpolate_path "$file_path" "$session_id")
      mkdir -p "${resolved%/*}" 2>/dev/null || true
      if [[ "$file_format" == "json" ]]; then
        printf '%s\n' "$summary" > "$resolved" 2>/dev/null || true
      else
        printf '%s\n' "$summary" > "$resolved" 2>/dev/null || true
      fi
    fi
  fi

  # telegram callback
  local tg_enabled tg_token tg_chat
  tg_enabled=$(printf '%s' "$callbacks" | jq -r '.telegram.enabled // false' 2>/dev/null || printf 'false')
  if [[ "$tg_enabled" == "true" ]]; then
    tg_token=$(printf '%s' "$callbacks" | jq -r '.telegram.botToken // ""' 2>/dev/null || true)
    tg_chat=$(printf '%s' "$callbacks" | jq -r '.telegram.chatId // ""' 2>/dev/null || true)
    if [[ -n "$tg_token" && -n "$tg_chat" ]]; then
      local tg_tags tg_message
      tg_tags=$(printf '%s' "$callbacks" | jq -r '(.telegram.tagList // []) | map(if startswith("@") then . else "@"+. end) | join(" ")' 2>/dev/null || true)
      tg_message="${tg_tags:+${tg_tags}\n}${summary}"
      send_telegram "$tg_token" "$tg_chat" "$tg_message" &
    fi
  fi

  # discord callback
  local dc_enabled dc_url
  dc_enabled=$(printf '%s' "$callbacks" | jq -r '.discord.enabled // false' 2>/dev/null || printf 'false')
  if [[ "$dc_enabled" == "true" ]]; then
    dc_url=$(printf '%s' "$callbacks" | jq -r '.discord.webhookUrl // ""' 2>/dev/null || true)
    if [[ -n "$dc_url" ]]; then
      local dc_tags dc_message
      dc_tags=$(printf '%s' "$callbacks" | jq -r '
        (.discord.tagList // []) | map(
          if . == "@here" or . == "@everyone" then .
          elif test("^role:[0-9]+$") then "<@&" + ltrimstr("role:") + ">"
          elif test("^[0-9]+$") then "<@" + . + ">"
          else . end
        ) | join(" ")
      ' 2>/dev/null || true)
      dc_message="${dc_tags:+${dc_tags}\n}${summary}"
      send_discord "$dc_url" "$dc_message" &
    fi
  fi

  # wait for background callbacks (max 5s)
  wait 2>/dev/null || true
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '{"continue":true}\n' && exit 0

session_id=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // ""' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
[[ -z "$cwd" ]] && cwd="$PWD"
reason=$(printf '%s' "$input" | jq -r '.reason // "other"' 2>/dev/null || printf 'other')

omc_dir="${cwd}/.omc"
state_dir="${omc_dir}/state"

# gather session metrics
agent_counts=$(get_agent_counts "$omc_dir")
spawned="${agent_counts%% *}"
completed="${agent_counts##* }"

modes_str=$(get_modes_used "$state_dir")
# trim trailing space, convert to comma-separated
modes_csv="${modes_str%" "}"
modes_csv="${modes_csv//" "/","}"

started_at=$(get_session_start "$state_dir")
ended_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)

duration_ms=
if [[ -n "${started_at:-}" ]]; then
  start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || printf '0')
  end_epoch=$(date -u +%s 2>/dev/null || printf '0')
  if (( start_epoch > 0 && end_epoch > 0 )); then
    duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
  fi
fi

# write session summary to .omc/sessions/
if [[ -n "$session_id" ]]; then
  sessions_dir="${omc_dir}/sessions"
  mkdir -p "$sessions_dir" 2>/dev/null || true
  jq -n \
    --arg session_id "$session_id" \
    --arg started_at "${started_at:-}" \
    --arg ended_at "$ended_at" \
    --arg reason "$reason" \
    --argjson spawned "$spawned" \
    --argjson completed "$completed" \
    --argjson duration_ms "${duration_ms:-null}" \
    --arg modes "$modes_csv" \
    '{
      session_id: $session_id,
      started_at: (if $started_at == "" then null else $started_at end),
      ended_at: $ended_at,
      reason: $reason,
      agents_spawned: $spawned,
      agents_completed: $completed,
      duration_ms: $duration_ms,
      modes_used: (if $modes == "" then [] else ($modes | split(",") | map(select(. != ""))) end)
    }' > "${sessions_dir}/${session_id}.json" 2>/dev/null || true
fi

# clean up transient state
cleanup_transient "$omc_dir" > /dev/null 2>&1 || true

# clean up mode state files
if [[ -d "$state_dir" ]]; then
  cleanup_mode_states "$state_dir" "$session_id" 2>/dev/null || true
fi

# trigger stop callbacks
summary=$(format_summary_md \
  "$session_id" "${started_at:-}" "$ended_at" "$reason" \
  "${duration_ms:-}" "$spawned" "$completed" "${modes_csv:-none}")
trigger_callbacks "$session_id" "$summary" 2>/dev/null || true

printf '{"continue":true}\n'
