#!/usr/bin/env bash
# info-screen.bash -- the bare-`just` splash: identity + facts + tool summary,
# then a short countdown offering the menu / fzf launchers. Appends inline;
# NEVER clears the screen or destroys scrollback (house style Iron Rule 5).
# Modes: (default) interactive countdown · --static no-countdown render.
set -uo pipefail

# shellcheck source-path=SCRIPTDIR source=lib.bash
source "$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)/lib.bash"
cd "$REPO_ROOT" || exit 1

SPLASH_SECS="${JUST_SPLASH_SECS:-5}"
STATIC=0
[[ "${1:-}" == "--static" ]] && STATIC=1

restore() { is_tty && tput cnorm 2> /dev/null || true; }
trap 'restore' EXIT
trap 'restore; exit 130' INT TERM HUP

banner() {
  local name='oh-my-claudecode'
  if has figlet; then
    figlet -f smslant "$name" 2> /dev/null ||
      figlet -f slant "$name" 2> /dev/null ||
      figlet "$name" 2> /dev/null ||
      printf '%s\n' "$name"
  else
    printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$name" "$C_RESET"
  fi
}

facts_block() {
  printf '%sversion%s   %s\n' "$C_DIM" "$C_RESET" "$(fact_version)"
  printf '%sbranch%s    %s\n' "$C_DIM" "$C_RESET" "$(fact_branch)"
  printf '%shead%s      %s\n' "$C_DIM" "$C_RESET" "$(fact_head)"
  printf '%sdirty%s     %s file(s)\n' "$C_DIM" "$C_RESET" "$(fact_dirty)"
}

inventory_block() {
  printf '%sagents%s    %s\n' "$C_DIM" "$C_RESET" "$(fact_agents)"
  printf '%sskills%s    %s\n' "$C_DIM" "$C_RESET" "$(fact_skills)"
  printf '%scommands%s  %s\n' "$C_DIM" "$C_RESET" "$(fact_commands)"
  printf '%ssrc .ts%s   %s\n' "$C_DIM" "$C_RESET" "$(fact_src)"
  printf '%stests%s     %s\n' "$C_DIM" "$C_RESET" "$(fact_tests)"
}

tools_block() {
  printf '%stoolchain%s %s\n' "$C_DIM" "$C_RESET" "$("$LIB_DIR/doctor.bash" --summary)"
  printf '%snode%s      %s\n' "$C_DIM" "$C_RESET" "$(node -v 2> /dev/null || echo '(missing)')"
  printf '%s%-8s%s  %s\n' "$C_DIM" "$PM" "$C_RESET" "$("$PM" -v 2> /dev/null || echo '(missing)')"
}

render() {
  local cols
  cols="$(term_cols)"
  printf '\n'
  printf '%s\n' "$(banner)"
  if has gum && ((cols >= 96)); then
    local f i t
    f="$(facts_block)"
    i="$(inventory_block)"
    t="$(tools_block)"
    local box_f box_i box_t
    box_f="$(gum style --border rounded --border-foreground 6 --padding '0 2' \
      --margin '0 1 0 0' "$f")"
    box_i="$(gum style --border rounded --border-foreground 6 --padding '0 2' \
      --margin '0 1 0 0' "$i")"
    if ((cols >= 130)); then
      box_t="$(gum style --border rounded --border-foreground 6 --padding '0 2' "$t")"
      gum join --horizontal --align top "$box_f" "$box_i" "$box_t"
    else
      gum join --horizontal --align top "$box_f" "$box_i"
    fi
  else
    printf '%s── repo ──%s\n' "$C_BOLD" "$C_RESET"
    facts_block
    printf '\n%s── inventory ──%s\n' "$C_BOLD" "$C_RESET"
    inventory_block
  fi
  printf '\n'
}

hint_line() {
  printf '%s⏎/m%s menu   %sf%s fzf   %sany key%s shell   %sjust help%s full list\n' \
    "$C_BOLD$C_CYAN" "$C_RESET" "$C_BOLD$C_CYAN" "$C_RESET" \
    "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
}

# ── Degrade to static when non-tty / tiny / no gum ────────────────────────────
cols="$(term_cols)"
scr_lines="$(term_lines)"
if ((STATIC == 1)) || ! is_tty || ((cols < 78)) || ((scr_lines < 24)) || ! has gum; then
  render
  hint_line
  exit 0
fi

# ── Interactive countdown ─────────────────────────────────────────────────────
render
drain_tty_input
tput civis 2> /dev/null || true
key='' action='timeout'
remaining="$SPLASH_SECS"
while ((remaining > 0)); do
  printf '\r%s  starting shell in %ss  %s(⏎ menu · f fzf · any key = now)%s%s' \
    "$C_REV" "$remaining" "$C_RESET$C_DIM" "$C_RESET" "$(tput el 2> /dev/null || true)"
  rc=0
  read -rsn1 -t 1 key || rc=$?
  if ((rc == 0)); then
    action='key'
    break
  elif ((rc == 1)); then
    action='eof' # stdin closed: fall through to shell
    break
  fi
  ((remaining--))
done
printf '\r%s\n' "$(tput el 2> /dev/null || true)"
restore

if [[ "$action" == 'timeout' ]]; then
  "$LIB_DIR/doctor.bash" --factoid
  exit 0
fi
if [[ "$action" == 'eof' ]]; then
  exit 0
fi
case "$key" in
  '' | m | M) exec just menu ;; # Enter (empty on -n1) or m
  f | F) exec just fzf ;;
  *) exit 0 ;; # any other key -> drop to shell now
esac
