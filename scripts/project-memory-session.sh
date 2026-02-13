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
declare -r _CACHE_EXPIRY_MS=86400000  # 24 hours
declare -r _MEMORY_FILE='.omc/project-memory.json'
declare -r _PROJECT_MARKERS=('.git' 'pyproject.toml' 'package.json' 'Cargo.toml' 'go.mod' '.venv')

find_project_root() {
  local dir=$1 marker cur=$dir
  while true; do
    for marker in "${_PROJECT_MARKERS[@]}"; do
      [[ -e "${cur}/${marker}" ]] && printf '%s' "$cur" && return 0
    done
    local parent="${cur%/*}"
    [[ "$parent" == "$cur" || -z "$parent" ]] && return 1
    cur=$parent
  done
}

# returns 0 if memory is stale (older than 24h)
is_stale() {
  local last_scanned=$1
  local now_ms=$(( EPOCHREALTIME * 1000 ))
  # last_scanned is epoch ms from JS Date.now()
  (( now_ms - last_scanned > _CACHE_EXPIRY_MS ))
}

# detect language from project files
# prints JSON array of language objects
detect_languages() {
  local root=$1
  local -a langs=()

  [[ -f "${root}/package.json" || -d "${root}/node_modules" ]] && langs+=('{"name":"JavaScript","confidence":"high","markers":["package.json"]}')
  if [[ -f "${root}/tsconfig.json" ]]; then
    langs=('{"name":"TypeScript","confidence":"high","markers":["tsconfig.json"]}')
  fi
  [[ -f "${root}/requirements.txt" || -f "${root}/setup.py" || -f "${root}/pyproject.toml" ]] && langs+=('{"name":"Python","confidence":"high","markers":["requirements.txt"]}')
  [[ -f "${root}/go.mod" ]] && langs+=('{"name":"Go","confidence":"high","markers":["go.mod"]}')
  [[ -f "${root}/Cargo.toml" ]] && langs+=('{"name":"Rust","confidence":"high","markers":["Cargo.toml"]}')
  [[ -f "${root}/pom.xml" || -f "${root}/build.gradle" ]] && langs+=('{"name":"Java","confidence":"high","markers":["pom.xml"]}')
  [[ -f "${root}/Gemfile" ]] && langs+=('{"name":"Ruby","confidence":"high","markers":["Gemfile"]}')

  local joined
  printf -v joined '%s,' "${langs[@]+"${langs[@]}"}"
  printf '[%s]' "${joined%,}"
}

# detect package manager
detect_package_manager() {
  local root=$1
  [[ -f "${root}/pnpm-lock.yaml" ]] && printf 'pnpm' && return
  [[ -f "${root}/yarn.lock" ]] && printf 'yarn' && return
  [[ -f "${root}/package-lock.json" ]] && printf 'npm' && return
  [[ -f "${root}/bun.lockb" ]] && printf 'bun' && return
}

# extract build/test/lint commands from package.json scripts
extract_pkg_commands() {
  local root=$1
  local pkg_json="${root}/package.json"
  [[ ! -f "$pkg_json" ]] && printf 'null null null null' && return

  local build test lint dev
  build=$(jq -r '.scripts.build // "null"' < "$pkg_json" 2>/dev/null || printf 'null')
  test=$(jq -r '.scripts.test // "null"' < "$pkg_json" 2>/dev/null || printf 'null')
  lint=$(jq -r '.scripts.lint // "null"' < "$pkg_json" 2>/dev/null || printf 'null')
  dev=$(jq -r '(.scripts.dev // .scripts.start // "null")' < "$pkg_json" 2>/dev/null || printf 'null')

  # prefix with package manager
  local pm
  pm=$(detect_package_manager "$root")
  [[ -z "${pm:-}" ]] && pm='npm'

  local -A cmds=([build]="$build" [test]="$test" [lint]="$lint" [dev]="$dev")
  for k in build test lint dev; do
    local v="${cmds[$k]}"
    if [[ "$v" != "null" && -n "$v" ]]; then
      cmds[$k]="${pm} run ${v}"
      # shortcut: if the script value is just "test", use "npm test" not "npm run test"
      [[ "$k" == "test" && "$v" == "test" ]] && cmds[$k]="${pm} test"
    fi
  done

  printf '%s\n%s\n%s\n%s' "${cmds[build]}" "${cmds[test]}" "${cmds[lint]}" "${cmds[dev]}"
}

