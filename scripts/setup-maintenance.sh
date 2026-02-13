#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C

input=$(timeout 5 cat 2>/dev/null || true)
cwd=$(printf '%s' "${input:-}" | jq -r '.cwd // empty' 2>/dev/null || true)
[[ -z "${cwd:-}" ]] && cwd="$(pwd)"

declare -r STATE_DIR="${cwd}/.omc/state"
declare -ri MAX_AGE_DAYS=7
declare -ri ORPHAN_AGE_SECS=86400  # 24h

# Critical state files never pruned
declare -ra CRITICAL_STATES=(
  'autopilot-state.json'
  'ultrapilot-state.json'
  'ralph-state.json'
  'ultrawork-state.json'
  'swarm-state.json'
)

declare -i pruned=0
declare -i orphaned=0

if [[ -d "${STATE_DIR}" ]]; then
  now_s=$(printf '%(%s)T' -1)
  declare -ri cutoff_s=$(( now_s - MAX_AGE_DAYS * 86400 ))
  declare -ri orphan_cutoff_s=$(( now_s - ORPHAN_AGE_SECS ))

  for f in "${STATE_DIR}"/*.json; do
    [[ -f "$f" ]] || continue
    fname="${f##*/}"

    # Portable mtime (GNU stat -c, BSD stat -f)
    mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || printf '0')

    # Prune old files (skip critical state files)
    if (( mtime < cutoff_s )); then
      is_critical=false
      for c in "${CRITICAL_STATES[@]}"; do
        [[ "$fname" == "$c" ]] && is_critical=true && break
      done
      if ! "${is_critical}"; then
        rm -f "$f" 2>/dev/null && (( pruned++ )) || true
        continue
      fi
    fi

    # Clean orphaned session-specific files (*-session-<uuid>.json older than 24h)
    if [[ "$fname" =~ -session-[a-f0-9-]+\.json$ ]] && (( mtime < orphan_cutoff_s )); then
      rm -f "$f" 2>/dev/null && (( orphaned++ )) || true
    fi
  done
fi

# Build context string
if (( pruned == 0 && orphaned == 0 )); then
  context="OMC maintenance completed:
- No maintenance needed"
else
  context="OMC maintenance completed:"
  (( pruned   > 0 )) && context+="
- ${pruned} old state files pruned"
  (( orphaned > 0 )) && context+="
- ${orphaned} orphaned state files cleaned"
fi

printf '%s\n' "$(jq -n \
  --arg ctx "${context}" \
  '{"continue":true,"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":$ctx}}')"
