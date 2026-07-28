#!/usr/bin/env bash
# omc-next.bash -- launch the next OMC work session on a terminal surface,
#                  from anywhere: inside rmux, outside it, or with no rmux at all.
# Usage: ./omc-next.bash [-b BEAD] [-p PROMPT] [-t auto|rmux|ghostty] [-n] [-l] [--self-test]

if [[ -z ${BASH_VERSINFO+set} ]]; then
  printf 'error: this script requires bash\n' >&2
  exit 1
fi
((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 3))) || {
  printf 'error: bash 5.3+ required (found %s)\n' "$BASH_VERSION" >&2
  exit 1
}
set -uo pipefail
IFS=$' \t\n'
export LC_ALL=C
trap 'exit 130' INT TERM HUP

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || {
  printf 'error: cannot resolve repo root\n' >&2
  exit 1
}
readonly REPO_ROOT
readonly SCRATCH_DIR="${HOME}/tmp"
readonly DEFAULT_BEAD='oh-my-claudecode-5ki'

# Trace every resolver before editing: evidence first, edits second.
readonly DEFAULT_PROMPT='br show %BEAD%. Then trace every place .omc root is resolved in scripts/ and src/, and tell me which ones bypass state-root.mjs before changing anything.'

declare bead="$DEFAULT_BEAD"
declare prompt=''
declare transport='auto'
declare window_hint=''
declare -i dry_run=0
declare -i do_list=0
declare -i self_test=0

usage() {
  cat << 'EOF'
omc-next.bash -- launch the next OMC work session on a terminal surface.

Works from a fresh Ghostty window, from inside an rmux session, or on a machine
with no rmux at all. Never opens a new Ghostty window (operator law): with the
ghostty transport it drives an existing one.

Options:
  -b, --bead ID        beads issue to open       (default: oh-my-claudecode-5ki)
  -p, --prompt TEXT    first prompt for Claude   (default: derived from --bead)
  -t, --transport T    auto | rmux | ghostty     (default: auto)
  -w, --window HINT    ghostty target: shell-id tag (s010) or title substring
  -l, --list           list candidate surfaces and exit
  -n, --dry-run        show what would be sent, send nothing
      --self-test      prove the transport delivers keystrokes, then exit
  -h, --help           this text

Examples:
  ./omc-next.bash                          # default bead, auto transport
  ./omc-next.bash -b oh-my-claudecode-6o2  # different bead
  ./omc-next.bash -p 'run the full suite'  # custom prompt
  ./omc-next.bash -t ghostty -w s010       # target one Ghostty window
  ./omc-next.bash --self-test              # verify delivery end-to-end
EOF
}

log() { printf '%s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      -b | --bead)
        [[ -n ${2-} ]] || die "--bead needs a value"
        bead="$2"
        shift 2
        ;;
      -p | --prompt)
        [[ -n ${2-} ]] || die "--prompt needs a value"
        prompt="$2"
        shift 2
        ;;
      -t | --transport)
        [[ -n ${2-} ]] || die "--transport needs a value"
        transport="$2"
        shift 2
        ;;
      -w | --window)
        [[ -n ${2-} ]] || die "--window needs a value"
        window_hint="$2"
        shift 2
        ;;
      -l | --list)
        do_list=1
        shift
        ;;
      -n | --dry-run)
        dry_run=1
        shift
        ;;
      --self-test)
        self_test=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown option: $1 (try --help)" ;;
    esac
  done

  case "$transport" in
    auto | rmux | ghostty) ;;
    *) die "--transport must be auto, rmux or ghostty (got: $transport)" ;;
  esac
}

# ---------------------------------------------------------------------------
# Transport selection
# ---------------------------------------------------------------------------

