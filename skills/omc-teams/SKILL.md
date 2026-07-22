---
name: omc-teams
description: CLI-team runtime for claude, codex, gemini, antigravity, grok, or cursor workers in tmux panes when you need process-based parallel execution
aliases: []
level: 4
---

# OMC Teams Skill

Spawn N CLI worker processes in tmux panes to execute tasks in parallel. Supports `claude`, `codex`, `gemini`, `antigravity`, `grok`, and `cursor` agent types. Cursor workers are executor-style only.

`/omc-teams` is a legacy compatibility skill for the CLI-first runtime: use `omc team ...` commands (not deprecated MCP runtime tools).

## Usage

```bash
/oh-my-claudecode:omc-teams N:claude "task description"
/oh-my-claudecode:omc-teams N:codex "task description"
/oh-my-claudecode:omc-teams N:gemini "task description"
/oh-my-claudecode:omc-teams N:antigravity "task description"
/oh-my-claudecode:omc-teams N:grok "task description"
/oh-my-claudecode:omc-teams N:cursor "implementation task description"
```

### Parameters

- **N** - Number of CLI workers (1-10)
- **agent-type** - `claude` (Claude CLI), `codex` (OpenAI Codex CLI), `gemini` (Google Gemini CLI; enterprise/API-key tier), `antigravity` (Antigravity CLI `agy`; Google's successor to the Gemini CLI), `grok` (xAI Grok CLI), or `cursor` (Cursor agent CLI; executor-style tasks only)
- **task** - Task description to distribute across all workers

### Examples

```bash
/omc-teams 2:claude "implement auth module with tests"
/omc-teams 2:codex "review the auth module for security issues"
/omc-teams 3:gemini "redesign UI components for accessibility"
/omc-teams 3:antigravity "redesign UI components for accessibility"
/omc-teams 1:grok "prototype an implementation approach"
/omc-teams 1:cursor "apply the implementation plan"
```

## Requirements

- **A tmux-compatible multiplexer** (`rmux` preferred, or `tmux`) must be installed and discoverable when running from a plain terminal; classic tmux sessions reuse the current surface. On POSIX, a plain `rmux` on PATH is driven in preference to `tmux`.
- **cmux is a last-resort fallback**, not the default. Even inside a cmux surface (`CMUX_SURFACE_ID` set without `$TMUX`), OMC prefers rmux/tmux when either is resolvable — since there is no live pane context to reuse, it creates a **detached** rmux/tmux session (same as a plain terminal) rather than splitting the cmux surface; native cmux splits are used only when no rmux/tmux binary is available.
- **claude** CLI: install and authenticate Claude Code using the [official setup instructions](https://code.claude.com/docs/en/setup); the legacy Anthropic npm package install path is deprecated for normal user installs.
- **codex** CLI: `npm install -g @openai/codex`
- **gemini** CLI: `npm install -g @google/gemini-cli` (enterprise/API-key tier)
- **antigravity** CLI: Install per the [official instructions](https://antigravity.google) (provides the `agy` binary) — verify with `agy --version`; Google's successor to the Gemini CLI
- **grok** CLI: install and authenticate the Grok CLI used by your environment
- **cursor** CLI: install and authenticate `cursor-agent`; if unavailable, report this setup requirement instead of silently falling back to Claude-only execution

## Workflow

### Phase 0: Verify prerequisites

Check the active multiplexer before claiming tmux is missing. If `$TMUX` is empty and `CMUX_SURFACE_ID` is also empty, check tmux explicitly:

```bash
command -v tmux >/dev/null 2>&1
```

- If the plain-terminal check fails for both `rmux` and `tmux`, report that **no tmux-compatible multiplexer is installed** and stop.
- If `$TMUX` is set, `omc team` can reuse the current tmux/rmux window/panes directly.
- If `$TMUX` is empty but `CMUX_SURFACE_ID` is set, OMC still **prefers rmux/tmux**: when either binary is resolvable it creates a **detached** rmux/tmux session (there is no live pane to reuse), and only falls back to **native cmux splits** when neither rmux nor tmux is available. Do **not** say tmux is missing or that they are "not inside tmux".
- If neither `$TMUX` nor `CMUX_SURFACE_ID` is set, report that the user is in a **plain terminal**. `omc team` can still launch a **detached rmux/tmux session**, but if they specifically want in-place pane/window topology they should start from a classic tmux/rmux session first.
- If you need to confirm the active tmux session, use:

```bash
tmux display-message -p '#S'
```

### Phase 1: Parse + validate input

Extract:

- `N` — worker count (1–10)
- `agent-type` — `claude|codex|gemini|grok|cursor`
- `task` — task description

Validate before decomposing or running anything:

- Reject unsupported agent types up front. `/omc-teams` only supports **`claude`**, **`codex`**, **`gemini`**, **`antigravity`**, **`grok`**, and **`cursor`**.
- Treat Cursor workers as executor-style only. Accept `N:cursor` and `N:cursor:executor`; reject or reframe reviewer, critic, security-reviewer, verdict, or final-approval work onto native Claude/OMC reviewer agents.
- If the user asks for an unsupported type such as `expert`, explain that `/omc-teams` launches external CLI workers only.
- For native Claude Code team agents/roles, direct them to **`/oh-my-claudecode:team`** instead.

### Phase 2: Decompose task

Break work into N independent subtasks (file- or concern-scoped) to avoid write conflicts.

### Phase 2.5: Resolve workspace root for multi-repo plans

`omc team` launches all workers with one shared working directory. For single-repo
tasks, the current repo is usually correct. For multi-repo tasks, especially when a
plan lives in one repo but the implementation touches sibling repos, resolve the
working directory before launch:

- If the task references a plan artifact under one repo (for example
  `tool/.omc/plans/task-1200-gwd-gifs.md`) and target paths in sibling repos
  (for example `api/` and `admin/`), choose the shared workspace root that contains
  all participating repos (for example the parent `inter/` directory).
- Use an **absolute plan path** in the task text so the workers can still find the
  plan after `--cwd` changes the launch directory.
- Include the explicit repo paths or repo names in the task text and subtasks.
- Do not anchor the launch cwd to only the repo containing `.omc/plans/...` when
  target repos are siblings; that strands `codex`, `claude`, `gemini`, `antigravity`, `grok`, and `cursor` workers in
  the plan repo instead of the implementation workspace.
- If no safe shared workspace root can be identified, do not launch `/omc-teams`.
  Report the single-cwd constraint and ask for, or derive from evidence, the intended
  workspace root.

### Phase 3: Start CLI team runtime

Activate mode state (recommended):

```text
state_write(mode="team", current_phase="team-exec", active=true)
```

Start workers via CLI:

```bash
omc team <N>:<claude|codex|gemini|antigravity|grok|cursor> "<task>"
```

For the multi-repo case resolved in Phase 2.5, launch from the shared workspace root
with the existing `--cwd` contract and keep the plan reference absolute:

```bash
omc team <N>:<claude|codex|gemini|antigravity|grok|cursor> "<task with absolute plan path and explicit repo paths>" --cwd <workspace-root>
```

Team name defaults to a slug from the task text (example: `review-auth-flow`).

After launch, verify the command actually executed instead of assuming Enter fired. Check pane output and confirm the command or worker bootstrap text appears in pane history:

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} #{pane_current_command}'
tmux capture-pane -pt <pane-id> -S -20
```

Do not claim the team started successfully unless pane output shows the command was submitted.

### Phase 4: Monitor + lifecycle API

```bash
omc team status <team-name>
omc team api list-tasks --input '{"team_name":"<team-name>"}' --json
```

Use `omc team api ...` for task claiming, task transitions, mailbox delivery, and worker state updates.

### Phase 5: Shutdown (only when needed)

```bash
omc team shutdown <team-name>
omc team shutdown <team-name> --force
```

Use shutdown for intentional cancellation or stale-state cleanup. Prefer non-force shutdown first.

### Phase 6: Report + state close

Report task results with completion/failure summary and any remaining risks.

```text
state_write(mode="team", current_phase="complete", active=false)
```

## Deprecated Runtime Note

Legacy MCP runtime tools are deprecated for execution:

- `omc_run_team_start`
- `omc_run_team_status`
- `omc_run_team_wait`
- `omc_run_team_cleanup`

If encountered, switch to `omc team ...` CLI commands.

## Error Reference

| Error                        | Cause                               | Fix                                                                                 |
| ---------------------------- | ----------------------------------- | ----------------------------------------------------------------------------------- |
| `not inside tmux`            | Requested in-place pane topology from a non-tmux surface | Start tmux and rerun, or let `omc team` use its detached-session fallback           |
| `cmux surface detected`      | Running inside cmux without `$TMUX` and no rmux/tmux resolvable | Use the normal `omc team ...` flow; OMC prefers rmux/tmux and only creates native cmux worker splits when neither is available |
| `Unsupported agent type`     | Requested agent is not claude/codex/gemini/antigravity/grok/cursor | Use `claude`, `codex`, `gemini`, `antigravity`, `grok`, or `cursor`; for native Claude Code agents use `/oh-my-claudecode:team` |
| `codex: command not found`   | Codex CLI not installed             | `npm install -g @openai/codex`                                                      |
| `gemini: command not found`  | Gemini CLI not installed            | `npm install -g @google/gemini-cli` (enterprise/API-key tier)                       |
| `agy: command not found`     | Antigravity CLI not installed       | Install per the [official instructions](https://antigravity.google)                |
| `Team <name> is not running` | stale or missing runtime state      | `omc team status <team-name>` then `omc team shutdown <team-name> --force` if stale |
| `status: failed`             | Workers exited with incomplete work | inspect runtime output, narrow scope, rerun                                         |

## Relationship to `/team`

| Aspect       | `/team`                                                       | `/omc-teams`                                         |
| ------------ | ------------------------------------------------------------- | ---------------------------------------------------- |
| Worker type  | Claude Code implicit agent-team teammates                     | claude / codex / gemini / antigravity CLI processes in tmux        |
| Invocation   | Agent/Task spawn with distinct `name` values; no TeamCreate/TeamDelete in Claude Code 2.1.178+ | `omc team [N:agent]` + `status` + `shutdown` + `api` |
| Coordination | Native implicit-team messaging and staged pipeline            | tmux worker runtime + CLI API state files            |
| Use when     | You want Claude-native in-session agent orchestration         | You want external CLI worker execution               |
