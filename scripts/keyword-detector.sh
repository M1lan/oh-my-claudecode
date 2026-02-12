#!/usr/bin/env bash
set -uo pipefail

# SCRIPT_DIR is not used in this script but kept for consistency with other scripts
# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

# On any unhandled error, emit safe passthrough
trap 'printf "%s\n" "{\"continue\":true,\"suppressOutput\":true}"; exit 0' ERR

# Read stdin with timeout
input=$(timeout 5 cat 2>/dev/null || true)

if [[ -z "${input// }" ]]; then
  printf '%s\n' '{"continue":true,"suppressOutput":true}'
  exit 0
fi

# Extract fields from JSON input
directory=$(printf '%s' "$input" | jq -r '.cwd // .directory // ""' 2>/dev/null || true)
session_id=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // ""' 2>/dev/null || true)

if [[ -z "$directory" ]]; then
  directory="$(pwd)"
fi

# Extract prompt from various JSON structures
prompt=$(printf '%s' "$input" | jq -r '
  if .prompt then .prompt
  elif .message.content then .message.content
  elif (.parts | type) == "array" then
    [.parts[] | select(.type == "text") | .text] | join(" ")
  else ""
  end
' 2>/dev/null || true)

if [[ -z "$prompt" ]]; then
  printf '%s\n' '{"continue":true,"suppressOutput":true}'
  exit 0
fi

# Sanitize prompt for keyword detection using perl (portable, no grep -P needed)
clean_prompt=$(printf '%s' "$prompt" | perl -0777 \
  -e 'my $t = do { local $/; <STDIN> };
      $t =~ s|<(\w[\w-]*)[\s>][\s\S]*?</\1>||g;
      $t =~ s|<\w[\w-]*(?:\s[^>]*)?\s*/>||g;
      $t =~ s|https?://[^\s)>\]]+||g;
      $t =~ s|(^|[\s"'"'"'`(])(?:\/)?(?:[\w.-]+\/)+[\w.-]+||gm;
      $t =~ s|```[\s\S]*?```||g;
      $t =~ s|`[^`]+`||g;
      print lc($t);
  ' 2>/dev/null || printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

# pmatch: portable perl regex match (replaces grep -P)
# Usage: pmatch STRING PATTERN  -> returns 0 if matched
pmatch() {
  printf '%s' "$1" | perl -ne "if (/$2/) { \$found=1; last } END { exit(\$found ? 0 : 1) }" 2>/dev/null
}

# --- State file helpers ---

is_valid_session() {
  local sid="$1"
  [[ -n "$sid" ]] && printf '%s' "$sid" | $GREP -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,255}$'
}

get_state_path() {
  local dir="$1" mode="$2" sid="$3"
  if is_valid_session "$sid"; then
    printf '%s\n' "${dir}/.omc/state/sessions/${sid}/${mode}-state.json"
  else
    printf '%s\n' "${dir}/.omc/state/${mode}-state.json"
  fi
}

activate_state() {
  local dir="$1" orig_prompt="$2" mode="$3" sid="$4"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local state_json
  state_json=$(jq -n \
    --arg started "$now" \
    --arg prompt "$orig_prompt" \
    --arg sid "$sid" \
    --arg checked "$now" \
    '{active:true, started_at:$started, original_prompt:$prompt, session_id:($sid|if . == "" then null else . end), reinforcement_count:0, last_checked_at:$checked}')

  if is_valid_session "$sid"; then
    local session_dir="${dir}/.omc/state/sessions/${sid}"
    mkdir -p "$session_dir" 2>/dev/null || true
    printf '%s\n' "$state_json" > "${session_dir}/${mode}-state.json" 2>/dev/null || true
    chmod 600 "${session_dir}/${mode}-state.json" 2>/dev/null || true
  else
    local local_dir="${dir}/.omc/state"
    mkdir -p "$local_dir" 2>/dev/null || true
    printf '%s\n' "$state_json" > "${local_dir}/${mode}-state.json" 2>/dev/null || true
    chmod 600 "${local_dir}/${mode}-state.json" 2>/dev/null || true
  fi
}

clear_state_files() {
  local dir="$1" sid="$2"
  shift 2
  local home_dir="${HOME:-/}"
  for mode in "$@"; do
    rm -f "${dir}/.omc/state/${mode}-state.json" 2>/dev/null || true
    rm -f "${home_dir}/.omc/state/${mode}-state.json" 2>/dev/null || true
    if is_valid_session "$sid"; then
      rm -f "${dir}/.omc/state/sessions/${sid}/${mode}-state.json" 2>/dev/null || true
    fi
  done
}

link_ralph_team() {
  local dir="$1" sid="$2"
  local ralph_path team_path
  ralph_path=$(get_state_path "$dir" "ralph" "$sid")
  team_path=$(get_state_path "$dir" "team" "$sid")

  if [[ -f "$ralph_path" ]]; then
    local updated
    updated=$(jq '.linked_team = true' "$ralph_path" 2>/dev/null || true)
    [[ -n "$updated" ]] && printf '%s\n' "$updated" > "$ralph_path" 2>/dev/null || true
  fi

  if [[ -f "$team_path" ]]; then
    local updated
    updated=$(jq '.linked_ralph = true' "$team_path" 2>/dev/null || true)
    [[ -n "$updated" ]] && printf '%s\n' "$updated" > "$team_path" 2>/dev/null || true
  fi
}

is_team_enabled() {
  local cfg_dir="${CLAUDE_CONFIG_DIR:-${HOME:-/}/.claude}"
  local settings="${cfg_dir}/settings.json"
  if [[ -f "$settings" ]]; then
    local val
    val=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' "$settings" 2>/dev/null || true)
    if [[ "$val" == "1" || "$val" == "true" ]]; then
      return 0
    fi
  fi
  if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" == "1" || "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" == "true" ]]; then
    return 0
  fi
  return 1
}

# --- Output builders ---

create_skill_invocation() {
  local skill_name="$1" orig_prompt="$2" args="${3:-}"
  local args_section=""
  [[ -n "$args" ]] && args_section=$'\n'"Arguments: ${args}"
  printf '[MAGIC KEYWORD: %s]\n\nYou MUST invoke the skill using the Skill tool:\n\nSkill: oh-my-claudecode:%s%s\n\nUser request:\n%s\n\nIMPORTANT: Invoke the skill IMMEDIATELY. Do not proceed without loading the skill instructions.\n' \
    "${skill_name^^}" "$skill_name" "$args_section" "$orig_prompt"
}

create_multi_skill_invocation() {
  local orig_prompt="$1"
  shift
  local skills=("$@")
  local count=${#skills[@]}

  if [[ $count -eq 0 ]]; then
    return
  fi

  if [[ $count -eq 1 ]]; then
    create_skill_invocation "${skills[0]}" "$orig_prompt"
    return
  fi

  local names_upper=""
  local skill_blocks=""
  local i=1
  for s in "${skills[@]}"; do
    [[ -n "$names_upper" ]] && names_upper+=", "
    names_upper+="${s^^}"
    skill_blocks+="### Skill ${i}: ${s^^}"$'\n'
    skill_blocks+="Skill: oh-my-claudecode:${s}"$'\n\n'
    i=$(( i + 1 ))
  done

  printf '[MAGIC KEYWORDS DETECTED: %s]\n\nYou MUST invoke ALL of the following skills using the Skill tool, in order:\n\n%s\nUser request:\n%s\n\nIMPORTANT: Invoke ALL skills listed above. Start with the first skill IMMEDIATELY. After it completes, invoke the next skill in order. Do not skip any skill.\n' \
    "$names_upper" "$skill_blocks" "$orig_prompt"
}

create_mcp_delegation() {
  local provider="$1" orig_prompt="$2"
  local tool roles default_role provider_label
  if [[ "$provider" == "codex" ]]; then
    tool="ask_codex"
    roles="architect, planner, critic, analyst, code-reviewer, security-reviewer, tdd-guide"
    default_role="architect"
    provider_label="Codex"
  elif [[ "$provider" == "gemini" ]]; then
    tool="ask_gemini"
    roles="designer, writer, vision"
    default_role="designer"
    provider_label="Gemini"
  else
    return
  fi

  printf "[MAGIC KEYWORD: %s]\n\nYou MUST delegate this task to the %s MCP tool.\n\nSteps:\n1. Write a prompt file to \`.omc/prompts/%s-{purpose}-{timestamp}.md\` containing clear task instructions derived from the user's request\n2. Determine the appropriate agent_role from: %s\n3. Call the \`%s\` MCP tool with:\n   - agent_role: <detected or default \"%s\">\n   - prompt_file: <path you wrote>\n   - output_file: <corresponding -summary.md path>\n   - context_files: <relevant files from user's request>\n\nUser request:\n%s\n\nIMPORTANT: Do NOT invoke a skill. Delegate to the MCP tool IMMEDIATELY.\n" \
    "${provider^^}" "$provider_label" "$provider" "$roles" "$tool" "$default_role" "$orig_prompt"
}

create_hook_output() {
  local additional_context="$1"
  jq -n --arg ctx "$additional_context" \
    '{continue:true, hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
}

# --- Keyword detection ---

declare -a matches=()

# Cancel
if printf '%s' "$clean_prompt" | $GREP -qE '\b(cancelomc|stopomc)\b'; then
  matches+=("cancel")
fi

# Ralph
if printf '%s' "$clean_prompt" | $GREP -qE '\b(ralph|until done)\b' || \
   pmatch "$clean_prompt" "don't stop" || \
   pmatch "$clean_prompt" 'must complete'; then
  matches+=("ralph")
fi

# Autopilot
if printf '%s' "$clean_prompt" | $GREP -qE '\b(autopilot|auto-pilot|autonomous|fullsend)\b' || \
   pmatch "$clean_prompt" 'auto pilot' || \
   pmatch "$clean_prompt" 'full auto' || \
   pmatch "$clean_prompt" '\bbuild\s+me\s+' || \
   pmatch "$clean_prompt" '\bcreate\s+me\s+' || \
   pmatch "$clean_prompt" '\bmake\s+me\s+' || \
   pmatch "$clean_prompt" '\bi\s+want\s+a\s+' || \
   pmatch "$clean_prompt" '\bi\s+want\s+an\s+' || \
   pmatch "$clean_prompt" '\bhandle\s+it\s+all\b' || \
   pmatch "$clean_prompt" '\bend\s+to\s+end\b' || \
   pmatch "$clean_prompt" '\be2e\s+this\b'; then
  matches+=("autopilot")
fi

# Ultrapilot (legacy)
if printf '%s' "$clean_prompt" | $GREP -qE '\b(ultrapilot|ultra-pilot)\b' || \
   pmatch "$clean_prompt" '\bparallel\s+build\b' || \
   pmatch "$clean_prompt" '\bswarm\s+build\b' || \
   pmatch "$clean_prompt" '\bswarm\s+[0-9]+\s+agents?\b' || \
   pmatch "$clean_prompt" '\bcoordinated\s+agents\b'; then
  matches+=("ultrapilot")
fi

# Ultrawork
if printf '%s' "$clean_prompt" | $GREP -qE '\b(ultrawork|ulw|uw)\b'; then
  matches+=("ultrawork")
fi

# Ecomode
if printf '%s' "$clean_prompt" | $GREP -qE '\b(eco|ecomode|eco-mode|efficient|save-tokens|budget)\b'; then
  matches+=("ecomode")
fi

# Team (intent-gated: reject "my team", "the team", etc. via perl lookbehind)
has_team_keyword=false
if pmatch "$clean_prompt" '(?<!(?:my|the|our|a|his|her|their|its)\s)\bteam\b'; then
  has_team_keyword=true
fi
if pmatch "$clean_prompt" '\bcoordinated\s+team\b'; then
  has_team_keyword=true
fi
if [[ "$has_team_keyword" == "true" ]] && is_team_enabled; then
  matches+=("team")
fi

# Pipeline
if printf '%s' "$clean_prompt" | $GREP -qE '\bpipeline\b' || \
   pmatch "$clean_prompt" '\bchain\s+agents\b'; then
  matches+=("pipeline")
fi

# Ralplan
if printf '%s' "$clean_prompt" | $GREP -qE '\bralplan\b'; then
  matches+=("ralplan")
fi

# Plan
if printf '%s' "$clean_prompt" | $GREP -qE '\bplan (this|the)\b'; then
  matches+=("plan")
fi

# TDD
if printf '%s' "$clean_prompt" | $GREP -qE '\btdd\b' || \
   pmatch "$clean_prompt" '\btest\s+first\b' || \
   pmatch "$clean_prompt" '\bred\s+green\b'; then
  matches+=("tdd")
fi

# Research
if printf '%s' "$clean_prompt" | $GREP -qE '\b(research|statistics)\b' || \
   pmatch "$clean_prompt" '\banalyze\s+data\b'; then
  matches+=("research")
fi

# Ultrathink
if printf '%s' "$clean_prompt" | $GREP -qE '\b(ultrathink|think hard|think deeply)\b'; then
  matches+=("ultrathink")
fi

# Deepsearch
if printf '%s' "$clean_prompt" | $GREP -qE '\bdeepsearch\b' || \
   pmatch "$clean_prompt" '\bsearch\s+(the\s+)?(codebase|code|files?|project)\b' || \
   pmatch "$clean_prompt" '\bfind\s+(in\s+)?(codebase|code|all\s+files?)\b'; then
  matches+=("deepsearch")
fi

# Analyze
if pmatch "$clean_prompt" '\bdeep\s*analyze\b' || \
   pmatch "$clean_prompt" '\binvestigate\s+(the|this|why)\b' || \
   pmatch "$clean_prompt" '\bdebug\s+(the|this|why)\b'; then
  matches+=("analyze")
fi

# Codex (intent-phrase only)
if pmatch "$clean_prompt" '\b(ask|use|delegate\s+to)\s+(codex|gpt)\b'; then
  matches+=("codex")
fi

# Gemini (intent-phrase only)
if pmatch "$clean_prompt" '\b(ask|use|delegate\s+to)\s+gemini\b'; then
  matches+=("gemini")
fi

# No matches
if [[ ${#matches[@]} -eq 0 ]]; then
  printf '%s\n' '{"continue":true,"suppressOutput":true}'
  exit 0
fi

# Deduplicate preserving order
declare -a unique_matches=()
declare -A seen_map=()
for m in "${matches[@]}"; do
  if [[ -z "${seen_map[$m]+_}" ]]; then
    seen_map[$m]=1
    unique_matches+=("$m")
  fi
done

# Resolve conflicts
has_cancel=false; has_ecomode=false; has_team_r=false
for m in "${unique_matches[@]}"; do
  case "$m" in
    cancel)    has_cancel=true ;;
    ecomode)   has_ecomode=true ;;
    team)      has_team_r=true ;;
  esac
done

declare -a resolved=()

if [[ "$has_cancel" == "true" ]]; then
  resolved=("cancel")
else
  declare -a filtered=()
  for m in "${unique_matches[@]}"; do
    [[ "$m" == "ultrawork"  && "$has_ecomode" == "true"  ]] && continue
    [[ "$m" == "autopilot"  && "$has_team_r"  == "true"  ]] && continue
    [[ "$m" == "ultrapilot" && "$has_team_r"  == "true"  ]] && continue
    filtered+=("$m")
  done

  # Sort by priority (insertion sort)
  priority_order=(cancel ralph autopilot team ultrawork ecomode pipeline ralplan plan tdd research ultrathink deepsearch analyze codex gemini)
  declare -A prio_idx=()
  local_i=0
  for p in "${priority_order[@]}"; do
    prio_idx[$p]=$local_i
    local_i=$(( local_i + 1 ))
  done

  for ((i=1; i<${#filtered[@]}; i++)); do
    key="${filtered[$i]}"
    key_idx="${prio_idx[$key]:-999}"
    j=$((i-1))
    while [[ $j -ge 0 ]]; do
      prev="${filtered[$j]}"
      prev_idx="${prio_idx[$prev]:-999}"
      if [[ $prev_idx -gt $key_idx ]]; then
        filtered[j+1]="${filtered[$j]}"
        j=$(( j - 1 ))
      else
        break
      fi
    done
    filtered[j+1]="$key"
  done

  resolved=("${filtered[@]}")
fi

# Handle cancel
if [[ "${resolved[0]:-}" == "cancel" ]]; then
  clear_state_files "$directory" "$session_id" ralph autopilot team ultrawork ecomode swarm pipeline
  msg=$(create_skill_invocation "cancel" "$prompt")
  create_hook_output "$msg"
  exit 0
fi

# Activate states for persistent modes
state_modes=(ralph autopilot team ultrawork ecomode)
for mode in "${resolved[@]}"; do
  for sm in "${state_modes[@]}"; do
    if [[ "$mode" == "$sm" ]]; then
      activate_state "$directory" "$prompt" "$mode" "$session_id"
      break
    fi
  done
done

# Ralph without ecomode and without ultrawork -> also activate ultrawork
has_ralph_r=false; has_ecomode_r=false; has_ultrawork_r=false; has_team_rr=false
for m in "${resolved[@]}"; do
  case "$m" in
    ralph)     has_ralph_r=true ;;
    ecomode)   has_ecomode_r=true ;;
    ultrawork) has_ultrawork_r=true ;;
    team)      has_team_rr=true ;;
  esac
done
if [[ "$has_ralph_r" == "true" && "$has_ecomode_r" == "false" && "$has_ultrawork_r" == "false" ]]; then
  activate_state "$directory" "$prompt" "ultrawork" "$session_id"
fi

# Link ralph + team if both present
if [[ "$has_ralph_r" == "true" && "$has_team_rr" == "true" ]]; then
  link_ralph_team "$directory" "$session_id"
fi

# Handle ultrathink: strip it and prepend message
ultrathink_present=false
declare -a resolved_no_ultrathink=()
for m in "${resolved[@]}"; do
  if [[ "$m" == "ultrathink" ]]; then
    ultrathink_present=true
  else
    resolved_no_ultrathink+=("$m")
  fi
done

ULTRATHINK_MESSAGE='<think-mode>

**ULTRATHINK MODE ENABLED** - Extended reasoning activated.

You are now in deep thinking mode. Take your time to:
1. Thoroughly analyze the problem from multiple angles
2. Consider edge cases and potential issues
3. Think through the implications of each approach
4. Reason step-by-step before acting

Use your extended thinking capabilities to provide the most thorough and well-reasoned response.

</think-mode>

---
'

if [[ "$ultrathink_present" == "true" ]]; then
  if [[ ${#resolved_no_ultrathink[@]} -eq 0 ]]; then
    create_hook_output "$ULTRATHINK_MESSAGE"
    exit 0
  fi
  skill_msg=$(create_multi_skill_invocation "$prompt" "${resolved_no_ultrathink[@]}")
  create_hook_output "${ULTRATHINK_MESSAGE}${skill_msg}"
  exit 0
fi

# Split resolved into skills vs MCP delegations
MCP_KEYWORDS=(codex gemini)
declare -a skill_matches=()
declare -a delegation_matches=()
for m in "${resolved[@]}"; do
  is_mcp=false
  for mk in "${MCP_KEYWORDS[@]}"; do
    [[ "$m" == "$mk" ]] && { is_mcp=true; break; }
  done
  if [[ "$is_mcp" == "true" ]]; then
    delegation_matches+=("$m")
  else
    skill_matches+=("$m")
  fi
done

if [[ ${#skill_matches[@]} -gt 0 && ${#delegation_matches[@]} -gt 0 ]]; then
  all_names=""
  for m in "${skill_matches[@]}" "${delegation_matches[@]}"; do
    [[ -n "$all_names" ]] && all_names+=", "
    all_names+="${m^^}"
  done

  skill_section="## Section 1: Skill Invocations

$(create_multi_skill_invocation "$prompt" "${skill_matches[@]}")"

  del_body=""
  first_del=true
  for d in "${delegation_matches[@]}"; do
    [[ "$first_del" == "false" ]] && del_body+=$'\n\n---\n\n'
    del_body+=$(create_mcp_delegation "$d" "$prompt")
    first_del=false
  done
  delegation_section="## Section 2: MCP Delegations

${del_body}"

  combined="[MAGIC KEYWORDS DETECTED: ${all_names}]

${skill_section}

---

${delegation_section}

IMPORTANT: Complete ALL sections above in order."

  create_hook_output "$combined"

elif [[ ${#delegation_matches[@]} -gt 0 ]]; then
  del_body=""
  first_del=true
  for d in "${delegation_matches[@]}"; do
    [[ "$first_del" == "false" ]] && del_body+=$'\n\n---\n\n'
    del_body+=$(create_mcp_delegation "$d" "$prompt")
    first_del=false
  done
  create_hook_output "$del_body"

else
  msg=$(create_multi_skill_invocation "$prompt" "${skill_matches[@]}")
  create_hook_output "$msg"
fi
