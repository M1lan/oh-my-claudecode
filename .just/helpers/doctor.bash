#!/usr/bin/env bash
# doctor.bash -- toolchain audit for oh-my-claudecode.
# Tiers: required (exit non-zero if missing), recommended, optional.
# Modes: (default) full table · --summary one-liner · --factoid single fact ·
#        --install gum multi-select brew install of missing items.
set -uo pipefail
trap 'exit 130' INT TERM HUP

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

# ── Catalogue ─────────────────────────────────────────────────────────────────
REQUIRED=(node "$PM" git)
RECOMMENDED=(rg fd bat jq fzf gum watchexec gh)
OPTIONAL=(dust rumdl shellcheck shfmt typos tokei scc)

declare -A PKG=(
  [node]='node' ["$PM"]='corepack (corepack enable)' [git]='git'
  [rg]='ripgrep' [fd]='fd' [bat]='bat' [jq]='jq' [fzf]='fzf' [gum]='gum'
  [watchexec]='watchexec' [gh]='gh' [dust]='dust' [rumdl]='rumdl (cargo)'
  [shellcheck]='shellcheck' [shfmt]='shfmt' [typos]='typos-cli (cargo)'
  [tokei]='tokei' [scc]='scc'
)
declare -A WHY=(
  [node]='JS runtime' ["$PM"]='package manager (canonical)' [git]='version control'
  [rg]='fast search (menu/search)' [fd]='file discovery (helpers)'
  [bat]='syntax-highlighted previews' [jq]='JSON facts + self-updating menu'
  [fzf]='fzf launcher + pickers' [gum]='guided menu TUI'
  [watchexec]='just watch' [gh]='PR + CI recipes' [dust]='bundle-size report'
  [rumdl]='markdown lint' [shellcheck]='shell lint (helpers/scripts)'
  [shfmt]='shell format (helpers)' [typos]='spell check' [tokei]='loc report'
  [scc]='loc report (fallback)'
)

# Return a tool's version string, one line. Handles the known formats.
version_of() {
  local t="$1" v=''
  case "$t" in
    shellcheck)
      # version number lives on the second line: "version: 0.11.0"
      v="$("$t" --version 2> /dev/null | rg -No 'version: ([0-9.]+)' -r '$1' | head -1)"
      ;;
    "$PM" | node)
      v="$("$t" --version 2> /dev/null | head -1)"
      ;;
    *)
      v="$("$t" --version 2> /dev/null | head -1)"
      ;;
  esac
  printf '%s' "${v:-installed}"
}

# ── Full table ────────────────────────────────────────────────────────────────
render_table() {
  local miss=0 t
  printf '%s── required ──%s\n' "$C_BOLD" "$C_RESET"
  for t in "${REQUIRED[@]}"; do
    if has "$t"; then
      printf '  %s✓%s %-12s %s%s%s\n' "$C_GREEN" "$C_RESET" "$t" \
        "$C_DIM" "$(version_of "$t")" "$C_RESET"
    else
      printf '  %s✗%s %-12s %sMISSING%s -- %s (brew install %s)\n' \
        "$C_RED" "$C_RESET" "$t" "$C_RED" "$C_RESET" "${WHY[$t]}" "${PKG[$t]}"
      ((miss++))
    fi
  done
  local tier
  for tier in RECOMMENDED OPTIONAL; do
    local -n arr="$tier"
    printf '\n%s── %s ──%s\n' "$C_BOLD" "${tier,,}" "$C_RESET"
    for t in "${arr[@]}"; do
      if has "$t"; then
        printf '  %s✓%s %-12s %s%s%s\n' "$C_GREEN" "$C_RESET" "$t" \
          "$C_DIM" "$(version_of "$t")" "$C_RESET"
      else
        printf '  %s·%s %-12s %soptional%s -- %s (brew install %s)\n' \
          "$C_YELLOW" "$C_RESET" "$t" "$C_DIM" "$C_RESET" "${WHY[$t]}" "${PKG[$t]}"
      fi
    done
  done
  printf '\n'
  if ((miss > 0)); then
    printf '%s%d required tool(s) missing.%s Run: just doctor --install\n' \
      "$C_RED" "$miss" "$C_RESET" >&2
    return 1
  fi
  printf '%sdoctor: all required tools present%s\n' "$C_GREEN" "$C_RESET"
}

# ── --summary : one line for the splash ───────────────────────────────────────
render_summary() {
  local t ok=0 total=0 rmiss=0
  for t in "${REQUIRED[@]}"; do
    ((total++))
    if has "$t"; then ((ok++)); else ((rmiss++)); fi
  done
  for t in "${RECOMMENDED[@]}" "${OPTIONAL[@]}"; do
    ((total++))
    has "$t" && ((ok++))
  done
  printf '%d/%d tools present' "$ok" "$total"
  ((rmiss > 0)) && printf ' (%d required MISSING)' "$rmiss"
  printf '\n'
}

# ── --factoid : the single most important line for the splash timeout ─────────
render_factoid() {
  local t
  for t in "${REQUIRED[@]}"; do
    has "$t" || {
      printf 'missing required %s -- brew install %s\n' "$t" "${PKG[$t]}"
      return
    }
  done
  for t in "${RECOMMENDED[@]}"; do
    has "$t" || {
      printf '%s not installed -- brew install %s\n' "$t" "${PKG[$t]}"
      return
    }
  done
  if [[ ! -d "$REPO_ROOT/dist" ]]; then
    printf 'no dist/ yet -- just build\n'
    return
  fi
  if (($(fact_dirty) > 0)); then
    printf 'working tree dirty -- just verify before you push\n'
    return
  fi
  printf 'all green -- just v runs the full pre-push gate\n'
}

# ── --install : gum multi-select of missing, then brew install ────────────────
render_install() {
  has gum || die 'gum required for --install (brew install gum)'
  has brew || die 'brew not found; install missing tools manually'
  local t missing=()
  for t in "${REQUIRED[@]}" "${RECOMMENDED[@]}" "${OPTIONAL[@]}"; do
    has "$t" || missing+=("$t")
  done
  ((${#missing[@]} > 0)) || {
    printf '%snothing to install -- everything present%s\n' "$C_GREEN" "$C_RESET"
    return 0
  }
  local labels=() pick
  for t in "${missing[@]}"; do labels+=("$t  --  ${WHY[$t]:-}"); done
  local chosen
  chosen="$(printf '%s\n' "${labels[@]}" |
    gum choose --no-limit --header='select tools to brew install (space, enter)' \
      --header.foreground 3 --cursor.foreground 6)" || return 0
  [[ -z "$chosen" ]] && return 0
  local formulas=()
  while IFS= read -r pick; do
    [[ -z "$pick" ]] && continue
    t="${pick%%  --  *}"
    formulas+=("${PKG[$t]%% *}")
  done <<< "$chosen"
  ((${#formulas[@]} > 0)) || return 0
  gum spin --title="brew install ${formulas[*]}" -- \
    brew install "${formulas[@]}"
  printf '%sinstalled: %s%s\n' "$C_GREEN" "${formulas[*]}" "$C_RESET"
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  --summary) render_summary ;;
  --factoid) render_factoid ;;
  --install) render_install ;;
  '' | --full) render_table ;;
  *) die "unknown doctor mode: $1 (use --summary|--factoid|--install)" ;;
esac
