#!/usr/bin/env bash
set -euo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude config directory (respects CLAUDE_CONFIG_DIR env var)
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

# Read stdin with timeout
input=$(timeout 5 cat 2>/dev/null || true)

# Parse stdin JSON
directory="$(printf '%s' "${input}" | jq -r '.cwd // .directory // ""' 2>/dev/null || true)"
session_id="$(printf '%s' "${input}" | jq -r '.session_id // .sessionId // ""' 2>/dev/null || true)"
[[ -z "${directory}" ]] && directory="$(pwd)"

# Helper: read JSON file safely, outputs empty string on failure
read_json_file() {
  local path="$1"
  if [[ -f "${path}" ]]; then
    jq '.' "${path}" 2>/dev/null || true
  fi
}

# Semver comparison: returns 0 (true) if $1 > $2
semver_gt() {
  local v1="$1" v2="$2"
  local IFS=.
  read -ra a <<< "$v1"
  read -ra b <<< "$v2"
  for ((i=0; i<3; i++)); do
    (( ${a[i]:-0} > ${b[i]:-0} )) && return 0
    (( ${a[i]:-0} < ${b[i]:-0} )) && return 1
  done
  return 1
}

# Semver compare for sorting: outputs -1, 0, or 1
semver_compare() {
  local v1="$1" v2="$2"
  local IFS=.
  read -ra a <<< "$v1"
  read -ra b <<< "$v2"
  for ((i=0; i<3; i++)); do
    (( ${a[i]:-0} > ${b[i]:-0} )) && echo 1 && return
    (( ${a[i]:-0} < ${b[i]:-0} )) && echo -1 && return
  done
  echo 0
}

# Output array to collect messages
messages=()

# ── 1. Version drift detection ──────────────────────────────────────────────

plugin_version=""
npm_version=""
claude_md_version=""

# Get plugin version from CLAUDE_PLUGIN_ROOT/package.json
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" && -f "${CLAUDE_PLUGIN_ROOT}/package.json" ]]; then
  plugin_version="$(jq -r '.version // ""' "${CLAUDE_PLUGIN_ROOT}/package.json" 2>/dev/null || true)"
fi

# Get npm version from ~/.claude/.omc-version.json
omc_version_file="${CONFIG_DIR}/.omc-version.json"
if [[ -f "${omc_version_file}" ]]; then
  npm_version="$(jq -r '.version // ""' "${omc_version_file}" 2>/dev/null || true)"
fi

# Get CLAUDE.md version from OMC:VERSION marker
claude_md_path="${CONFIG_DIR}/CLAUDE.md"
if [[ -f "${claude_md_path}" ]]; then
  marker_match="$(grep -oE '<!-- OMC:VERSION:[0-9]+\.[0-9]+\.[0-9]+[^ ]* -->' "${claude_md_path}" 2>/dev/null | head -1 || true)"
  if [[ -n "${marker_match}" ]]; then
    claude_md_version="${marker_match#<!-- OMC:VERSION:}"
    claude_md_version="${claude_md_version% -->}"
  else
    claude_md_version="unknown"
  fi
fi

