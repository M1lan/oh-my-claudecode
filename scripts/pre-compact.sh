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

# read active mode states from .omc/state/
# params: state_dir
# prints JSON object with active mode data
read_mode_states() {
  local state_dir=$1
  local -A mode_config=(
    [autopilot]='autopilot-state.json'
    [ralph]='ralph-state.json'
    [ultrawork]='ultrawork-state.json'
    [swarm]='swarm-summary.json'
    [ultrapilot]='ultrapilot-state.json'
    [ecomode]='ecomode-state.json'
    [pipeline]='pipeline-state.json'
    [ultraqa]='ultraqa-state.json'
  )

  local modes_json='{'
  local first=true

  for mode in autopilot ralph ultrawork swarm ultrapilot ecomode pipeline ultraqa; do
    local file="${mode_config[$mode]}"
    local fpath="${state_dir}/${file}"
    [[ ! -f "$fpath" ]] && continue

    local state active
    state=$(jq '.' < "$fpath" 2>/dev/null || true)
    [[ -z "${state:-}" ]] && continue
    active=$(printf '%s' "$state" | jq -r '.active // false' 2>/dev/null || printf 'false')
    [[ "$active" != "true" ]] && continue

    local extracted
    case "$mode" in
      autopilot)
        extracted=$(printf '%s' "$state" | jq -c '{phase:(.phase // "unknown"),originalIdea:(.originalIdea // "")}' 2>/dev/null || true) ;;
      ralph)
        extracted=$(printf '%s' "$state" | jq -c '{iteration:(.iteration // 0),prompt:(.originalPrompt // .prompt // "")}' 2>/dev/null || true) ;;
      ultrawork)
        extracted=$(printf '%s' "$state" | jq -c '{original_prompt:(.original_prompt // .prompt // "")}' 2>/dev/null || true) ;;
      swarm)
        extracted=$(printf '%s' "$state" | jq -c '{session_id:(.session_id // "active"),task_count:(.task_count // 0)}' 2>/dev/null || true) ;;
      ultrapilot)
        extracted=$(printf '%s' "$state" | jq -c '{session_id:(.session_id // ""),worker_count:(.worker_count // 0)}' 2>/dev/null || true) ;;
      ecomode)
        extracted=$(printf '%s' "$state" | jq -c '{original_prompt:(.original_prompt // .prompt // "")}' 2>/dev/null || true) ;;
      pipeline)
        extracted=$(printf '%s' "$state" | jq -c '{preset:(.preset // "custom"),current_stage:(.current_stage // 0)}' 2>/dev/null || true) ;;
      ultraqa)
        extracted=$(printf '%s' "$state" | jq -c '{cycle:(.cycle // 0),prompt:(.original_prompt // .prompt // "")}' 2>/dev/null || true) ;;
    esac

    [[ -z "${extracted:-}" ]] && continue
    [[ "$first" == "false" ]] && modes_json+=','
    modes_json+="\"${mode}\":${extracted}"
    first=false
  done

  modes_json+='}'
  printf '%s' "$modes_json"
}

