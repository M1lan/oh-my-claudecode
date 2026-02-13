<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# commands/

## Purpose
The commands/ directory contains slash command definitions for oh-my-claudecode. Each markdown file defines a user-invocable slash command (e.g., `/oh-my-claudecode:plan`) that Claude Code recognizes and routes to the appropriate skill or orchestration behavior. This directory mirrors the structure of skills/ but represents the user-facing command surface rather than internal skill implementations.

## Key Files
| File | Description |
|------|-------------|
| `analyze.md` | Triggers deep codebase or data analysis via the analyst agent |
| `autopilot.md` | Activates autopilot mode for continuous autonomous task execution |
| `build-fix.md` | Invokes the build-fixer agent to diagnose and repair CI/build failures |
| `cancel.md` | Cancels active execution modes (ralph, ultrawork, autopilot, pipeline) |
| `code-review.md` | Runs a full code review pass using the code-reviewer agent |
| `configure-discord.md` | Sets up Discord webhook integration for notifications |
| `configure-telegram.md` | Sets up Telegram bot integration for notifications |
| `deepinit.md` | Deep initialization of a project with full context gathering |
| `deepsearch.md` | Performs exhaustive multi-source research on a topic |
| `doctor.md` | Runs diagnostic checks on the OMC installation and environment |
| `ecomode.md` | Activates eco mode to reduce token usage on lightweight tasks |
| `help.md` | Displays available commands and usage instructions |
| `hud.md` | Shows the heads-up display of current agent state and active modes |
| `learn-about-omc.md` | Provides an interactive tour of OMC capabilities |
| `learner.md` | Activates learning mode to capture and persist session insights |
| `mcp-setup.md` | Guides MCP server configuration and tool registration |
| `note.md` | Saves a persistent note to the notepad for cross-session recall |
| `omc-setup.md` | Runs the full OMC installation and configuration wizard |
| `pipeline.md` | Defines and executes a sequential multi-agent pipeline |
| `plan.md` | Generates a structured implementation plan for a given request |
| `psm.md` | Product-strategy mode; frames work in product and user terms |
| `ralph-init.md` | Initializes ralph (continuous work) mode with task setup |
| `ralph.md` | Activates ralph mode for persistent autonomous execution |
| `ralplan.md` | Ralph mode with an upfront planning phase before execution |
| `release.md` | Orchestrates a release: changelog, version bump, tag, and notes |
| `research.md` | Kicks off structured external research via the researcher agent |
| `review.md` | General review command routing to the appropriate review agent |
| `security-review.md` | Runs a security-focused review via the security-reviewer agent |
| `swarm.md` | Launches a parallel swarm of agents for large-scale tasks |
| `tdd.md` | Activates test-driven development mode with red-green-refactor flow |
| `team.md` | Creates and coordinates a named team of specialized agents |
| `trace.md` | Displays the agent flow trace timeline for the current session |
| `ultrapilot.md` | High-autonomy pilot mode for extended multi-step execution |
| `ultraqa.md` | Ultra quality-assurance mode with exhaustive verification passes |
| `ultrawork.md` | Maximum-effort autonomous work mode with continuous iteration |

## For AI Agents

### Working In This Directory
Slash command files define the entry point for user-facing features. When adding a new command, create a `.md` file whose name matches the slash command suffix (e.g., `my-cmd.md` for `/oh-my-claudecode:my-cmd`). The file should describe what the command does, how it is triggered, and which skill or agent it delegates to. Do not embed complex logic here; keep command files as thin routing stubs pointing to skills/.

### Common Patterns
- Command files reference the corresponding skill in skills/ for implementation.
- Mode-activation commands (ralph, autopilot, ultrawork) write state via the state tools.
- Commands that spawn agents specify the agent type and model recommendation.
- The `cancel.md` command is always available regardless of active mode.

## Dependencies

### Internal
- Each command typically invokes a corresponding file in `skills/`.
- Mode commands interact with state files managed by `src/state/`.
- Agent-spawning commands reference templates in `agents/`.

### External
None - pure markdown command definition files.

<!-- MANUAL: -->