# Detect drift and notify (deduplicated)
if [[ -n "${plugin_version}" ]]; then
  drift_parts=()
  if [[ -n "${npm_version}" && "${npm_version}" != "${plugin_version}" ]]; then
    drift_parts+=("npm package (omc CLI): ${npm_version} (expected ${plugin_version})")
  fi
  if [[ "${claude_md_version}" == "unknown" ]]; then
    drift_parts+=("CLAUDE.md instructions: unknown (needs migration) (expected ${plugin_version})")
  elif [[ -n "${claude_md_version}" && "${claude_md_version}" != "${plugin_version}" ]]; then
    drift_parts+=("CLAUDE.md instructions: ${claude_md_version} (expected ${plugin_version})")
  fi

  if [[ ${#drift_parts[@]} -gt 0 ]]; then
    drift_key="plugin:${plugin_version}-npm:${npm_version}-claude:${claude_md_version}"
    state_file="${CONFIG_DIR}/.omc/update-state.json"
    should_notify=true

    if [[ -f "${state_file}" ]]; then
      last_notified="$(jq -r '.lastNotifiedDrift // ""' "${state_file}" 2>/dev/null || true)"
      if [[ "${last_notified}" == "${drift_key}" ]]; then
        should_notify=false
      fi
    fi

    if [[ "${should_notify}" == "true" ]]; then
      mkdir -p "${CONFIG_DIR}/.omc"
      now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '{"lastNotifiedDrift":"%s","lastNotifiedAt":"%s"}\n' "${drift_key}" "${now_iso}" > "${state_file}"

      drift_msg="[OMC VERSION DRIFT DETECTED]\n\nPlugin version: ${plugin_version}\n"
      for part in "${drift_parts[@]}"; do
        drift_msg+="${part}\n"
      done
      drift_msg+="\nRun 'omc update' to sync all components."

      messages+=("<session-restore>\n\n${drift_msg}\n\n</session-restore>\n\n---\n")
    fi
  fi
fi

# ── 2. NPM update check (24h cache) ─────────────────────────────────────────

if [[ -n "${plugin_version}" ]]; then
  cache_file="${CONFIG_DIR}/.omc/update-check.json"
  cache_valid=false
  latest_version=""

  if [[ -f "${cache_file}" ]]; then
    cache_ts="$(jq -r '.timestamp // 0' "${cache_file}" 2>/dev/null || echo 0)"
    # bash integer arithmetic: compare epoch seconds (strip ms)
    cache_ts_s="${cache_ts:0:-3}"
    now_s="$(date +%s)"
    age_s=$(( now_s - ${cache_ts_s:-0} ))
    if (( age_s < 86400 )); then
      cache_valid=true
      if [[ "$(jq -r '.updateAvailable // false' "${cache_file}" 2>/dev/null || true)" == "true" ]]; then
        latest_version="$(jq -r '.latestVersion // ""' "${cache_file}" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ "${cache_valid}" == "false" ]]; then
    npm_response="$(curl -s --max-time 2 "https://registry.npmjs.org/oh-my-claude-sisyphus/latest" 2>/dev/null || true)"
    if [[ -n "${npm_response}" ]]; then
      fetched_version="$(printf '%s' "${npm_response}" | jq -r '.version // ""' 2>/dev/null || true)"
      if [[ -n "${fetched_version}" ]]; then
        update_available=false
        if semver_gt "${fetched_version}" "${plugin_version}"; then
          update_available=true
          latest_version="${fetched_version}"
        fi
        mkdir -p "${CONFIG_DIR}/.omc"
        now_ms_epoch="$(date +%s)000"
        printf '{"timestamp":%s,"latestVersion":"%s","currentVersion":"%s","updateAvailable":%s}\n' \
          "${now_ms_epoch}" "${fetched_version}" "${plugin_version}" "${update_available}" > "${cache_file}"
      fi
    fi
  fi

  if [[ -n "${latest_version}" ]] && semver_gt "${latest_version}" "${plugin_version}"; then
    messages+=("<session-restore>\n\n[OMC UPDATE AVAILABLE]\n\nA new version of oh-my-claudecode is available: v${latest_version} (current: v${plugin_version})\n\nTo update, run: omc update\n(This syncs plugin, npm package, and CLAUDE.md together)\n\n</session-restore>\n\n---\n")
  fi
fi

# ── 3. HUD check ─────────────────────────────────────────────────────────────

hud_dir="${CONFIG_DIR}/hud"
hud_script_omc="${hud_dir}/omc-hud.mjs"
hud_script_sisyphus="${hud_dir}/sisyphus-hud.mjs"
settings_file="${CONFIG_DIR}/settings.json"
hud_reason=""

if [[ ! -f "${hud_script_omc}" && ! -f "${hud_script_sisyphus}" ]]; then
  hud_reason="HUD script missing"
elif [[ ! -f "${settings_file}" ]]; then
  hud_reason="settings.json missing"
else
  # Retry up to 3 times for race condition (settings.json mid-write)
  for attempt in 1 2 3; do
    settings_content="$(cat "${settings_file}" 2>/dev/null || true)"
    if [[ -z "${settings_content// /}" ]]; then
      sleep 0.1
      continue
    fi
    status_line="$(printf '%s' "${settings_content}" | jq -r '.statusLine // ""' 2>/dev/null || true)"
    if [[ -z "${status_line}" ]]; then
      if (( attempt < 3 )); then
        sleep 0.1
        continue
      fi
      hud_reason="statusLine not configured"
    fi
    break
  done
fi

if [[ -n "${hud_reason}" ]]; then
  messages+=("<system-reminder>\n[Sisyphus] HUD not configured (${hud_reason}). Run /hud setup then restart Claude Code.\n</system-reminder>")
fi

# ── 4. Ultrawork state restore ───────────────────────────────────────────────

ultrawork_state=""
SESSION_ID_PATTERN='^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$'

if [[ -n "${session_id}" ]] && [[ "${session_id}" =~ ${SESSION_ID_PATTERN} ]]; then
  uw_path="${directory}/.omc/state/sessions/${session_id}/ultrawork-state.json"
  if [[ -f "${uw_path}" ]]; then
    uw_json="$(jq '.' "${uw_path}" 2>/dev/null || true)"
    # Validate session identity
    uw_sid="$(printf '%s' "${uw_json}" | jq -r '.session_id // ""' 2>/dev/null || true)"
    if [[ -z "${uw_sid}" || "${uw_sid}" == "${session_id}" ]]; then
      ultrawork_state="${uw_json}"
    fi
  fi
else
  uw_path="${directory}/.omc/state/ultrawork-state.json"
  [[ -f "${uw_path}" ]] && ultrawork_state="$(jq '.' "${uw_path}" 2>/dev/null || true)"
fi

if [[ -n "${ultrawork_state}" ]]; then
  uw_active="$(printf '%s' "${ultrawork_state}" | jq -r '.active // false' 2>/dev/null || true)"
  if [[ "${uw_active}" == "true" ]]; then
    uw_started="$(printf '%s' "${ultrawork_state}" | jq -r '.started_at // ""' 2>/dev/null || true)"
    uw_prompt="$(printf '%s' "${ultrawork_state}" | jq -r '.original_prompt // ""' 2>/dev/null || true)"
    messages+=("<session-restore>\n\n[ULTRAWORK MODE RESTORED]\n\nYou have an active ultrawork session from ${uw_started}.\nOriginal task: ${uw_prompt}\n\nContinue working in ultrawork mode until all tasks are complete.\n\n</session-restore>\n\n---\n")
  fi
fi

# ── 5. Ralph state restore ───────────────────────────────────────────────────

ralph_state=""

if [[ -n "${session_id}" ]] && [[ "${session_id}" =~ ${SESSION_ID_PATTERN} ]]; then
  ralph_path="${directory}/.omc/state/sessions/${session_id}/ralph-state.json"
  if [[ -f "${ralph_path}" ]]; then
    ralph_json="$(jq '.' "${ralph_path}" 2>/dev/null || true)"
    ralph_sid="$(printf '%s' "${ralph_json}" | jq -r '.session_id // ""' 2>/dev/null || true)"
    if [[ -z "${ralph_sid}" || "${ralph_sid}" == "${session_id}" ]]; then
      ralph_state="${ralph_json}"
    fi
  fi
else
  ralph_path="${directory}/.omc/state/ralph-state.json"
  if [[ -f "${ralph_path}" ]]; then
    ralph_state="$(jq '.' "${ralph_path}" 2>/dev/null || true)"
  else
    ralph_path2="${directory}/.omc/ralph-state.json"
    [[ -f "${ralph_path2}" ]] && ralph_state="$(jq '.' "${ralph_path2}" 2>/dev/null || true)"
  fi
fi

if [[ -n "${ralph_state}" ]]; then
  ralph_active="$(printf '%s' "${ralph_state}" | jq -r '.active // false' 2>/dev/null || true)"
  if [[ "${ralph_active}" == "true" ]]; then
    ralph_prompt="$(printf '%s' "${ralph_state}" | jq -r '.prompt // "Task in progress"' 2>/dev/null || true)"
    ralph_iter="$(printf '%s' "${ralph_state}" | jq -r '.iteration // 1' 2>/dev/null || true)"
    ralph_max="$(printf '%s' "${ralph_state}" | jq -r '.max_iterations // 10' 2>/dev/null || true)"
    messages+=("<session-restore>\n\n[RALPH LOOP RESTORED]\n\nYou have an active ralph-loop session.\nOriginal task: ${ralph_prompt}\nIteration: ${ralph_iter}/${ralph_max}\n\nContinue working until the task is verified complete.\n\n</session-restore>\n\n---\n")
  fi
fi

# ── 6. Incomplete todos ──────────────────────────────────────────────────────

incomplete_count=0
for todo_file in "${directory}/.omc/todos.json" "${directory}/.claude/todos.json"; do
  if [[ -f "${todo_file}" ]]; then
    count="$(jq '[(.todos // (if type=="array" then . else [] end))[] | select(.status != "completed" and .status != "cancelled")] | length' "${todo_file}" 2>/dev/null || echo 0)"
    incomplete_count=$(( incomplete_count + count ))
  fi
done

if (( incomplete_count > 0 )); then
  messages+=("<session-restore>\n\n[PENDING TASKS DETECTED]\n\nYou have ${incomplete_count} incomplete tasks from a previous session.\nPlease continue working on these tasks.\n\n</session-restore>\n\n---\n")
fi

# ── 7. Notepad priority context ──────────────────────────────────────────────

notepad_path="${directory}/.omc/notepad.md"
if [[ -f "${notepad_path}" ]]; then
  notepad_content="$(cat "${notepad_path}" 2>/dev/null || true)"
  # Extract content between "## Priority Context" and next "## " or EOF
  priority_section="$(printf '%s' "${notepad_content}" | awk '/^## Priority Context/{found=1; next} found && /^## /{exit} found{print}' || true)"
  # Strip HTML comments
  clean_content="$(printf '%s' "${priority_section}" | sed 's/<!--.*-->//g' | sed '/^[[:space:]]*$/d' || true)"
  if [[ -n "${clean_content// /}" ]]; then
    messages+=("<notepad-context>\n[NOTEPAD - Priority Context]\n${clean_content}\n</notepad-context>")
  fi
fi

# ── 8. Cleanup old plugin cache versions (keep latest 2) ────────────────────

cache_base="${CONFIG_DIR}/plugins/cache/omc/oh-my-claudecode"
if [[ -d "${cache_base}" ]]; then
  # Get version directories matching semver pattern, sort by version descending
  mapfile -t versions < <(
    shopt -s nullglob
    version_dirs=()
    for dir in "${cache_base}"/*; do
      [[ -d "$dir" ]] || continue
      basename_dir="${dir##*/}"
      [[ $basename_dir =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] && version_dirs+=("$basename_dir")
    done
    printf '%s\n' "${version_dirs[@]}" | sort -t. -k1,1rn -k2,2rn -k3,3rn
  )
  if (( ${#versions[@]} > 2 )); then
    for version in "${versions[@]:2}"; do
      rm -rf "${cache_base:?}/${version}" 2>/dev/null || true
    done
  fi
fi

# ── Output ───────────────────────────────────────────────────────────────────

if (( ${#messages[@]} > 0 )); then
  # Join messages with newline
  combined=""
  for msg in "${messages[@]}"; do
    if [[ -n "${combined}" ]]; then
      combined+=$'\n'
    fi
    combined+="$(printf '%b' "${msg}")"
  done
  # Output JSON with additionalContext
  jq -n --arg ctx "${combined}" \
    '{"continue":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
else
  printf '{"continue":true,"suppressOutput":true}\n'
fi