# rmux is a tmux shim, so tmux answers the same verbs and is a clean fallback.
mux_bin() {
  local candidate
  for candidate in rmux tmux; do
    if command -v "$candidate" > /dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

have_ghostty() { [[ $OSTYPE == darwin* ]] && command -v osascript > /dev/null 2>&1; }
inside_mux() { [[ -n ${RMUX-} || -n ${TMUX-} ]]; }

# Prefer a multiplexer over the desktop: send-keys addresses a pane directly and
# does not care what has focus. The Ghostty path types into whatever window is
# focused, which a human at the keyboard can change mid-flight.
resolve_transport() {
  if [[ $transport != auto ]]; then
    printf '%s\n' "$transport"
    return 0
  fi
  if mux_bin > /dev/null; then
    printf 'rmux\n'
  elif have_ghostty; then
    log 'warning: no rmux or tmux found -- falling back to Ghostty keystrokes'
    printf 'ghostty\n'
  else
    die 'no usable transport: no rmux, no tmux, and no macOS osascript'
  fi
}

# ---------------------------------------------------------------------------
# Command staging
#
# The command is written to a file and only its path is typed. Keystroke and
# send-keys paths both mangle quotes, newlines and unicode; a one-word
# `source <path>` cannot be mangled.
# ---------------------------------------------------------------------------

stage_command() {
  local body="$1" nonce="$2" path
  path="${SCRATCH_DIR}/omc-next-cmd-${nonce}.bash"
  mkdir -p -- "$SCRATCH_DIR" || die "cannot create $SCRATCH_DIR"
  {
    printf '# generated by omc-next.bash -- safe to delete\n'
    printf 'rm -f -- %q\n' "$path"
    printf '%s\n' "$body"
  } > "$path" || die "cannot write $path"
  printf '%s\n' "$path"
}

build_launch_body() {
  local text="${prompt:-${DEFAULT_PROMPT//%BEAD%/$bead}}"
  printf 'cd %q || return 1\n' "$REPO_ROOT"
  printf 'omc --yolo %q\n' "$text"
}

build_selftest_body() {
  printf 'printf "delivered %%s\\n" %q > %q\n' "$1" "${SCRATCH_DIR}/omc-next-selftest-$1"
}

new_nonce() { printf '%s-%s\n' "$(date +%s)" "$$"; }

# ---------------------------------------------------------------------------
# rmux transport
# ---------------------------------------------------------------------------

rmux_session_name() {
  local branch
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2> /dev/null)" || branch='nogit'
  printf 'omc-%s-%s\n' "${REPO_ROOT##*/}" "${branch//[^A-Za-z0-9_-]/-}"
}

rmux_list_surfaces() {
  printf '== rmux sessions ==\n'
  "$MUX" ls 2> /dev/null || printf '(none)\n'
  printf '\n== rmux panes ==\n'
  "$MUX" find-panes 2> /dev/null || "$MUX" list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path}' 2> /dev/null || printf '(none)\n'
}

# Resolve the session to work in, exactly.
#
# `has-session -t NAME` matches loosely and answers yes for a mere prefix, while
# `new-window -t NAME` demands the exact name and fails. Comparing against the
# real name list avoids that trap. A timestamped session for the same repo and
# branch (`<base>-20260726013419`) counts as ours and gets reused.
rmux_find_session() {
  local base="$1" name prefixed=''
  while IFS= read -r name; do
    [[ $name == "$base" ]] && {
      printf '%s\n' "$name"
      return 0
    }
    [[ -z $prefixed && $name == "${base}-"* ]] && prefixed="$name"
  done < <("$MUX" list-sessions -F '#{session_name}' 2> /dev/null)

  [[ -n $prefixed ]] && printf '%s\n' "$prefixed"
  return 0
}

# Return "<session> <pane_id>" for a fresh pane, creating what is missing.
rmux_target_pane() {
  local base="$1" session pane
  session="$(rmux_find_session "$base")"

  if [[ -n $session ]]; then
    pane="$("$MUX" new-window -t "$session" -c "$REPO_ROOT" -P -F '#{pane_id}')" || return 1
  else
    session="$base"
    "$MUX" new-session -d -s "$session" -c "$REPO_ROOT" || return 1
    pane="$("$MUX" list-panes -t "$session" -F '#{pane_id}' 2> /dev/null | head -n 1)"
  fi

  [[ -n $pane ]] || return 1
  printf '%s %s\n' "$session" "$pane"
}

rmux_send() {
  local pane="$1" cmd_path="$2"
  "$MUX" send-keys -t "$pane" -l "source ${cmd_path}" || return 1
  "$MUX" send-keys -t "$pane" Enter || return 1
}

rmux_focus() {
  local session="$1"
  if inside_mux; then
    "$MUX" switch-client -t "$session" 2> /dev/null && return 0
    log "note: could not switch client; attach manually: $MUX attach -t $session"
    return 0
  fi
  log "attaching to $session (detach with your rmux prefix + d)"
  exec "$MUX" attach -t "$session"
}