# read todo counts from .claude/todos.json or .omc/state/todos.json
# params: directory
# prints JSON {pending,in_progress,completed}
read_todos() {
  local dir=$1
  local -a paths=("${dir}/.claude/todos.json" "${dir}/.omc/state/todos.json")

  for todo_path in "${paths[@]}"; do
    [[ ! -f "$todo_path" ]] && continue
    local result
    result=$(jq -c '
      if type == "array" then
        {
          pending: ([.[] | select(.status == "pending")] | length),
          in_progress: ([.[] | select(.status == "in_progress")] | length),
          completed: ([.[] | select(.status == "completed")] | length)
        }
      else {pending:0,in_progress:0,completed:0}
      end
    ' < "$todo_path" 2>/dev/null || true)
    [[ -n "${result:-}" ]] && printf '%s' "$result" && return 0
  done

  printf '{"pending":0,"in_progress":0,"completed":0}'
}

# query SQLite jobs.db for active and recent jobs
# params: db_path
# prints JSON {active:[...],recent:[...],stats:{...}}
read_jobs_db() {
  local db_path=$1

  if ! command -v sqlite3 > /dev/null 2>&1 || [[ ! -f "$db_path" ]]; then
    printf '{"active":[],"recent":[],"stats":null}'
    return 0
  fi

  local now_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  local five_min_ago=$(( now_ms - 300000 ))

  local active_json recent_json stats_json

  # active jobs
  active_json=$(sqlite3 -json "$db_path" \
    "SELECT jobId,provider,model,agentRole,spawnedAt FROM jobs WHERE status='running' OR status='spawned'" \
    2>/dev/null || printf '[]')
  [[ -z "${active_json:-}" ]] && active_json='[]'

  # recent completed/failed jobs (last 5 minutes)
  recent_json=$(sqlite3 -json "$db_path" \
    "SELECT jobId,provider,status,agentRole,completedAt FROM jobs WHERE (status='completed' OR status='failed') AND CAST(completedAt AS INTEGER) > ${five_min_ago} LIMIT 10" \
    2>/dev/null || printf '[]')
  [[ -z "${recent_json:-}" ]] && recent_json='[]'

  # stats
  stats_json=$(sqlite3 -json "$db_path" \
    "SELECT COUNT(*) as total, SUM(CASE WHEN status='running' OR status='spawned' THEN 1 ELSE 0 END) as active, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed, SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed FROM jobs" \
    2>/dev/null || printf 'null')
  if [[ -n "${stats_json:-}" && "$stats_json" != 'null' && "$stats_json" != '[]' ]]; then
    stats_json=$(printf '%s' "$stats_json" | jq '.[0] // null' 2>/dev/null || printf 'null')
  else
    stats_json='null'
  fi

  jq -n \
    --argjson active "$active_json" \
    --argjson recent "$recent_json" \
    --argjson stats "$stats_json" \
    '{active:$active,recent:$recent,stats:$stats}'
}

# export wisdom from notepads
# params: directory
# prints markdown string to stdout
export_wisdom() {
  local dir=$1
  local notepads_dir="${dir}/.omc/notepads"
  [[ ! -d "$notepads_dir" ]] && return 0

  local -a wisdom_files=('learnings.md' 'decisions.md' 'issues.md' 'problems.md')
  local wisdom_parts=()

  for plan_dir in "${notepads_dir}"/*/; do
    [[ ! -d "$plan_dir" ]] && continue
    local plan_name="${plan_dir%/}"
    plan_name="${plan_name##*/}"
    for wf in "${wisdom_files[@]}"; do
      local wpath="${plan_dir}${wf}"
      [[ ! -f "$wpath" ]] && continue
      local content
      content=$(< "$wpath" 2>/dev/null | $SED '/^[[:space:]]*$/d' || true)
      [[ -z "${content:-}" ]] && continue
      wisdom_parts+=("### ${plan_name}/${wf}"$'\n'"${content}")
    done
  done

  if (( ${#wisdom_parts[@]} > 0 )); then
    printf '## Plan Wisdom\n\n'
    local part
    for part in "${wisdom_parts[@]}"; do
      printf '%s\n\n' "$part"
    done
  fi
}

# format checkpoint as system message
# params: checkpoint_json wisdom_str
format_system_message() {
  local checkpoint=$1 wisdom=${2:-}

  local now_iso trigger active_modes todo_summary jobs_info

  now_iso=$(printf '%s' "$checkpoint" | jq -r '.created_at' 2>/dev/null || printf '')
  trigger=$(printf '%s' "$checkpoint" | jq -r '.trigger' 2>/dev/null || printf 'auto')
  active_modes=$(printf '%s' "$checkpoint" | jq -r '.active_modes' 2>/dev/null || printf '{}')
  todo_summary=$(printf '%s' "$checkpoint" | jq -r '.todo_summary' 2>/dev/null || printf '{}')
  jobs_info=$(printf '%s' "$checkpoint" | jq -r '.background_jobs' 2>/dev/null || printf 'null')

  local msg="# PreCompact Checkpoint

Created: ${now_iso}
Trigger: ${trigger}
"

  # active modes section
  local mode_count
  mode_count=$(printf '%s' "$active_modes" | jq 'keys | length' 2>/dev/null || printf '0')
  if (( mode_count > 0 )); then
    msg+="
## Active Modes
"
    local ap ralph uw swarm up eco pipe qa
    ap=$(printf '%s' "$active_modes" | jq -c '.autopilot // null' 2>/dev/null || printf 'null')
    ralph=$(printf '%s' "$active_modes" | jq -c '.ralph // null' 2>/dev/null || printf 'null')
    uw=$(printf '%s' "$active_modes" | jq -c '.ultrawork // null' 2>/dev/null || printf 'null')
    swarm=$(printf '%s' "$active_modes" | jq -c '.swarm // null' 2>/dev/null || printf 'null')
    up=$(printf '%s' "$active_modes" | jq -c '.ultrapilot // null' 2>/dev/null || printf 'null')
    eco=$(printf '%s' "$active_modes" | jq -c '.ecomode // null' 2>/dev/null || printf 'null')
    pipe=$(printf '%s' "$active_modes" | jq -c '.pipeline // null' 2>/dev/null || printf 'null')
    qa=$(printf '%s' "$active_modes" | jq -c '.ultraqa // null' 2>/dev/null || printf 'null')

    [[ "$ap" != "null" ]] && msg+="
- **Autopilot** (Phase: $(printf '%s' "$ap" | jq -r '.phase'))
  Original Idea: $(printf '%s' "$ap" | jq -r '.originalIdea')"
    [[ "$ralph" != "null" ]] && msg+="
- **Ralph** (Iteration: $(printf '%s' "$ralph" | jq -r '.iteration'))
  Prompt: $(printf '%s' "$ralph" | jq -r '.prompt')"
    [[ "$uw" != "null" ]] && msg+="
- **Ultrawork**
  Prompt: $(printf '%s' "$uw" | jq -r '.original_prompt')"
    [[ "$swarm" != "null" ]] && msg+="
- **Swarm** (Session: $(printf '%s' "$swarm" | jq -r '.session_id'), Tasks: $(printf '%s' "$swarm" | jq -r '.task_count'))"
    [[ "$up" != "null" ]] && msg+="
- **Ultrapilot** (Workers: $(printf '%s' "$up" | jq -r '.worker_count'))"
    [[ "$eco" != "null" ]] && msg+="
- **Ecomode**
  Prompt: $(printf '%s' "$eco" | jq -r '.original_prompt | .[0:50]')..."
    [[ "$pipe" != "null" ]] && msg+="
- **Pipeline** (Preset: $(printf '%s' "$pipe" | jq -r '.preset'), Stage: $(printf '%s' "$pipe" | jq -r '.current_stage'))"
    [[ "$qa" != "null" ]] && msg+="
- **UltraQA** (Cycle: $(printf '%s' "$qa" | jq -r '.cycle'))
  Prompt: $(printf '%s' "$qa" | jq -r '.prompt')"
    msg+=$'\n'
  fi

  # todo summary
  local total pending in_progress completed_count
  pending=$(printf '%s' "$todo_summary" | jq -r '.pending // 0' 2>/dev/null || printf '0')
  in_progress=$(printf '%s' "$todo_summary" | jq -r '.in_progress // 0' 2>/dev/null || printf '0')
  completed_count=$(printf '%s' "$todo_summary" | jq -r '.completed // 0' 2>/dev/null || printf '0')
  total=$(( pending + in_progress + completed_count ))

  if (( total > 0 )); then
    msg+="
## TODO Summary

- Pending: ${pending}
- In Progress: ${in_progress}
- Completed: ${completed_count}
"
  fi

  # background jobs
  if [[ "$jobs_info" != "null" && -n "${jobs_info:-}" ]]; then
    local active_jobs recent_jobs stats_obj
    active_jobs=$(printf '%s' "$jobs_info" | jq -c '.active // []' 2>/dev/null || printf '[]')
    recent_jobs=$(printf '%s' "$jobs_info" | jq -c '.recent // []' 2>/dev/null || printf '[]')
    stats_obj=$(printf '%s' "$jobs_info" | jq -c '.stats // null' 2>/dev/null || printf 'null')

    local active_count recent_count
    active_count=$(printf '%s' "$active_jobs" | jq 'length' 2>/dev/null || printf '0')
    recent_count=$(printf '%s' "$recent_jobs" | jq 'length' 2>/dev/null || printf '0')

    if (( active_count > 0 || recent_count > 0 )); then
      msg+="
## Background Jobs (Codex/Gemini)
"
      if (( active_count > 0 )); then
        msg+="
### Currently Running"
        local now_s
        now_s=$(date +%s 2>/dev/null || printf '0')
        while IFS= read -r job; do
          local jid jprov jmod jrole jspawned age
          jid=$(printf '%s' "$job" | jq -r '.jobId // .job_id' 2>/dev/null || printf 'unknown')
          jprov=$(printf '%s' "$job" | jq -r '.provider' 2>/dev/null || printf '?')
          jmod=$(printf '%s' "$job" | jq -r '.model' 2>/dev/null || printf '?')
          jrole=$(printf '%s' "$job" | jq -r '.agentRole // .agent_role' 2>/dev/null || printf '?')
          jspawned=$(printf '%s' "$job" | jq -r '.spawnedAt // .spawned_at // ""' 2>/dev/null || true)
          age=0
          if [[ -n "$jspawned" ]]; then
            local spawn_s
            spawn_s=$(date -d "$jspawned" +%s 2>/dev/null || printf '0')
            (( spawn_s > 0 )) && age=$(( now_s - spawn_s ))
          fi
          msg+="
- **${jid}** ${jprov}/${jmod} (${jrole}) - ${age}s ago"
        done < <(printf '%s' "$active_jobs" | jq -c '.[]' 2>/dev/null || true)
        msg+=$'\n'
      fi

      if (( recent_count > 0 )); then
        msg+="
### Recently Completed"
        while IFS= read -r job; do
          local jid jstat jprov jrole icon
          jid=$(printf '%s' "$job" | jq -r '.jobId // .job_id' 2>/dev/null || printf 'unknown')
          jstat=$(printf '%s' "$job" | jq -r '.status' 2>/dev/null || printf '?')
          jprov=$(printf '%s' "$job" | jq -r '.provider' 2>/dev/null || printf '?')
          jrole=$(printf '%s' "$job" | jq -r '.agentRole // .agent_role' 2>/dev/null || printf '?')
          [[ "$jstat" == "completed" ]] && icon='OK' || icon='FAIL'
          msg+="
- **${jid}** [${icon}] ${jprov} (${jrole})"
        done < <(printf '%s' "$recent_jobs" | jq -c '.[]' 2>/dev/null || true)
        msg+=$'\n'
      fi

      if [[ "$stats_obj" != "null" ]]; then
        local s_active s_completed s_failed s_total
        s_active=$(printf '%s' "$stats_obj" | jq -r '.active // 0' 2>/dev/null || printf '0')
        s_completed=$(printf '%s' "$stats_obj" | jq -r '.completed // 0' 2>/dev/null || printf '0')
        s_failed=$(printf '%s' "$stats_obj" | jq -r '.failed // 0' 2>/dev/null || printf '0')
        s_total=$(printf '%s' "$stats_obj" | jq -r '.total // 0' 2>/dev/null || printf '0')
        msg+="
**Job Stats:** ${s_active} active, ${s_completed} completed, ${s_failed} failed (${s_total} total)
"
      fi
    fi
  fi

  # wisdom
  if [[ -n "${wisdom:-}" ]]; then
    msg+="
## Wisdom

Plan wisdom has been preserved in checkpoint.
"
  fi

  msg+="
---
**Note:** This checkpoint preserves critical state before compaction.
Review active modes to ensure continuity after compaction."

  printf '%s' "$msg"
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '{"continue":true}\n' && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
[[ -z "$cwd" ]] && cwd="$PWD"
trigger=$(printf '%s' "$input" | jq -r '.trigger // "auto"' 2>/dev/null || printf 'auto')
[[ "$trigger" != "manual" ]] && trigger='auto'

state_dir="${cwd}/.omc/state"
checkpoint_dir="${state_dir}/checkpoints"
jobs_db="${state_dir}/jobs.db"

mkdir -p "$checkpoint_dir" 2>/dev/null || true

# gather all state
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u)
active_modes=$(read_mode_states "$state_dir" 2>/dev/null || printf '{}')
todo_summary=$(read_todos "$cwd" 2>/dev/null || printf '{"pending":0,"in_progress":0,"completed":0}')
jobs_info=$(read_jobs_db "$jobs_db" 2>/dev/null || printf '{"active":[],"recent":[],"stats":null}')
wisdom=$(export_wisdom "$cwd" 2>/dev/null || true)

# create checkpoint object
checkpoint=$(jq -n \
  --arg created_at "$now_iso" \
  --arg trigger "$trigger" \
  --argjson active_modes "$active_modes" \
  --argjson todo_summary "$todo_summary" \
  --argjson background_jobs "$jobs_info" \
  --argjson wisdom_exported "$([ -n "${wisdom:-}" ] && printf 'true' || printf 'false')" \
  '{
    created_at: $created_at,
    trigger: $trigger,
    active_modes: $active_modes,
    todo_summary: $todo_summary,
    background_jobs: $background_jobs,
    wisdom_exported: $wisdom_exported
  }' 2>/dev/null || printf '{}')

# save checkpoint to disk
ts="${now_iso//[:.]/-}"
checkpoint_file="${checkpoint_dir}/checkpoint-${ts}.json"
printf '%s\n' "$checkpoint" > "$checkpoint_file" 2>/dev/null || true

# save wisdom separately if present
if [[ -n "${wisdom:-}" ]]; then
  printf '%s\n' "$wisdom" > "${checkpoint_dir}/wisdom-${ts}.md" 2>/dev/null || true
fi

# format system message
system_message=$(format_system_message "$checkpoint" "$wisdom" 2>/dev/null || true)

if [[ -z "${system_message:-}" ]]; then
  printf '{"continue":true}\n'
  exit 0
fi

jq -n --arg msg "$system_message" '{"continue":true,"systemMessage":$msg}'
