#!/usr/bin/env bash
# Skill Injector Hook (UserPromptSubmit)
# Injects relevant learned skills into context based on prompt triggers.
# Bash port of skill-injector.mjs

set -uo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

QUIET_CONTINUE='{"continue":true,"suppressOutput":true}'

quiet_exit() {
  printf '%s\n' "$QUIET_CONTINUE"
  exit 0
}

# Read stdin with timeout
input=$(timeout 5 cat 2>/dev/null || true)

[[ -z "${input:-}" ]] && quiet_exit

# Parse fields from JSON input
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)
session_id=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // "unknown"' 2>/dev/null || printf '%s' "unknown")
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[[ -z "${cwd:-}" ]] && cwd="$(pwd)"
[[ -z "${prompt:-}" ]] && quiet_exit

# Use session_id to prevent unused variable warning
[[ -n "${session_id:-}" ]] || true

# =============================================================================
# Pure-bash skill matching
# =============================================================================

MAX_SKILLS=5
SKILL_EXT=".md"
HOME_DIR="${HOME}"
CFG_DIR="${CLAUDE_CONFIG_DIR:-${HOME_DIR}/.claude}"
USER_SKILLS_DIR="${CFG_DIR}/skills/omc-learned"
GLOBAL_SKILLS_DIR="${HOME_DIR}/.omc/skills"
PROJECT_SKILLS_DIR="${cwd}/.omc/skills"

# Use SKILL_EXT to prevent unused variable warning
[[ -n "${SKILL_EXT:-}" ]] || true

prompt_lower="${prompt,,}"

# Collect candidate skill files: path|scope
declare -a candidates=()

add_skills_from_dir() {
  local dir="$1"
  local scope="$2"
  [[ -d "$dir" ]] || return 0
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    candidates+=("${f}|${scope}")
  done
}

add_skills_from_dir "$PROJECT_SKILLS_DIR" "project"
add_skills_from_dir "$GLOBAL_SKILLS_DIR" "user"
add_skills_from_dir "$USER_SKILLS_DIR" "user"

# Parse each skill file and score it
declare -a scored_skills=()  # "score|name|path|scope|body|triggers_json"

for entry in "${candidates[@]+"${candidates[@]}"}"; do
  skill_path="${entry%|*}"
  scope="${entry##*|}"

  content=$(cat "$skill_path" 2>/dev/null || true)
  [[ -z "$content" ]] && continue

  # Check for frontmatter
  if ! printf '%s' "$content" | $GREP -q '^---'; then
    continue
  fi

  # Extract frontmatter block (between first two ---)
  frontmatter=$(printf '%s' "$content" | $AWK '/^---/{count++; if(count==1){next} if(count==2){exit}} count==1{print}')
  # Extract body (after second ---)
  body=$(printf '%s' "$content" | $AWK '/^---/{count++} count>=2 && !/^---/{print}' | tail -n +2)
  body=$(printf '%s' "$body" | $SED '/./,$!d' | $SED -e 's/[[:space:]]*$//')

  # Extract name
  skill_name=$(printf '%s' "$frontmatter" | $GREP -m1 '^name:' | $SED "s/^name:[[:space:]]*//" | tr -d '"'"'" || true)
  [[ -z "${skill_name:-}" ]] && skill_name="Unnamed Skill"

  # Extract triggers list (lines like "  - value")
  score=0
  triggers_json="[]"
  triggers_raw=$(printf '%s' "$frontmatter" | $AWK '/^triggers:/{found=1;next} found && /^  -/{print} found && !/^  -/{exit}')

  declare -a triggers=()
  while IFS= read -r line; do
    trigger=$(printf '%s' "$line" | $SED 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"'"'")
    trigger="${trigger,,}"
    [[ -z "${trigger:-}" ]] && continue
    triggers+=("$trigger")
    if printf '%s' "$prompt_lower" | $GREP -qF "$trigger" 2>/dev/null; then
      score=$((score + 10))
    fi
  done <<< "$triggers_raw"

  if [[ "${#triggers[@]}" -gt 0 ]]; then
    triggers_json=$(printf '%s\n' "${triggers[@]}" | jq -R . | jq -s . 2>/dev/null || printf '%s' "[]")
  fi

  if [[ "$score" -gt 0 ]]; then
    scored_skills+=("${score}|${skill_name}|${skill_path}|${scope}|${body}|${triggers_json}")
  fi
done

if [[ "${#scored_skills[@]}" -eq 0 ]]; then
  quiet_exit
fi

# Sort by score descending, take top MAX_SKILLS
mapfile -t sorted < <(printf '%s\n' "${scored_skills[@]}" | sort -t'|' -k1 -rn | head -n "$MAX_SKILLS")

# Format output message
message="<mnemosyne>

## Relevant Learned Skills

The following skills from previous sessions may help:

"

for entry in "${sorted[@]}"; do
  IFS='|' read -r sc nm sp scope bdy trig_json <<< "$entry"
  metadata=$(jq -n \
    --arg path "$sp" \
    --argjson triggers "$trig_json" \
    --argjson score "$sc" \
    --arg scope "$scope" \
    '{"path":$path,"triggers":$triggers,"score":$score,"scope":$scope}' 2>/dev/null || printf '%s' '{}')

  message+="### ${nm} (${scope})
<skill-metadata>${metadata}</skill-metadata>

${bdy}

---

"
done

message+="</mnemosyne>"

printf '%s\n' "$(jq -n \
  --arg ctx "$message" \
  '{"continue":true,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$ctx}}')"