# scan project and produce memory JSON
# prints JSON to stdout
scan_project() {
  local root=$1

  local langs
  langs=$(detect_languages "$root")

  local pm
  pm=$(detect_package_manager "$root" || true)

  local -a cmds
  mapfile -t cmds < <(extract_pkg_commands "$root")
  local build_cmd="${cmds[0]:-null}"
  local test_cmd="${cmds[1]:-null}"
  local lint_cmd="${cmds[2]:-null}"
  local dev_cmd="${cmds[3]:-null}"

  # null-ify "null" string
  [[ "$build_cmd" == "null" ]] && build_cmd='null' || build_cmd="\"${build_cmd}\""
  [[ "$test_cmd" == "null" ]] && test_cmd='null' || test_cmd="\"${test_cmd}\""
  [[ "$lint_cmd" == "null" ]] && lint_cmd='null' || lint_cmd="\"${lint_cmd}\""
  [[ "$dev_cmd" == "null" ]] && dev_cmd='null' || dev_cmd="\"${dev_cmd}\""
  [[ -z "${pm:-}" ]] && pm='null' || pm="\"${pm}\""

  local now_ms=$(( EPOCHREALTIME * 1000 ))
  # integer ms: EPOCHREALTIME is float, multiply and truncate
  printf -v now_ms '%d' "${now_ms}"

  jq -n \
    --argjson langs "$langs" \
    --argjson now "$now_ms" \
    --arg root "$root" \
    --argjson pm "${pm}" \
    --argjson build_cmd "$build_cmd" \
    --argjson test_cmd "$test_cmd" \
    --argjson lint_cmd "$lint_cmd" \
    --argjson dev_cmd "$dev_cmd" \
    '{
      version: "1.0",
      projectRoot: $root,
      lastScanned: $now,
      techStack: {
        languages: $langs,
        frameworks: [],
        packageManager: $pm
      },
      build: {
        buildCommand: $build_cmd,
        testCommand: $test_cmd,
        lintCommand: $lint_cmd,
        devCommand: $dev_cmd
      },
      conventions: {namingStyle: null, importStyle: null, testPattern: null},
      structure: {isMonorepo: false, workspaces: []},
      customNotes: [],
      userDirectives: [],
      hotPaths: [],
      directoryMap: {}
    }'
}

# merge existing memory with freshly-scanned data (preserve userDirectives/hotPaths/customNotes)
# params: existing_json new_json
merge_memory() {
  local existing=$1 fresh=$2
  jq -n \
    --argjson existing "$existing" \
    --argjson fresh "$fresh" \
    '$fresh |
      .userDirectives = ($existing.userDirectives // []) |
      .hotPaths = ($existing.hotPaths // []) |
      .customNotes = ($existing.customNotes // []) |
      .directoryMap = ($existing.directoryMap // {})'
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

memory_file="${project_root}/${_MEMORY_FILE}"
omc_dir="${project_root}/.omc"

existing_memory=
if [[ -f "$memory_file" ]]; then
  existing_memory=$(< "$memory_file" 2>/dev/null || true)
fi

# check staleness
needs_scan=true
if [[ -n "${existing_memory:-}" ]]; then
  last_scanned=$(printf '%s' "$existing_memory" | jq -r '.lastScanned // 0' 2>/dev/null || printf '0')
  # validate required fields
  valid=$(printf '%s' "$existing_memory" | jq -r '
    if (.version != null and .projectRoot != null and .lastScanned != null) then "yes" else "no" end
  ' 2>/dev/null || printf 'no')

  if [[ "$valid" == "yes" ]] && ! is_stale "$last_scanned" 2>/dev/null; then
    needs_scan=false
  fi
fi

if [[ "$needs_scan" == "true" ]]; then
  fresh=$(scan_project "$project_root" 2>/dev/null || true)
  if [[ -n "${fresh:-}" ]]; then
    if [[ -n "${existing_memory:-}" ]]; then
      fresh=$(merge_memory "$existing_memory" "$fresh" 2>/dev/null || printf '%s' "$fresh")
    fi
    mkdir -p "$omc_dir" 2>/dev/null || true
    printf '%s\n' "$fresh" > "$memory_file" 2>/dev/null || true
  fi
fi

printf '%s\n' "$_PASS"
