<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# templates/

## Purpose
The templates/ directory contains the source templates for hook implementations and injected coding rules. During plugin installation, these templates are copied to `~/.claude-plugin/hooks/` (JS modules) and made available as injectable rule sets (markdown). The hooks/ subdirectory provides the logic that runs on Claude Code lifecycle events, while the rules/ subdirectory provides opinionated coding standards that can be injected into Claude sessions on demand.

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `hooks/` | ES module (`.mjs`) templates for each Claude Code hook event handler |
| `rules/` | Markdown rule files defining coding standards injected into sessions |
| `lib/` | Shared utility modules imported by hook templates |

## Key Files

### hooks/
| File | Description |
|------|-------------|
| `keyword-detector.mjs` | Scans incoming user prompts for OMC magic keywords and mode triggers |
| `persistent-mode.mjs` | Manages persistent execution mode state (ralph, ultrawork, autopilot) |
| `post-tool-use.mjs` | Runs after every successful tool call; logs to trace timeline |
| `pre-tool-use.mjs` | Runs before every tool call; enforces tool-use policies and logging |
| `session-start.mjs` | Initializes OMC context at the start of each Claude Code session |
| `stop-continuation.mjs` | Determines whether a persistent mode should continue or halt on Stop event |

### rules/
| File | Description |
|------|-------------|
| `coding-style.md` | Code style conventions: naming, formatting, and structural guidelines |
| `git-workflow.md` | Git branching, commit message format, and PR workflow rules |
| `performance.md` | Performance-conscious coding patterns and anti-patterns to avoid |
| `security.md` | Secure coding rules: input validation, secrets handling, and threat awareness |
| `testing.md` | Testing philosophy, coverage expectations, and test structure conventions |

## For AI Agents

### Working In This Directory
Hook templates in `hooks/` are the source of truth for hook behavior. Edit these `.mjs` files to change how OMC responds to Claude Code events, then re-run the install step to propagate changes to `~/.claude-plugin/`. Rule files in `rules/` are standalone markdown documents - edit them directly to update the injected standards. When adding a new hook event, create a new `.mjs` file in `hooks/`, register it in `hooks/hooks.json`, and update the install script to copy it.

### Common Patterns
- Hook `.mjs` files export a default async function that receives the Claude Code event payload.
- Shared utilities (e.g., state reading, logging) are imported from `lib/`.
- Rule files use plain markdown with clear section headers so they can be injected as-is into Claude context.
- `keyword-detector.mjs` and `persistent-mode.mjs` work together: the detector identifies triggers, and the mode manager updates state.
- Hook templates are copied verbatim during install; they must be self-contained or rely only on `lib/`.

## Dependencies

### Internal
- `hooks/` templates are installed by `src/install/` scripts to `~/.claude-plugin/hooks/`.
- `hooks/` templates import shared utilities from `templates/lib/`.
- `hooks/hooks.json` (in the root `hooks/` directory) references the installed script paths.
- `rules/` files are referenced by skill and command definitions that inject coding standards.

### External
- Node.js ESM runtime (for `.mjs` hook files).
- Claude Code hook execution environment (provides event payload to each hook).

<!-- MANUAL: -->
