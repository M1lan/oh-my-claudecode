#!/usr/bin/env bash
# OMC Persistent Mode Hook (Bash)
# Minimal continuation enforcer for all OMC modes.
# Supported modes: ralph, autopilot, ultrapilot, swarm, ultrawork, ecomode, ultraqa, pipeline

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALLOW='{"continue":true,"suppressOutput":true}'

allow() { printf '%s\n' "$ALLOW"; exit 0; }
block() { printf '%s\n' "{\"decision\":\"block\",\"reason\":$(printf '%s' "$1" | jq -Rs .)}"; exit 0; }

# ISO timestamp → epoch seconds (macOS-compatible)
iso_to_epoch() {
  python3 -c "
import sys, datetime
ts = sys.argv[1].replace('Z','+00:00')
print(int(datetime.datetime.fromisoformat(ts).timestamp()))
" "$1" 2>/dev/null || echo 0
}

# is_stale <state_json>  → returns 0 (true) if stale, 1 if fresh
is_stale() {
  local state_json="$1"
  local lc sa epoch_lc epoch_sa most_recent now
  now=$(date +%s)
  lc=$(printf '%s' "$state_json" | jq -r '.last_checked_at // empty')
  sa=$(printf '%s' "$state_json" | jq -r '.started_at // empty')
  epoch_lc=$( [[ -n "$lc" ]] && iso_to_epoch "$lc" || echo 0 )
  epoch_sa=$( [[ -n "$sa" ]] && iso_to_epoch "$sa" || echo 0 )
  most_recent=$(( epoch_lc > epoch_sa ? epoch_lc : epoch_sa ))
  [[ $most_recent -eq 0 ]] && return 0
  (( (now - most_recent) > 7200 ))
}

