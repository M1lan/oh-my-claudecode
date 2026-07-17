# shellcheck shell=bash disable=SC2034
# lib.bash -- sourced library for oh-my-claudecode Justfile helpers.
# SOURCED, never executed: no shebang. Carries the Bash 5.3 guard so every
# helper that sources it inherits the floor. Provides tput default colors,
# tty/term helpers, project facts (parsed from files, never a compiler), and
# small utilities. House style v3: terminal-default colors only, never clear.

# ── Bash 5.3 floor (major + minor, never the weak >= 5) ───────────────────────
((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))) || {
  printf 'error: GNU Bash >= 5.3 required, got %s\n' "$BASH_VERSION" >&2
  printf 'hint : brew install bash  (/opt/homebrew/bin must precede /bin in PATH)\n' >&2
  exit 1
}

set -o pipefail

# ── Locations ─────────────────────────────────────────────────────────────────
LIB_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)"
REPO_ROOT="$(cd -- "$LIB_DIR/../.." && pwd)"
readonly LIB_DIR REPO_ROOT

# Single-source package manager (mirrors Justfile PM + package.json).
PM="pnpm"
readonly PM

# ── tty + terminal size ───────────────────────────────────────────────────────
is_tty() { [[ -t 1 ]]; }

# Terminal width/height. Precedence: COLUMNS/LINES env (test override) >
# stty on /dev/tty > tput > 80x24. stty size reports "0 0" on degenerate ptys,
# so reject non-positive values.
_term_size() {
  local cols lines
  cols="${COLUMNS:-0}"
  lines="${LINES:-0}"
  if ((cols <= 0 || lines <= 0)) && [[ -r /dev/tty ]]; then
    read -r lines cols < <(stty size 2> /dev/null < /dev/tty || printf '0 0')
  fi
  ((cols > 0)) || cols="$(tput cols 2> /dev/null || printf 0)"
  ((lines > 0)) || lines="$(tput lines 2> /dev/null || printf 0)"
  ((cols > 0)) || cols=80
  ((lines > 0)) || lines=24
  printf '%s %s' "$cols" "$lines"
}
term_cols() {
  local c l
  read -r c l < <(_term_size)
  printf '%s' "$c"
}
term_lines() {
  local c l
  read -r c l < <(_term_size)
  printf '%s' "$l"
}

# ── Colors: terminal defaults via tput ONLY (indices 0-7) ─────────────────────
_ncolors=0
if is_tty && [[ -z "${NO_COLOR:-}" ]]; then
  _ncolors="$(tput colors 2> /dev/null || printf 0)"
fi
if ((_ncolors >= 8)); then
  C_RESET="$(tput sgr0)" C_BOLD="$(tput bold)" C_DIM="$(tput dim)"
  C_REV="$(tput rev)"
  C_RED="$(tput setaf 1)" C_GREEN="$(tput setaf 2)" C_YELLOW="$(tput setaf 3)"
  C_BLUE="$(tput setaf 4)" C_MAGENTA="$(tput setaf 5)" C_CYAN="$(tput setaf 6)"
else
  C_RESET='' C_BOLD='' C_DIM='' C_REV=''
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN=''
fi

# ── Small utilities ───────────────────────────────────────────────────────────
has() { command -v "$1" > /dev/null 2>&1; }

die() {
  printf '%serror:%s %s\n' "${C_RED}" "${C_RESET}" "$*" >&2
  exit 1
}

info() { printf '%s\n' "$*" >&2; }

# Drain terminal query replies (DSR/OSC) that gum/lipgloss provoke, so the next
# `read -rsn1` does not swallow an ESC from the terminal's reply. No-op off-tty.
drain_tty_input() {
  is_tty || return 0
  local _junk
  while read -rsn1 -t 0.02 _junk 2> /dev/null; do :; done
}

# ── Project facts (file-parsed, splash-safe: no tsc/node build spawns) ─────────
fact_version() {
  if has jq; then
    jq -r '.version // "?"' "$REPO_ROOT/package.json" 2> /dev/null || printf '?'
  else
    printf '?'
  fi
}

fact_branch() {
  local b
  b="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2> /dev/null || printf '?')"
  # jj-colocated repos sit on detached HEAD -> literal "HEAD".
  if [[ "$b" == "HEAD" && -d "$REPO_ROOT/.jj" ]] && has jj; then
    b="jj @ $(jj --ignore-working-copy -R "$REPO_ROOT" log -r @ --no-graph \
      -T 'change_id.shortest(8)' 2> /dev/null || printf '?')"
  fi
  printf '%s' "$b"
}

fact_head() {
  git -C "$REPO_ROOT" log -1 --pretty='%h %s' 2> /dev/null | cut -c1-48 || printf '?'
}

fact_dirty() {
  local -a lines=()
  mapfile -t lines < <(git -C "$REPO_ROOT" status --porcelain 2> /dev/null)
  printf '%s' "${#lines[@]}"
}

# Count files under DIR matching fd PATTERN (+ optional fd flags). Uses an
# array so the count is always exact and the function always exits clean
# (grep -c prints "0" AND exits 1 on no matches -> double-count trap; avoided).
# Signature: _count_files DIR PATTERN [fd flags...]  ->  fd <flags> <pat> <dir>
_count_files() {
  local dir="$1" pat="$2"
  shift 2
  [[ -d "$REPO_ROOT/$dir" ]] || {
    printf 0
    return
  }
  has fd || {
    printf '?'
    return
  }
  local -a matches=()
  mapfile -t matches < <(cd "$REPO_ROOT" && fd "$@" "$pat" "$dir" 2> /dev/null)
  printf '%s' "${#matches[@]}"
}

fact_agents() { _count_files agents '.' -e md -E AGENTS.md; }
fact_skills() { _count_files skills 'SKILL\.md' -t f; }
fact_commands() { _count_files commands '.' -e md; }
fact_src() { _count_files src '.' -e ts; }
fact_tests() { _count_files tests '\.test\.ts$' -t f; }
