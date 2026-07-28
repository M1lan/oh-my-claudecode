# Driving a terminal from a script — rmux and Ghostty

How an agent starts work in a terminal surface **from anywhere**: inside a
multiplexer, outside one, or on a box with no multiplexer at all. Written from
measurements taken 2026-07-26, including the two ways it goes wrong.

Reference implementation: [`omc-next.bash`](omc-next.bash) in this directory.

```bash
./omc-next.bash                       # default: next bead, best transport
./omc-next.bash --dry-run             # show the payload, send nothing
./omc-next.bash --self-test           # prove delivery end-to-end
./omc-next.bash -t ghostty --list     # enumerate Ghostty windows
```

## The one rule that shapes everything

**Never launch a new Ghostty instance or window from an agent.** Operator law,
no exceptions (`~/.claude/IMPORTANT.md`). Every technique here drives surfaces
that already exist. If none is usable, the correct outcome is a loud error, not
a new window.

## Transport ladder

Try in this order. Each rung is strictly safer than the one below it.

| Rung | Transport | Addressing | Focus-dependent |
|---|---|---|---|
| 1 | `rmux` | pane id (`%27`) | no |
| 2 | `tmux` | pane id | no |
| 3 | Ghostty + `osascript` | window title | **yes** |

Rungs 1 and 2 are the same API — rmux is a tmux shim, so every verb below works
against either binary. Resolve once, then use the variable:

```bash
mux_bin() {
  local candidate
  for candidate in rmux tmux; do
    command -v "$candidate" > /dev/null 2>&1 && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}
MUX="$(mux_bin)" || die 'no multiplexer'
```

## Rung 1-2: multiplexer (preferred, deterministic)

`send-keys` addresses a pane directly. Nothing about window focus, the frontmost
app, or what the human is doing can misroute it. This is why it outranks the
desktop path.

```bash
# Enumerate
"$MUX" list-sessions -F '#{session_name}'
"$MUX" find-panes                      # rmux extra; tmux: list-panes -a -F '...'

# Create or reuse, then get a pane id
"$MUX" new-session -d -s "$name" -c "$dir"
pane="$("$MUX" new-window -t "$session" -c "$dir" -P -F '#{pane_id}')"

# Send: literal text, then a separate Enter
"$MUX" send-keys -t "$pane" -l "source /path/to/cmd.bash"
"$MUX" send-keys -t "$pane" Enter

# Land the human on it
"$MUX" switch-client -t "$session"     # when already inside a mux
exec "$MUX" attach -t "$session"       # when outside one
```

### Trap: `has-session` matches loosely, `new-window` does not

```bash
rmux has-session -t omc-repo-mymain    # exit 0 -- but only a PREFIX matched
rmux new-window  -t omc-repo-mymain    # "session not found"
```

A session named `omc-repo-mymain-20260726013419` satisfies `has-session` for the
bare prefix and then fails every command that needs the real name. Compare
against the actual list instead:

```bash
while IFS= read -r name; do
  [[ $name == "$base" ]] && { found="$name"; break; }
  [[ -z $prefixed && $name == "${base}-"* ]] && prefixed="$name"
done < <("$MUX" list-sessions -F '#{session_name}')
```

Treating a timestamped `<base>-<stamp>` session as ours is usually what you want:
it reuses the operator's existing session for that repo instead of littering.

## Rung 3: Ghostty via osascript (last resort)

Ghostty ships **no AppleScript dictionary** — there is no `do script`. Control
goes through System Events accessibility APIs: read window titles, focus one,
type into it. Requires Accessibility permission for the calling app; verify with

```bash
osascript -e 'tell application "System Events" to return UI elements enabled'   # -> true
```

### Process name — ask, do not assume

It is lowercase `ghostty` on this build, capitalised on others:

```bash
proc="$(osascript -e 'tell application "System Events" \
  to get name of first process whose name contains "hostty"')"
```

### Window titles are the only routing channel

The zsh prompt stamps every title (`~/.config/mein-zsh/home/.zshrc`):

```text
👻 ~/mysrc/oh-my-claudecode ⟦s010⟧     plain shell, shell id s010
👻 ~/.config ⟦s029*⟧                    trailing * = shell is inside a multiplexer
Quick Terminal                          the dropdown overlay
```

Read them with:

```bash
osascript -e "tell application \"System Events\" to tell process \"$proc\" \
  to get name of every window" | tr ',' '\n' | sed 's/^ *//; s/ *$//'
```

### Trap: window indices reshuffle, and AXRaise does not focus

Two failures, both measured:

- **Indices are front-to-back order.** They change the instant anything raises a
  window, so an index captured a moment ago addresses a different window by the
  time keys fly. Route by title, resolve to an index inside a single osascript.
- **`perform action "AXRaise"` reorders without giving key focus.** Keystrokes
  still go wherever focus was. Setting `AXMain` does focus the window.

Verify focus by **`AXMain`, never by "window 1"** — the Quick Terminal overlay
sits at index 1 while never being the main window:

```text
1 main=false :: Quick Terminal
2 main=true  :: 👻 ~/mysrc/oh-my-claudecode ⟦s010⟧      <- the real target
```

### Trap: a shell-looking title can be an agent TUI

This is the one that bites hardest. zsh sets the title *before* an agent starts,
and Claude Code does not overwrite it. So a window reading
`👻 ~/mysrc/oh-my-claudecode ⟦s010⟧` may be running a Claude session, and
keystrokes sent there become **chat messages**, not commands.

Measured twice on 2026-07-26: an auto-picked "plain shell" target was the window
hosting the very Claude session running the script. Both payloads arrived in the
chat composer.

Consequences baked into `omc-next.bash`:

1. **No auto-picking.** The ghostty transport requires `-w <hint>`; the operator
   names the target.
2. **Re-verify `AXMain` between typing and Return.** A human at the keyboard wins
   every race, so if focus moved after the text was typed, the Return is withheld
   and the worst case is inert text rather than a command run in the wrong shell.
3. **Verify by side effect, not by exit code.** osascript reports success for
   keystrokes it delivered into the void.

### Quoting: stage the command, type only a path

Both `send-keys` and `keystroke` mangle quotes, newlines and unicode. Write the
real command to a file and type one unmanglable word:

```bash
path="$HOME/tmp/omc-next-cmd-$$.bash"      # ~/tmp: scratch rule. Backups go to ~/backups.
{ printf 'rm -f -- %q\n' "$path"; printf '%s\n' "$body"; } > "$path"
# then send:  source $path
```

The generated file deletes itself on first line, so nothing accumulates.

## Verify by side effect

Never report delivery because a command exited 0. Have the remote shell prove it
ran, by writing a nonce, and poll for it:

```bash
# staged body
printf 'printf "delivered %%s\\n" %q > %q\n' "$nonce" "$HOME/tmp/selftest-$nonce"
# caller polls up to 15s for that file, then PASS or FAIL
```

`omc-next.bash --self-test` does exactly this. Current results on this machine:

| Transport | Result |
|---|---|
| rmux | PASS, repeatable |
| Ghostty + osascript | PASS on an idle desktop; FAILS while the operator is actively switching windows |

## Checklist for the next agent

- Multiplexer present? Use it. Do not touch osascript.
- No multiplexer? Starting one is authorized and beats keystroking blind.
- Forced onto Ghostty? Demand an explicit target, route by title, focus via
  `AXMain`, re-verify before Return, confirm by nonce.
- Never open a Ghostty window. Never claim delivery you did not observe.
