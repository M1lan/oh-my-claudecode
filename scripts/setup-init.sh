#!/usr/bin/env bash

: "${EPOCHREALTIME:?requires GNU Bash 5.3+}" 2>/dev/null \
  || { printf 'error: GNU Bash >= 5.3 required (found %s)\n' "$BASH_VERSION" >&2; exit 1; }

set -uo pipefail
export LC_ALL=C

input=$(timeout 5 cat 2>/dev/null || true)
cwd=$(printf '%s' "${input:-}" | jq -r '.cwd // empty' 2>/dev/null || true)
[[ -z "${cwd:-}" ]] && cwd="$(pwd)"

declare -ra REQUIRED_DIRS=(
  '.omc/state'
  '.omc/logs'
  '.omc/notepads'
  '.omc/state/checkpoints'
  '.omc/plans'
)

declare -i dirs_created=0
declare -i configs_validated=0
declare -i env_vars_set=0

# Create required directories
for dir in "${REQUIRED_DIRS[@]}"; do
  full_path="${cwd}/${dir}"
  if [[ ! -d "${full_path}" ]]; then
    mkdir -p "${full_path}" 2>/dev/null && (( dirs_created++ )) || true
  fi
done

# Validate config files
if [[ -r "${cwd}/.omc-config.json" ]]; then
  (( configs_validated++ )) || true
fi

# Set environment variable if CLAUDE_ENV_FILE is set
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  printf 'export OMC_INITIALIZED=true\n' >> "${CLAUDE_ENV_FILE}" 2>/dev/null \
    && (( env_vars_set++ )) || true
fi

# Build context string
context="OMC initialized:
- ${dirs_created} directories created
- ${configs_validated} configs validated"
[[ ${env_vars_set} -gt 0 ]] && context+="
- Environment variables set: OMC_INITIALIZED"

printf '%s\n' "$(jq -n \
  --arg ctx "${context}" \
  '{"continue":true,"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":$ctx}}')"