# read_state <state_dir> <global_dir> <filename> <session>
# Sets STATE_JSON, STATE_PATH, STATE_IS_GLOBAL
read_state() {
  local state_dir="$1" global_dir="$2" filename="$3" session="$4"
  STATE_IS_GLOBAL=false
  if [[ -n "$session" && "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$ ]]; then
    STATE_PATH="${state_dir}/sessions/${session}/${filename}"
    STATE_JSON=$(jq -r '.' "$STATE_PATH" 2>/dev/null || echo 'null')
    return
  fi
  local lp="${state_dir}/${filename}" gp="${global_dir}/${filename}"
  if [[ -f "$lp" ]]; then
    STATE_PATH="$lp"
    STATE_JSON=$(jq -r '.' "$lp" 2>/dev/null || echo 'null')
  elif [[ -f "$gp" ]]; then
    STATE_PATH="$gp"
    STATE_IS_GLOBAL=true
    STATE_JSON=$(jq -r '.' "$gp" 2>/dev/null || echo 'null')
  else
    STATE_PATH="$lp"
    STATE_JSON='null'
  fi
}

write_state() {
  local path="$1" json="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$json" > "$path"
}

# read_tool_error <state_dir> → prints JSON or nothing
read_tool_error() {
  local state_dir="$1"
  local path="${state_dir}/last-tool-error.json"
  [[ -f "$path" ]] || return
  local ts
  ts=$(jq -r '.timestamp // empty' "$path" 2>/dev/null || true)
  [[ -z "$ts" ]] && return
  local epoch age
  epoch=$(iso_to_epoch "$ts")
  age=$(( $(date +%s) - epoch ))
  (( age > 60 )) && return
  jq -r '.' "$path" 2>/dev/null
}

# get_error_guidance <err_json> → prints guidance string or nothing
get_error_guidance() {
  local err_json="$1"
  [[ -z "$err_json" || "$err_json" == 'null' ]] && return
  local rc tn em
  rc=$(printf '%s' "$err_json" | jq -r '.retry_count // 1')
  tn=$(printf '%s' "$err_json" | jq -r '.tool_name // "unknown"')
  em=$(printf '%s' "$err_json" | jq -r '.error // "Unknown error"')
  if (( rc >= 5 )); then
    printf '[TOOL ERROR - ALTERNATIVE APPROACH NEEDED]\nThe "%s" operation has failed %d times.\n\nSTOP RETRYING THE SAME APPROACH. Instead:\n1. Try a completely different command or approach\n2. Check if the environment/dependencies are correct\n3. Consider breaking down the task differently\n4. If stuck, ask the user for guidance\n\n' "$tn" "$rc"
  else
    printf '[TOOL ERROR - RETRY REQUIRED]\nThe previous "%s" operation failed.\n\nError: %s\n\nREQUIRED ACTIONS:\n1. Analyze why the command failed\n2. Fix the issue (wrong path? permission? syntax? missing dependency?)\n3. RETRY the operation with corrected parameters\n4. Continue with your original task after success\n\nDo NOT skip this step. Do NOT move on without fixing the error.\n\n' "$tn" "$em"
  fi
}

# session_matches <state_json> <session> <has_valid>
session_matches() {
  local state_json="$1" session="$2" has_valid="$3"
  local s
  s=$(printf '%s' "$state_json" | jq -r '.session_id // empty')
  if [[ "$has_valid" == true ]]; then
    [[ "$s" == "$session" ]]
  else
    [[ -z "$s" || "$s" == "$session" ]]
  fi
}

# is_for_project <state_json> <current_dir> <is_global>
is_for_project() {
  local state_json="$1" current_dir="$2" is_global="$3"
  local pp
  pp=$(printf '%s' "$state_json" | jq -r '.project_path // empty')
  if [[ -z "$pp" ]]; then
    [[ "$is_global" != true ]]
    return
  fi
  [[ "$(cd "$pp" 2>/dev/null && pwd)" == "$(cd "$current_dir" 2>/dev/null && pwd)" ]]
}

count_incomplete_tasks() {
  local session="$1"
  [[ -z "$session" || ! "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$ ]] && echo 0 && return
  local cfg_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
  local task_dir="${cfg_dir}/tasks/${session}"
  [[ -d "$task_dir" ]] || { echo 0; return; }
  find "$task_dir" -maxdepth 1 -name '*.json' ! -name '.lock' -print0 2>/dev/null \
    | xargs -0 -I{} jq -r 'select(.status=="pending" or .status=="in_progress") | .status' {} 2>/dev/null \
    | wc -l | tr -d ' '
}

count_incomplete_todos() {
  local session="$1" project_dir="$2"
  local count=0

  # Session-specific todos
  if [[ -n "$session" && "$session" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$ ]]; then
    local session_todo="${HOME}/.claude/todos/${session}.json"
    if [[ -f "$session_todo" ]]; then
      local n
      n=$(jq '[if type=="array" then .[] elif .todos and (.todos|type)=="array" then .todos[] else empty end | select(.status != "completed" and .status != "cancelled")] | length' "$session_todo" 2>/dev/null || echo 0)
      count=$(( count + n ))
    fi
  fi

  # Project-local todos
  for todo_path in "${project_dir}/.omc/todos.json" "${project_dir}/.claude/todos.json"; do
    if [[ -f "$todo_path" ]]; then
      local n
      n=$(jq '[if type=="array" then .[] elif .todos and (.todos|type)=="array" then .todos[] else empty end | select(.status != "completed" and .status != "cancelled")] | length' "$todo_path" 2>/dev/null || echo 0)
      count=$(( count + n ))
    fi
  done

  echo "$count"
}

main() {
  local input
  input=$(timeout 5 cat 2>/dev/null || true)

  local data='{}'
  if [[ -n "$input" ]]; then
    data=$(printf '%s' "$input" | jq -r '.' 2>/dev/null || echo '{}')
  fi

  local directory session_id_raw session_id has_valid_session
  directory=$(printf '%s' "$data" | jq -r '.cwd // .directory // empty')
  [[ -z "$directory" ]] && directory="$(pwd)"

  session_id_raw=$(printf '%s' "$data" | jq -r '.sessionId // .session_id // .sessionid // empty')
  if [[ -n "$session_id_raw" && "$session_id_raw" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$ ]]; then
    session_id="$session_id_raw"
    has_valid_session=true
  else
    session_id=""
    has_valid_session=false
  fi

  local state_dir="${directory}/.omc/state"
  local global_state_dir="${HOME}/.omc/state"

  # Context limit check → allow
  local stop_reason end_turn_reason
  stop_reason=$(printf '%s' "$data" | jq -r '.stop_reason // .stopReason // empty' | tr '[:upper:]' '[:lower:]')
  end_turn_reason=$(printf '%s' "$data" | jq -r '.end_turn_reason // .endTurnReason // empty' | tr '[:upper:]' '[:lower:]')
  local context_patterns="context_limit context_window context_exceeded context_full max_context token_limit max_tokens conversation_too_long input_too_long"
  for p in $context_patterns; do
    if [[ "$stop_reason" == *"$p"* || "$end_turn_reason" == *"$p"* ]]; then
      allow
    fi
  done

  # User abort check → allow
  local user_requested
  user_requested=$(printf '%s' "$data" | jq -r '.user_requested // .userRequested // false')
  if [[ "$user_requested" == "true" ]]; then allow; fi
  case "$stop_reason" in
    aborted|abort|cancel|interrupt) allow ;;
  esac
  for p in user_cancel user_interrupt ctrl_c manual_stop; do
    [[ "$stop_reason" == *"$p"* ]] && allow
  done

  # Read all mode states
  local ralph_json ralph_path ralph_global
  read_state "$state_dir" "$global_state_dir" "ralph-state.json" "$session_id"
  ralph_json="$STATE_JSON"; ralph_path="$STATE_PATH"; ralph_global="$STATE_IS_GLOBAL"

  local autopilot_json autopilot_path autopilot_global
  read_state "$state_dir" "$global_state_dir" "autopilot-state.json" "$session_id"
  autopilot_json="$STATE_JSON"; autopilot_path="$STATE_PATH"; autopilot_global="$STATE_IS_GLOBAL"

  local ultrapilot_json ultrapilot_path ultrapilot_global
  read_state "$state_dir" "$global_state_dir" "ultrapilot-state.json" "$session_id"
  ultrapilot_json="$STATE_JSON"; ultrapilot_path="$STATE_PATH"; ultrapilot_global="$STATE_IS_GLOBAL"

  local ultrawork_json ultrawork_path ultrawork_global
  read_state "$state_dir" "$global_state_dir" "ultrawork-state.json" "$session_id"
  ultrawork_json="$STATE_JSON"; ultrawork_path="$STATE_PATH"; ultrawork_global="$STATE_IS_GLOBAL"

  local ecomode_json ecomode_path ecomode_global
  read_state "$state_dir" "$global_state_dir" "ecomode-state.json" "$session_id"
  ecomode_json="$STATE_JSON"; ecomode_path="$STATE_PATH"; ecomode_global="$STATE_IS_GLOBAL"

  local ultraqa_json ultraqa_path ultraqa_global
  read_state "$state_dir" "$global_state_dir" "ultraqa-state.json" "$session_id"
  ultraqa_json="$STATE_JSON"; ultraqa_path="$STATE_PATH"; ultraqa_global="$STATE_IS_GLOBAL"

  local pipeline_json pipeline_path pipeline_global
  read_state "$state_dir" "$global_state_dir" "pipeline-state.json" "$session_id"
  pipeline_json="$STATE_JSON"; pipeline_path="$STATE_PATH"; pipeline_global="$STATE_IS_GLOBAL"

  # Swarm: marker file + summary json
  local swarm_marker=false swarm_json='null'
  [[ -f "${state_dir}/swarm-active.marker" ]] && swarm_marker=true
  if [[ -f "${state_dir}/swarm-summary.json" ]]; then
    swarm_json=$(jq -r '.' "${state_dir}/swarm-summary.json" 2>/dev/null || echo 'null')
  fi

  # Count incomplete items
  local task_count todo_count total_incomplete
  task_count=$(count_incomplete_tasks "$session_id")
  todo_count=$(count_incomplete_todos "$session_id" "$directory")
  total_incomplete=$(( task_count + todo_count ))

  local tool_err_json err_guidance reason now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Priority 1: Ralph
  local ralph_active
  ralph_active=$(printf '%s' "$ralph_json" | jq -r '.active // false')
  if [[ "$ralph_active" == "true" && "$ralph_json" != 'null' ]] \
     && ! is_stale "$ralph_json" \
     && session_matches "$ralph_json" "$session_id" "$has_valid_session" \
     && is_for_project "$ralph_json" "$directory" "$ralph_global"; then
    local iteration max_iter
    iteration=$(printf '%s' "$ralph_json" | jq -r '.iteration // 1')
    max_iter=$(printf '%s' "$ralph_json" | jq -r '.max_iterations // 100')
    if (( iteration < max_iter )); then
      tool_err_json=$(read_tool_error "$state_dir" || true)
      err_guidance=$(get_error_guidance "$tool_err_json")
      local new_iter=$(( iteration + 1 ))
      local prompt
      prompt=$(printf '%s' "$ralph_json" | jq -r '.prompt // empty')
      ralph_json=$(printf '%s' "$ralph_json" | jq --argjson i "$new_iter" --arg ts "$now_iso" '.iteration = $i | .last_checked_at = $ts')
      write_state "$ralph_path" "$ralph_json"
      reason="[RALPH LOOP - ITERATION ${new_iter}/${max_iter}] Work is NOT done. Continue working.
When FULLY complete (after Architect verification), run /oh-my-claudecode:cancel to cleanly exit ralph mode and clean up all state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
      [[ -n "$prompt" ]] && reason="${reason}
Task: ${prompt}"
      [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
      block "$reason"
    fi
  fi

  # Priority 2: Autopilot
  local autopilot_active
  autopilot_active=$(printf '%s' "$autopilot_json" | jq -r '.active // false')
  if [[ "$autopilot_active" == "true" && "$autopilot_json" != 'null' ]] \
     && ! is_stale "$autopilot_json" \
     && session_matches "$autopilot_json" "$session_id" "$has_valid_session" \
     && is_for_project "$autopilot_json" "$directory" "$autopilot_global"; then
    local phase
    phase=$(printf '%s' "$autopilot_json" | jq -r '.phase // "unspecified"')
    if [[ "$phase" != "complete" ]]; then
      local new_count
      new_count=$(( $(printf '%s' "$autopilot_json" | jq -r '.reinforcement_count // 0') + 1 ))
      if (( new_count <= 20 )); then
        tool_err_json=$(read_tool_error "$state_dir" || true)
        err_guidance=$(get_error_guidance "$tool_err_json")
        autopilot_json=$(printf '%s' "$autopilot_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
        write_state "$autopilot_path" "$autopilot_json"
        reason="[AUTOPILOT - Phase: ${phase}] Autopilot not complete. Continue working. When all phases are complete, run /oh-my-claudecode:cancel to cleanly exit and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
        [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
        block "$reason"
      fi
    fi
  fi

  # Priority 3: Ultrapilot
  local ultrapilot_active
  ultrapilot_active=$(printf '%s' "$ultrapilot_json" | jq -r '.active // false')
  if [[ "$ultrapilot_active" == "true" && "$ultrapilot_json" != 'null' ]] \
     && ! is_stale "$ultrapilot_json" \
     && session_matches "$ultrapilot_json" "$session_id" "$has_valid_session" \
     && is_for_project "$ultrapilot_json" "$directory" "$ultrapilot_global"; then
    local incomplete
    incomplete=$(printf '%s' "$ultrapilot_json" | jq '[.workers // [] | .[] | select(.status != "complete" and .status != "failed")] | length')
    if (( incomplete > 0 )); then
      local new_count
      new_count=$(( $(printf '%s' "$ultrapilot_json" | jq -r '.reinforcement_count // 0') + 1 ))
      if (( new_count <= 20 )); then
        tool_err_json=$(read_tool_error "$state_dir" || true)
        err_guidance=$(get_error_guidance "$tool_err_json")
        ultrapilot_json=$(printf '%s' "$ultrapilot_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
        write_state "$ultrapilot_path" "$ultrapilot_json"
        reason="[ULTRAPILOT] ${incomplete} workers still running. Continue working. When all workers complete, run /oh-my-claudecode:cancel to cleanly exit and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
        [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
        block "$reason"
      fi
    fi
  fi

  # Priority 4: Swarm
  local swarm_active
  swarm_active=$(printf '%s' "$swarm_json" | jq -r '.active // false')
  if [[ "$swarm_marker" == "true" && "$swarm_active" == "true" && "$swarm_json" != 'null' ]] \
     && ! is_stale "$swarm_json" \
     && is_for_project "$swarm_json" "$directory" "false"; then
    local pending
    pending=$(printf '%s' "$swarm_json" | jq '(.tasks_pending // 0) + (.tasks_claimed // 0)')
    if (( pending > 0 )); then
      local new_count
      new_count=$(( $(printf '%s' "$swarm_json" | jq -r '.reinforcement_count // 0') + 1 ))
      if (( new_count <= 15 )); then
        tool_err_json=$(read_tool_error "$state_dir" || true)
        err_guidance=$(get_error_guidance "$tool_err_json")
        swarm_json=$(printf '%s' "$swarm_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
        write_state "${state_dir}/swarm-summary.json" "$swarm_json"
        reason="[SWARM ACTIVE] ${pending} tasks remain. Continue working. When all tasks are done, run /oh-my-claudecode:cancel to cleanly exit and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
        [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
        block "$reason"
      fi
    fi
  fi

  # Priority 5: Pipeline
  local pipeline_active
  pipeline_active=$(printf '%s' "$pipeline_json" | jq -r '.active // false')
  if [[ "$pipeline_active" == "true" && "$pipeline_json" != 'null' ]] \
     && ! is_stale "$pipeline_json" \
     && session_matches "$pipeline_json" "$session_id" "$has_valid_session" \
     && is_for_project "$pipeline_json" "$directory" "$pipeline_global"; then
    local current_stage total_stages
    current_stage=$(printf '%s' "$pipeline_json" | jq -r '.current_stage // 0')
    total_stages=$(printf '%s' "$pipeline_json" | jq -r '(.stages // []) | length')
    if (( current_stage < total_stages )); then
      local new_count
      new_count=$(( $(printf '%s' "$pipeline_json" | jq -r '.reinforcement_count // 0') + 1 ))
      if (( new_count <= 15 )); then
        tool_err_json=$(read_tool_error "$state_dir" || true)
        err_guidance=$(get_error_guidance "$tool_err_json")
        pipeline_json=$(printf '%s' "$pipeline_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
        write_state "$pipeline_path" "$pipeline_json"
        local stage_disp=$(( current_stage + 1 ))
        reason="[PIPELINE - Stage ${stage_disp}/${total_stages}] Pipeline not complete. Continue working. When all stages complete, run /oh-my-claudecode:cancel to cleanly exit and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
        [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
        block "$reason"
      fi
    fi
  fi

  # Priority 6: UltraQA
  local ultraqa_active
  ultraqa_active=$(printf '%s' "$ultraqa_json" | jq -r '.active // false')
  if [[ "$ultraqa_active" == "true" && "$ultraqa_json" != 'null' ]] \
     && ! is_stale "$ultraqa_json" \
     && session_matches "$ultraqa_json" "$session_id" "$has_valid_session" \
     && is_for_project "$ultraqa_json" "$directory" "$ultraqa_global"; then
    local cycle max_cycles all_passing
    cycle=$(printf '%s' "$ultraqa_json" | jq -r '.cycle // 1')
    max_cycles=$(printf '%s' "$ultraqa_json" | jq -r '.max_cycles // 10')
    all_passing=$(printf '%s' "$ultraqa_json" | jq -r '.all_passing // false')
    if (( cycle < max_cycles )) && [[ "$all_passing" != "true" ]]; then
      tool_err_json=$(read_tool_error "$state_dir" || true)
      err_guidance=$(get_error_guidance "$tool_err_json")
      local new_cycle=$(( cycle + 1 ))
      ultraqa_json=$(printf '%s' "$ultraqa_json" | jq --argjson c "$new_cycle" --arg ts "$now_iso" '.cycle = $c | .last_checked_at = $ts')
      write_state "$ultraqa_path" "$ultraqa_json"
      reason="[ULTRAQA - Cycle ${new_cycle}/${max_cycles}] Tests not all passing. Continue fixing. When all tests pass, run /oh-my-claudecode:cancel to cleanly exit and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force."
      [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
      block "$reason"
    fi
  fi

  # Priority 7: Ultrawork
  local ultrawork_active
  ultrawork_active=$(printf '%s' "$ultrawork_json" | jq -r '.active // false')
  if [[ "$ultrawork_active" == "true" && "$ultrawork_json" != 'null' ]] \
     && ! is_stale "$ultrawork_json" \
     && session_matches "$ultrawork_json" "$session_id" "$has_valid_session" \
     && is_for_project "$ultrawork_json" "$directory" "$ultrawork_global"; then
    local new_count max_reinforcements
    new_count=$(( $(printf '%s' "$ultrawork_json" | jq -r '.reinforcement_count // 0') + 1 ))
    max_reinforcements=$(printf '%s' "$ultrawork_json" | jq -r '.max_reinforcements // 50')
    if (( new_count > max_reinforcements )); then
      allow
    fi
    tool_err_json=$(read_tool_error "$state_dir" || true)
    err_guidance=$(get_error_guidance "$tool_err_json")
    ultrawork_json=$(printf '%s' "$ultrawork_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
    write_state "$ultrawork_path" "$ultrawork_json"
    reason="[ULTRAWORK #${new_count}/${max_reinforcements}] Mode active."
    if (( total_incomplete > 0 )); then
      local item_type="todos"
      (( task_count > 0 )) && item_type="Tasks"
      reason="${reason} ${total_incomplete} incomplete ${item_type} remain. Continue working."
    elif (( new_count >= 3 )); then
      reason="${reason} If all work is complete, run /oh-my-claudecode:cancel to cleanly exit ultrawork mode and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force. Otherwise, continue working."
    else
      reason="${reason} Continue working - create Tasks to track your progress."
    fi
    local orig_prompt
    orig_prompt=$(printf '%s' "$ultrawork_json" | jq -r '.original_prompt // empty')
    [[ -n "$orig_prompt" ]] && reason="${reason}
Task: ${orig_prompt}"
    [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
    block "$reason"
  fi

  # Priority 8: Ecomode
  local ecomode_active
  ecomode_active=$(printf '%s' "$ecomode_json" | jq -r '.active // false')
  if [[ "$ecomode_active" == "true" && "$ecomode_json" != 'null' ]] \
     && ! is_stale "$ecomode_json" \
     && session_matches "$ecomode_json" "$session_id" "$has_valid_session" \
     && is_for_project "$ecomode_json" "$directory" "$ecomode_global"; then
    local new_count max_reinforcements
    new_count=$(( $(printf '%s' "$ecomode_json" | jq -r '.reinforcement_count // 0') + 1 ))
    max_reinforcements=$(printf '%s' "$ecomode_json" | jq -r '.max_reinforcements // 50')
    if (( new_count > max_reinforcements )); then
      allow
    fi
    tool_err_json=$(read_tool_error "$state_dir" || true)
    err_guidance=$(get_error_guidance "$tool_err_json")
    ecomode_json=$(printf '%s' "$ecomode_json" | jq --argjson c "$new_count" --arg ts "$now_iso" '.reinforcement_count = $c | .last_checked_at = $ts')
    write_state "$ecomode_path" "$ecomode_json"
    reason="[ECOMODE #${new_count}/${max_reinforcements}] Mode active."
    if (( total_incomplete > 0 )); then
      local item_type="todos"
      (( task_count > 0 )) && item_type="Tasks"
      reason="${reason} ${total_incomplete} incomplete ${item_type} remain. Continue working."
    elif (( new_count >= 3 )); then
      reason="${reason} If all work is complete, run /oh-my-claudecode:cancel to cleanly exit ecomode and clean up state files. If cancel fails, retry with /oh-my-claudecode:cancel --force. Otherwise, continue working."
    else
      reason="${reason} Continue working - create Tasks to track your progress."
    fi
    [[ -n "$err_guidance" ]] && reason="${err_guidance}${reason}"
    block "$reason"
  fi

  # No modes active
  allow
}

main || printf '%s\n' '{"continue":true,"suppressOutput":true}'
