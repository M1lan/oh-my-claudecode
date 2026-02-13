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
declare -r _PROJECT_MARKERS=('.git' 'pyproject.toml' 'package.json' 'Cargo.toml' 'go.mod' '.venv')

# walk up from dir until a project marker is found
# returns path via stdout, empty if not found
find_project_root() {
  local dir=$1
  local marker cur=$dir
  while true; do
    for marker in "${_PROJECT_MARKERS[@]}"; do
      [[ -e "${cur}/${marker}" ]] && printf '%s' "$cur" && return 0
    done
    local parent="${cur%/*}"
    [[ "$parent" == "$cur" || -z "$parent" ]] && return 1
    cur=$parent
  done
}

# format project memory as context summary (mirrors formatContextSummary in TS)
# param: memory_json - full JSON string of project memory
# prints formatted text to stdout
format_context_summary() {
  local mem=$1

  jq -r '
    # user directives first
    (.userDirectives // []) as $dirs |
    (.techStack.languages // []) as $langs |
    (.techStack.frameworks // []) as $fws |
    (.techStack.packageManager // null) as $pm |
    (.build.buildCommand // null) as $build |
    (.build.testCommand // null) as $test |
    (.hotPaths // []) as $hp |
    (.directoryMap // {} | to_entries | map(.value) | map(select(.purpose != null and .purpose != ""))) as $dirs_map |

    # format directives
    (if ($dirs | length) > 0 then
      "**User Directives:**\n" +
      ($dirs | map(
        if type == "string" then "- " + .
        else "- " + (.text // .content // .directive // (.| tostring))
        end
      ) | join("\n")) + "\n"
    else "" end) as $dir_text |

    # build tech summary parts
    ([$langs | sort_by(.markers | length) | reverse | map(select(.confidence == "high")) | first | .name // empty] |
      if length > 0 then .[0] else null end) as $primary_lang |

    # primary framework: prefer fullstack > frontend > backend > testing > build
    ([$fws | map(select(.category == "fullstack")) | first,
       $fws | map(select(.category == "frontend")) | first,
       $fws | map(select(.category == "backend")) | first,
       $fws | map(select(.category == "testing")) | first,
       $fws | map(select(.category == "build")) | first,
       $fws | first] | map(select(. != null)) | first) as $primary_fw |

    # assemble tech parts
    ([$primary_lang,
      (if $primary_fw then $primary_fw.name else null end),
      (if $pm then "using " + $pm else null end),
      (if $build then "Build: " + $build else null end),
      (if $test then "Test: " + $test else null end)
    ] | map(select(. != null)) | join(" | ")) as $tech_summary |

    # hot paths (top 5 by accessCount)
    ($hp | sort_by(-.accessCount) | .[0:5]) as $top_paths |

    # key directories (first 5 with purpose)
    ($dirs_map | .[0:5]) as $key_dirs |

    # assemble output
    (
      (if $dir_text != "" then $dir_text + "\n" else "" end) +
      (if $tech_summary != "" then "[Project Environment] " + $tech_summary else "" end) +
      (if ($top_paths | length) > 0 then
        "\n\n**Frequently Accessed:**\n" +
        ($top_paths | map("- " + .path + " (" + (.accessCount | tostring) + "x)") | join("\n"))
      else "" end) +
      (if ($key_dirs | length) > 0 then
        "\n\n**Key Directories:**\n" +
        ($key_dirs | map("- " + .path + ": " + .purpose) | join("\n"))
      else "" end)
    )
  ' <<< "$mem" 2>/dev/null || true
}

input=$(timeout 5 cat 2>/dev/null || true)
[[ -z "${input:-}" ]] && printf '%s\n' "$_PASS" && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // .directory // ""' 2>/dev/null || true)
[[ -z "$cwd" ]] && cwd="$PWD"

project_root=$(find_project_root "$cwd" 2>/dev/null || true)
if [[ -z "${project_root:-}" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

memory_file="${project_root}/.omc/project-memory.json"
if [[ ! -f "$memory_file" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

memory=$(< "$memory_file") 2>/dev/null || true
if [[ -z "${memory:-}" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

# check if there is critical info to preserve
has_critical=$(printf '%s' "$memory" | jq -r '
  ((.userDirectives // [] | length) > 0) or
  ((.hotPaths // [] | length) > 0) or
  ((.techStack.languages // [] | length) > 0)
  | if . then "yes" else "no" end
' 2>/dev/null || true)

if [[ "$has_critical" != "yes" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

context_summary=$(format_context_summary "$memory")
if [[ -z "${context_summary:-}" ]]; then
  printf '%s\n' "$_PASS"
  exit 0
fi

system_message="# Project Memory (Post-Compaction Recovery)

The following project context and user directives must be preserved after compaction:

${context_summary}

**IMPORTANT:** These user directives must be followed throughout the session, even after compaction."

printf '%s' "$input" | jq -n \
  --arg msg "$system_message" \
  '{"continue":true,"systemMessage":$msg}'
