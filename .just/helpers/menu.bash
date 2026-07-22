#!/usr/bin/env bash
# menu.bash -- the GUIDED command builder (gum only, never fzf).
# Full grouped recipe list via a self-updating `just --dump` + jq feed. Pick a
# recipe by fuzzy name; parametrized recipes prompt each argument; confirm; run.
# For someone who does NOT already know the recipe name.
set -uo pipefail
trap 'exit 130' INT TERM HUP

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

has gum || die 'gum required for the menu (brew install gum) -- try: just fzf'
has jq || die 'jq required for the menu (brew install jq)'

GROUP_ORDER=(meta install build dev run test bench lint verify docs release clean git omc util misc)

# Emit "name<TAB>group<TAB>doc<TAB>params" for every public recipe.
recipe_feed() {
  just --dump --dump-format json 2> /dev/null | jq -r '
    .recipes | to_entries[]
    | select(.key | startswith("_") | not)
    | select(.key != "default")
    | select([.value.attributes[]? | strings] | index("private") | not)
    | [ .key,
        (([.value.attributes[]? | objects | .group] | first) // "misc"),
        (.value.doc // ""),
        ([.value.parameters[]?
          | .name + (if .kind == "star" or .kind == "plus" then "*"
                     elif .default != null then "?"
                     else "" end)] | join(" "))
      ] | @tsv'
}

# Build a group-ordered, aligned display list. Column: name | [group] | doc.
build_display() {
  local -A rows=()
  local name grp doc params
  while IFS=$'\t' read -r name grp doc params; do
    [[ -z "$name" ]] && continue
    local label
    printf -v label '%-22s %s[%s]%s %s' "$name" "$C_CYAN" "$grp" "$C_RESET" "$doc"
    rows["$grp"]+="${label}"$'\n'
  done < <(recipe_feed)
  local g seen=()
  for g in "${GROUP_ORDER[@]}"; do
    [[ -n "${rows[$g]:-}" ]] && printf '%s' "${rows[$g]}"
    seen+=("$g")
  done
  for g in "${!rows[@]}"; do
    [[ " ${seen[*]} " == *" $g "* ]] && continue
    printf '%s' "${rows[$g]}"
  done
}

# Params for a given recipe (name<TAB>...<TAB>params column).
params_of() {
  local want="$1" name grp doc params
  while IFS=$'\t' read -r name grp doc params; do
    [[ "$name" == "$want" ]] && {
      printf '%s' "$params"
      return
    }
  done < <(recipe_feed)
}

header="$(printf '%soh-my-claudecode%s  %sguided menu%s  ·  type to filter · esc esc quits' \
  "$C_BOLD$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET")"

while true; do
  height=$(($(term_lines) - 8))
  ((height < 8)) && height=8
  printf '\n' # spacer; gum redraws its own region inline (never clear)
  rc=0
  choice="$(build_display | gum filter --no-fuzzy --reverse --height="$height" \
    --placeholder='type a recipe…' --header="$header" --indicator='▌' \
    --indicator.foreground 6 --match.foreground 6 --header.foreground 3 \
    --prompt ' › ' --prompt.foreground 6)" || rc=$?
  ((rc == 130)) && exit 130
  ((rc != 0)) && exit 0
  [[ -z "$choice" ]] && exit 0

  recipe="${choice%% *}"
  [[ -z "$recipe" || "$recipe" == '['* ]] && continue

  # Show the recipe body before running.
  if has bat; then
    just --show "$recipe" 2> /dev/null | bat --language=make --style=plain --color=always ||
      just --show "$recipe" 2> /dev/null || true
  else
    just --show "$recipe" 2> /dev/null || true
  fi

  # Prompt each parameter.
  args=()
  params="$(params_of "$recipe")"
  if [[ -n "$params" ]]; then
    for p in $params; do
      optional=0
      [[ "$p" == *'?' || "$p" == *'*' ]] && optional=1
      pname="${p%[?*]}"
      rc=0
      val="$(gum input --placeholder="value for <$pname>${optional:+  (optional, empty to skip)}" \
        --prompt=" ❯ $pname " --prompt.foreground 6)" || rc=$?
      ((rc == 130)) && {
        args=()
        continue 2
      }
      if [[ -z "$val" ]]; then
        ((optional == 1)) && break # let just fill remaining defaults
        # required param with empty input: abort this selection
        continue 2
      fi
      # variadic input word-splits into separate args
      if [[ "$p" == *'*' ]]; then
        # shellcheck disable=SC2206
        args+=($val)
      else
        args+=("$val")
      fi
    done
  fi

  if gum confirm "run: just $recipe ${args[*]:-}" --prompt.foreground 6; then
    exec just "$recipe" "${args[@]+"${args[@]}"}"
  fi
done
