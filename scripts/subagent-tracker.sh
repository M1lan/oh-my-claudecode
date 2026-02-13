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
declare -ri _STALE_THRESHOLD_MS=300000   # 5 minutes
declare -ri _MAX_COMPLETED=100
declare -ri _LOCK_TIMEOUT_MS=5000
declare -ri _LOCK_RETRY_MS=50

action="${1:-}"
if [[ "$action" != "start" && "$action" != "stop" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

# acquire file lock using noclobber; retries until timeout
# returns 0 on success, 1 on timeout
# params: lock_path
acquire_lock() {
  local lock_path=$1
  local lock_dir="${lock_path%/*}"
  mkdir -p "$lock_dir" 2>/dev/null || true

  local deadline=$(( ${EPOCHREALTIME/./} / 1000 + _LOCK_TIMEOUT_MS ))

  while true; do
    # stale lock check: read existing lock and verify PID is alive
    if [[ -f "$lock_path" ]]; then
      local lock_content lock_pid lock_ts
      lock_content=$(< "$lock_path" 2>/dev/null || true)
      IFS=: read -r lock_pid lock_ts <<< "$lock_content"
      if [[ -n "${lock_pid:-}" && -n "${lock_ts:-}" ]]; then
        local now_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
        local age=$(( now_ms - lock_ts ))
        local pid_alive=false
        kill -0 "$lock_pid" 2>/dev/null && pid_alive=true
        if (( age > _LOCK_TIMEOUT_MS )) || [[ "$pid_alive" == "false" ]]; then
          rm -f "$lock_path" 2>/dev/null || true
        fi
      else
        rm -f "$lock_path" 2>/dev/null || true
      fi
    fi

    # try atomic create with noclobber
    if ( set -C; printf '%d:%d' "$$" "$(( ${EPOCHREALTIME/./} / 1000 ))" > "$lock_path" ) 2>/dev/null; then
      return 0
    fi

    local now_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
    (( now_ms >= deadline )) && return 1
    sleep "0.0${_LOCK_RETRY_MS}" 2>/dev/null || sleep 1
  done
}

# release file lock
# params: lock_path
release_lock() {
  rm -f "$1" 2>/dev/null || true
}

# detect active parent mode from state files
# prints mode name to stdout
detect_parent_mode() {
  local state_dir=$1
  local -a mode_checks=(
    "ultrapilot-state.json:ultrapilot"
    "autopilot-state.json:autopilot"
    "ultrawork-state.json:ultrawork"
    "ralph-state.json:ralph"
  )

  for entry in "${mode_checks[@]}"; do
    local file="${entry%%:*}" mode="${entry##*:}"
    local fpath="${state_dir}/${file}"
    if [[ -f "$fpath" ]]; then
      local active
      active=$(jq -r '.active // .status // ""' < "$fpath" 2>/dev/null || true)
      if [[ "$active" == "true" || "$active" == "running" || "$active" == "active" ]]; then
        printf '%s' "$mode"
        return 0
      fi
    fi
  done

  # swarm: check for non-empty swarm.db
  local swarm_db="${state_dir}/swarm.db"
  if [[ -f "$swarm_db" ]]; then
    local size
    size=$(stat -c %s "$swarm_db" 2>/dev/null || stat -f %z "$swarm_db" 2>/dev/null || printf '0')
    (( size > 0 )) && printf 'swarm' && return 0
  fi

  printf 'none'
}

# read tracking state from disk; returns empty JSON structure if missing
# params: state_path
read_state() {
  local fpath=$1
  if [[ -f "$fpath" ]]; then
    jq '.' < "$fpath" 2>/dev/null || true
  fi
  if [[ -z "$(cat "$fpath" 2>/dev/null || true)" ]] || ! jq -e . < "$fpath" > /dev/null 2>&1; then
    printf '{"agents":[],"total_spawned":0,"total_completed":0,"total_failed":0,"last_updated":""}'
  fi
}

# append event to session replay JSONL
# params: state_dir session_id event_json
append_replay() {
  local state_dir=$1 session_id=$2 event=$3
  [[ -z "$session_id" ]] && return 0
  local replay_dir="${state_dir}/sessions/${session_id}"
  mkdir -p "$replay_dir" 2>/dev/null || true
  printf '%s\n' "$event" >> "${replay_dir}/replay.jsonl" 2>/dev/null || true
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '%s\n' "$_PASS" && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
[[ -z "$cwd" ]] && cwd="$PWD"
session_id=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // ""' 2>/dev/null || true)
agent_id=$(printf '%s' "$input" | jq -r '.agent_id // .agentId // ""' 2>/dev/null || true)
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // .agentType // ""' 2>/dev/null || true)

state_dir="${cwd}/.omc/state"
state_path="${state_dir}/subagent-tracking.json"
lock_path="${state_dir}/subagent-tracker.lock"

mkdir -p "$state_dir" 2>/dev/null || true

if ! acquire_lock "$lock_path"; then
  printf '%s\n' "$_PASS"
  exit 0
fi
trap 'release_lock "$lock_path"' EXIT INT TERM

# read current state
state=
if [[ -f "$state_path" ]]; then
  state=$(jq '.' < "$state_path" 2>/dev/null || true)
fi
if [[ -z "${state:-}" ]]; then
  state='{"agents":[],"total_spawned":0,"total_completed":0,"total_failed":0,"last_updated":""}'
fi

now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || printf '%s' "$(date -u)")
now_ms=$(( ${EPOCHREALTIME/./} / 1000 ))

if [[ "$action" == "start" ]]; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null | head -c 200 || true)
  model=$(printf '%s' "$input" | jq -r '.model // ""' 2>/dev/null || true)
  parent_mode=$(detect_parent_mode "$state_dir")

  state=$(jq -n \
    --argjson state "$state" \
    --arg agent_id "$agent_id" \
    --arg agent_type "$agent_type" \
    --arg started_at "$now_iso" \
    --arg parent_mode "$parent_mode" \
    --arg prompt "$prompt" \
    --arg model "$model" \
    --arg now "$now_iso" \
    '$state |
     .agents += [{
       agent_id: $agent_id,
       agent_type: $agent_type,
       started_at: $started_at,
       parent_mode: $parent_mode,
       task_description: (if $prompt != "" then $prompt else null end),
       model: (if $model != "" then $model else null end),
       status: "running"
     }] |
     .total_spawned += 1 |
     .last_updated = $now' 2>/dev/null || printf '%s' "$state")

  # count running agents
  running=$(printf '%s' "$state" | jq '[.agents[] | select(.status == "running")] | length' 2>/dev/null || printf '0')

  # detect stale agents (running > 5 min)
  stale=$(printf '%s' "$state" | jq -r \
    --argjson threshold "$_STALE_THRESHOLD_MS" \
    --argjson now "$now_ms" \
    '[.agents[] | select(.status == "running") |
      select(($now - ((.started_at | fromdateiso8601) * 1000)) > $threshold) |
      .agent_id] | @json' 2>/dev/null || printf '[]')

  # write updated state
  printf '%s\n' "$state" > "$state_path" 2>/dev/null || true

  # append replay event
  replay_event=$(jq -n \
    --arg type "agent_start" \
    --arg agent_id "$agent_id" \
    --arg agent_type "$agent_type" \
    --arg session_id "$session_id" \
    --arg parent_mode "$parent_mode" \
    --arg ts "$now_iso" \
    '{type:$type,agentId:$agent_id,agentType:$agent_type,sessionId:$session_id,parentMode:$parent_mode,timestamp:$ts}')
  append_replay "$state_dir" "$session_id" "$replay_event"

  jq -n \
    --arg agent_type "$agent_type" \
    --arg agent_id "$agent_id" \
    --argjson count "$running" \
    --argjson stale "$stale" \
    '{continue:true,hookSpecificOutput:{
      hookEventName:"SubagentStart",
      additionalContext:("Agent " + $agent_type + " started (" + $agent_id + ")"),
      agent_count:$count,
      stale_agents:$stale
    }}'

