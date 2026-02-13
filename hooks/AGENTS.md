<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# hooks/

## Purpose
The hooks/ directory contains the Claude Code plugin hooks configuration. The central file, hooks.json, registers shell scripts that intercept Claude Code lifecycle events and inject orchestration behavior - such as keyword detection, skill activation, session initialization, tool usage auditing, and stop-continuation logic. These hooks are the runtime glue between Claude Code events and the OMC orchestration layer.

## Key Files
| File | Description |
|------|-------------|
| `hooks.json` | Master hooks configuration; maps Claude Code lifecycle events to shell scripts |

## Hook Event Mappings (defined in hooks.json)
| Event | Scripts |
|-------|---------|
| `UserPromptSubmit` | `keyword-detector.sh`, `skill-injector.sh` |
| `SessionStart` | `session-start.sh` |
| `Stop` | `stop-continuation.sh` |
| `PreToolUse` | `pre-tool-use.sh` |
| `PostToolUse` | `post-tool-use.sh`, `post-tool-use-failure.sh` |

The shell scripts themselves live in the installation target (`~/.claude-plugin/hooks/`) and are sourced from templates in `templates/hooks/`. The hooks.json file in this directory is the source-of-truth configuration that gets installed into the plugin location.

## For AI Agents

### Working In This Directory
This directory has a single configuration file. When modifying hook behavior, edit hooks.json to add, remove, or reorder event handlers. The shell scripts referenced in hooks.json must exist in the installation target at runtime. Do not inline logic into hooks.json itself - keep it as a routing manifest pointing to scripts. When adding a new hook event, add the event key and script path(s) to hooks.json, then create the corresponding script template in `templates/hooks/`.

### Common Patterns
- Hook scripts are bash/shell executables and must be kept lightweight (they run on every event).
- `keyword-detector.sh` scans user prompts for magic keywords and mode activations.
- `skill-injector.sh` injects skill context into the Claude session based on detected keywords.
- `stop-continuation.sh` checks whether an active mode (ralph, ultrawork) should continue running.
- `pre-tool-use.sh` and `post-tool-use.sh` log tool usage for the trace timeline.
- `post-tool-use-failure.sh` handles tool failure events and notifies active monitors.

## Dependencies

### Internal
- Script templates sourced from `templates/hooks/` during installation.
- Installation scripts in `src/install/` copy hooks.json to `~/.claude-plugin/`.
- State files read/written by hook scripts live in `~/.claude/state/`.

### External
- Claude Code hook system (requires Claude Code CLI with hooks support).
- Shell runtime (bash/zsh) available in the execution environment.

<!-- MANUAL: -->