run_rmux() {
  local body="$1" nonce="$2" base session pane target cmd_path
  base="$(rmux_session_name)"

  if ((dry_run)); then
    session="$(rmux_find_session "$base")"
    printf 'transport : rmux\nsession   : %s\nwould run :\n%s\n' "${session:-$base (new)}" "$body"
    return 0
  fi

  target="$(rmux_target_pane "$base")" || die "could not obtain a pane for session $base"
  read -r session pane <<< "$target"
  cmd_path="$(stage_command "$body" "$nonce")"
  rmux_send "$pane" "$cmd_path" || die "$MUX send-keys failed for pane $pane"
  log "sent to rmux ${session} pane ${pane}"

  ((self_test)) && return 0
  rmux_focus "$session"
}

# ---------------------------------------------------------------------------
# Ghostty transport (macOS, no rmux required)
#
# Ghostty ships no AppleScript dictionary, so control goes through System
# Events: read window titles, focus the chosen window, type into it. The zsh
# prompt tags every window title with a shell id -- `⟦s010⟧` plain, `⟦s010*⟧`
# when that shell sits inside a multiplexer -- which is the only routing
# channel osascript can see.
#
# Two traps, both hit during development:
#   * Window indices are front-to-back order and RESHUFFLE the moment anything
#     raises a window, so an index captured a moment ago addresses a different
#     window by the time keystrokes fly. Everything below routes by title.
#   * `perform action "AXRaise"` reorders windows without giving one key focus,
#     so keystrokes land wherever focus already was. Setting the AXMain
#     attribute does focus it; the result is verified before typing.
# ---------------------------------------------------------------------------

# The process name is lowercase "ghostty" on this build; other builds
# capitalise it. Ask rather than assume.
ghostty_proc_name() {
  local name
  name="$(osascript -e 'tell application "System Events" to get name of first process whose name contains "hostty"' 2> /dev/null)"
  [[ -n $name ]] || return 1
  printf '%s\n' "$name"
}

ghostty_window_titles() {
  local proc
  proc="$(ghostty_proc_name)" || return 1
  osascript -e "tell application \"System Events\" to tell process \"${proc}\" to get name of every window" 2> /dev/null |
    tr ',' '\n' |
    sed 's/^ *//; s/ *$//' |
    grep -v '^$'
}

ghostty_list_surfaces() {
  printf '== Ghostty windows ==\n'
  local -i i=0
  local title
  while IFS= read -r title; do
    i+=1
    printf '%2d  %s\n' "$i" "$title"
  done < <(ghostty_window_titles)
  ((i > 0)) || printf '(none -- is Ghostty running?)\n'
}

# Resolve the routing key for the target window. `--window` is MANDATORY here.
#
# Auto-picking was removed after it chose the window hosting the Claude session
# that ran this script. A window title keeps the shell pattern
# `👻 <cwd> ⟦sNNN⟧` that zsh set before an agent TUI launched inside it, so the
# title cannot prove a shell prompt is waiting. Typing into an agent TUI sends a
# chat message instead of running a command. The operator names the target.
ghostty_pick_key() {
  local title
  [[ -n $window_hint ]] || return 1

  while IFS= read -r title; do
    if [[ $title == *"$window_hint"* ]]; then
      printf '%s\n' "$(ghostty_title_key "$title")"
      return 0
    fi
  done < <(ghostty_window_titles)

  die "no Ghostty window matched hint: $window_hint"
}