elif [[ "$action" == "stop" ]]; then
  success=$(printf '%s' "$input" | jq -r '.success // "null"' 2>/dev/null || printf 'null')
  # SDK does not provide success field — default to completed when null/undefined
  [[ "$success" == "false" ]] && succeeded=false || succeeded=true
  status_val=$([[ "$succeeded" == "true" ]] && printf 'completed' || printf 'failed')

  output_summary=$(printf '%s' "$input" | jq -r '.output // ""' 2>/dev/null | head -c 500 || true)

  state=$(jq -n \
    --argjson state "$state" \
    --arg agent_id "$agent_id" \
    --arg status "$status_val" \
    --arg completed_at "$now_iso" \
    --arg output "$output_summary" \
    --argjson now_ms "$now_ms" \
    --argjson max_completed "$_MAX_COMPLETED" \
    '$state |
     # update matching agent
     (.agents | map(
       if .agent_id == $agent_id then
         . + {
           status: $status,
           completed_at: $completed_at,
           output_summary: (if $output != "" then $output else null end),
           duration_ms: (($completed_at | fromdateiso8601) * 1000 - ((.started_at | fromdateiso8601) * 1000) | floor)
         }
       else . end
     )) as $updated_agents |
     # update counters
     (if $status == "completed" then .total_completed += 1 else .total_failed += 1 end) |
     .agents = $updated_agents |
     # evict oldest completed/failed beyond max
     ((.agents | map(select(.status == "completed" or .status == "failed")) |
       sort_by(.completed_at) | reverse | .[($max_completed):] | map(.agent_id)) as $to_remove |
       .agents = (.agents | map(select(.agent_id as $id | $to_remove | index($id) == null)))) |
     .last_updated = $completed_at' 2>/dev/null || printf '%s' "$state")

  # look up the agent type from tracked state if missing
  if [[ -z "$agent_type" ]]; then
    agent_type=$(printf '%s' "$state" | jq -r \
      --arg id "$agent_id" \
      '.agents[] | select(.agent_id == $id) | .agent_type // "unknown"' 2>/dev/null || printf 'unknown')
  fi

  printf '%s\n' "$state" > "$state_path" 2>/dev/null || true

  # append replay event
  replay_event=$(jq -n \
    --arg type "agent_stop" \
    --arg agent_id "$agent_id" \
    --arg agent_type "$agent_type" \
    --arg session_id "$session_id" \
    --arg status "$status_val" \
    --arg ts "$now_iso" \
    '{type:$type,agentId:$agent_id,agentType:$agent_type,sessionId:$session_id,status:$status,timestamp:$ts}')
  append_replay "$state_dir" "$session_id" "$replay_event"

  running=$(printf '%s' "$state" | jq '[.agents[] | select(.status == "running")] | length' 2>/dev/null || printf '0')
  succeeded_word=$([[ "$succeeded" == "true" ]] && printf 'completed' || printf 'failed')

  jq -n \
    --arg agent_type "$agent_type" \
    --arg agent_id "$agent_id" \
    --arg word "$succeeded_word" \
    --argjson count "$running" \
    '{continue:true,hookSpecificOutput:{
      hookEventName:"SubagentStop",
      additionalContext:("Agent " + $agent_type + " " + $word + " (" + $agent_id + ")"),
      agent_count:$count
    }}'
fi
