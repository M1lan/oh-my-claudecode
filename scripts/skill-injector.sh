#!/usr/bin/env bash
# Skill Injector Hook (UserPromptSubmit)
# Injects relevant learned skills into context based on prompt triggers.
# Bash port of skill-injector.mjs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
session_id=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // "unknown"' 2>/dev/null || echo "unknown")
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
[[ -z "${cwd:-}" ]] && cwd="$(pwd)"
[[ -z "${prompt:-}" ]] && quiet_exit

# =============================================================================
# Primary: Try compiled bridge via node
# =============================================================================

BRIDGE_CJS="${SCRIPT_DIR}/../dist/hooks/skill-bridge.cjs"

bridge_result=""
if [[ -f "$BRIDGE_CJS" ]]; then
  bridge_result=$(printf '%s' "$input" | node --input-type=module 2>/dev/null <<'JSEOF' || echo '[]'
import { createRequire } from 'module';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { homedir } from 'os';

const scriptDir = process.env.SKILL_INJECTOR_SCRIPT_DIR;
const bridgePath = join(scriptDir, '..', 'dist', 'hooks', 'skill-bridge.cjs');
const require = createRequire(import.meta.url);

const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  try {
    const bridge = require(bridgePath);
    const data = JSON.parse(Buffer.concat(chunks).toString() || '{}');
    const prompt = data.prompt || '';
    const sessionId = data.session_id || data.sessionId || 'unknown';
    const directory = data.cwd || process.cwd();
    const matches = bridge.matchSkillsForInjection(prompt, directory, sessionId, { maxResults: 5 });
    if (matches.length > 0) bridge.markSkillsInjected(sessionId, matches.map(s => s.path), directory);
    console.log(JSON.stringify(matches));
  } catch {
    console.log('[]');
  }
});
JSEOF
) || bridge_result="[]"
fi

# Normalize
[[ -z "${bridge_result:-}" ]] && bridge_result="[]"

# Check if bridge returned real results
bridge_count=$(printf '%s' "$bridge_result" | jq 'length' 2>/dev/null || echo "0")

if [[ "$bridge_count" -gt 0 ]]; then
  # Format from bridge results (already parsed objects)
  formatted=$(printf '%s' "$bridge_result" | jq -r '
    "<mnemosyne>\n\n## Relevant Learned Skills\n\nThe following skills from previous sessions may help:\n\n" +
    (map(
      "### " + .name + " (" + .scope + ")\n" +
      "<skill-metadata>" + (. | {path, triggers, score, scope} | tojson) + "</skill-metadata>\n\n" +
      .content + "\n\n---\n"
    ) | join("\n")) +
    "\n</mnemosyne>"
  ' 2>/dev/null || true)

  if [[ -n "${formatted:-}" ]]; then
    printf '%s\n' "$(jq -n \
      --arg ctx "$formatted" \
      '{"continue":true,"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$ctx}}')"
    exit 0
  fi
fi

# =============================================================================
# Fallback: pure-bash skill matching
# =============================================================================

MAX_SKILLS=5
SKILL_EXT=".md"
HOME_DIR="${HOME}"
CFG_DIR="${CLAUDE_CONFIG_DIR:-${HOME_DIR}/.claude}"
USER_SKILLS_DIR="${CFG_DIR}/skills/omc-learned"
GLOBAL_SKILLS_DIR="${HOME_DIR}/.omc/skills"
PROJECT_SKILLS_DIR="${cwd}/.omc/skills"

prompt_lower=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

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
  if ! printf '%s' "$content" | grep -q '^---'; then
    continue
  fi

  # Extract frontmatter block (between first two ---)
  frontmatter=$(printf '%s' "$content" | awk '/^---/{count++; if(count==1){next} if(count==2){exit}} count==1{print}')
  # Extract body (after second ---)
  body=$(printf '%s' "$content" | awk '/^---/{count++} count>=2 && !/^---/{print}' | tail -n +2)
  body=$(printf '%s' "$body" | sed '/./,$!d' | sed -e 's/[[:space:]]*$//')

  # Extract name
  skill_name=$(printf '%s' "$frontmatter" | grep -m1 '^name:' | sed "s/^name:[[:space:]]*//" | tr -d '"'"'" || true)
  [[ -z "${skill_name:-}" ]] && skill_name="Unnamed Skill"

  # Extract triggers list (lines like "  - value")
  score=0
  triggers_json="[]"
  triggers_raw=$(printf '%s' "$frontmatter" | awk '/^triggers:/{found=1;next} found && /^  -/{print} found && !/^  -/{exit}')

  declare -a triggers=()
  while IFS= read -r line; do
    trigger=$(printf '%s' "$line" | sed 's/^[[:space:]]*-[[:space:]]*//' | tr -d '"'"'" | tr '[:upper:]' '[:lower:]')
    [[ -z "${trigger:-}" ]] && continue
    triggers+=("$trigger")
    if printf '%s' "$prompt_lower" | grep -qF "$trigger" 2>/dev/null; then
      score=$((score + 10))
    fi
  done <<< "$triggers_raw"

  if [[ "${#triggers[@]}" -gt 0 ]]; then
    triggers_json=$(printf '%s\n' "${triggers[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
  fi

  if [[ "$score" -gt 0 ]]; then
    scored_skills+=("${score}|${skill_name}|${skill_path}|${scope}|${body}|${triggers_json}")
  fi
done

if [[ "${#scored_skills[@]}" -eq 0 ]]; then
  quiet_exit
fi

# Sort by score descending, take top MAX_SKILLS
IFS=$'\n' sorted=($(printf '%s\n' "${scored_skills[@]}" | sort -t'|' -k1 -rn | head -n "$MAX_SKILLS"))
unset IFS

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
    '{"path":$path,"triggers":$triggers,"score":$score,"scope":$scope}' 2>/dev/null || echo '{}')

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