# Reduce a title to its `sNNN` shell id when it has one, else use it whole.
ghostty_title_key() {
  local title="$1"
  if [[ $title =~ ⟦(s[0-9]+)\*?⟧ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$title"
  fi
}

# Focus the window whose title contains KEY, confirm it took, then type.
# Prints the focused title on success; fails loudly instead of typing blind.
ghostty_send() {
  local key="$1" cmd_path="$2" proc result
  proc="$(ghostty_proc_name)" || return 1

  result="$(
    osascript << EOF 2>&1
on run
  set theKey to "${key}"
  tell application "System Events" to tell process "${proc}"
    set frontmost to true
    set found to false
    repeat with i from 1 to (count of windows)
      if name of window i contains theKey then
        set value of attribute "AXMain" of window i to true
        set found to true
        exit repeat
      end if
    end repeat
    if not found then return "ERROR: no window matching " & theKey
  end tell
  delay 0.5
  -- Verify via AXMain, not window order: the Quick Terminal overlay sits at
  -- index 1 while never being the main window, so index checks misfire.
  set frontTitle to ""
  tell application "System Events" to tell process "${proc}"
    repeat with i from 1 to (count of windows)
      if (value of attribute "AXMain" of window i) is true then
        set frontTitle to name of window i
        exit repeat
      end if
    end repeat
  end tell
  if frontTitle is "" then return "ERROR: no main window after focusing " & theKey
  if frontTitle does not contain theKey then
    return "ERROR: focus landed on " & frontTitle
  end if
  tell application "System Events"
    keystroke "source ${cmd_path}"
  end tell
  -- Focus can move between verification and typing: a human at the keyboard
  -- wins every race. Re-check before Return so a lost race leaves inert text
  -- somewhere instead of executing a command in the wrong shell.
  set stillTitle to ""
  tell application "System Events" to tell process "${proc}"
    repeat with i from 1 to (count of windows)
      if (value of attribute "AXMain" of window i) is true then
        set stillTitle to name of window i
        exit repeat
      end if
    end repeat
  end tell
  if stillTitle does not contain theKey then
    return "ERROR: focus moved to " & stillTitle & " before Return; text typed but NOT executed"
  end if
  tell application "System Events" to key code 36
  return frontTitle
end run
EOF
  )"

  if [[ $result == ERROR:* || -z $result ]]; then
    printf '%s\n' "${result:-osascript returned nothing}" >&2
    return 1
  fi
  printf '%s\n' "$result"
}

run_ghostty() {
  local body="$1" nonce="$2" key cmd_path focused

  have_ghostty || die 'ghostty transport needs macOS with osascript'
  ghostty_proc_name > /dev/null || die 'Ghostty is not running (starting it is forbidden -- open a window yourself)'

  key="$(ghostty_pick_key)" || die "$(
    printf 'the ghostty transport needs an explicit target: -w <shell-id or title text>\n'
    printf 'List candidates:  %s -t ghostty --list\n' "${BASH_SOURCE[0]}"
    printf 'Pick a window sitting at a SHELL PROMPT. A title can still read\n'
    printf '"👻 ~/path ⟦sNNN⟧" while an agent TUI runs inside it, and keystrokes\n'
    printf 'would become chat messages there. Auto-picking is deliberately absent.\n'
  )"

  if ((dry_run)); then
    printf 'transport  : ghostty\nwindow key : %s\nwould run  :\n%s\n' "$key" "$body"
    return 0
  fi

  cmd_path="$(stage_command "$body" "$nonce")"
  log "focusing Ghostty window matching '${key}' -- hands off the keyboard"
  focused="$(ghostty_send "$key" "$cmd_path")" ||
    die 'osascript delivery failed (check Accessibility permission for the calling app)'
  log "sent to Ghostty window: ${focused}"
}

# ---------------------------------------------------------------------------
# Self-test: prove keystrokes actually landed rather than assuming it.
# ---------------------------------------------------------------------------

await_selftest() {
  local nonce="$1" marker="${SCRATCH_DIR}/omc-next-selftest-$1"
  local -i waited=0
  while ((waited < 15)); do
    if [[ -f $marker ]]; then
      printf 'self-test PASSED: %s\n' "$(< "$marker")"
      rm -f -- "$marker"
      return 0
    fi
    sleep 1
    waited+=1
  done
  printf 'self-test FAILED: %s never appeared after %ds\n' "$marker" "$waited" >&2
  return 1
}

main() {
  parse_args "$@"

  local chosen
  chosen="$(resolve_transport)" || exit 1

  if [[ $chosen == rmux ]]; then
    MUX="$(mux_bin)" || die 'neither rmux nor tmux is installed'
    readonly MUX
  fi

  if ((do_list)); then
    case "$chosen" in
      rmux) rmux_list_surfaces ;;
      ghostty) ghostty_list_surfaces ;;
    esac
    exit 0
  fi

  local nonce body
  nonce="$(new_nonce)"
  if ((self_test)); then
    body="$(build_selftest_body "$nonce")"
  else
    body="$(build_launch_body)"
  fi

  case "$chosen" in
    rmux) run_rmux "$body" "$nonce" ;;
    ghostty) run_ghostty "$body" "$nonce" ;;
  esac

  if ((self_test)) && ((dry_run == 0)); then
    await_selftest "$nonce" || exit 1
  fi
}

main "$@"
