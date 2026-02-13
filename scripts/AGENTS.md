<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# scripts

## Purpose

The scripts directory contains build automation, hook implementations, and supporting utilities for oh-my-claudecode (OMC). These scripts handle critical runtime operations including mode persistence, tool verification, keyword detection, MCP server bundling, and session lifecycle management. Most production scripts exist as both Node.js ESM (.mjs) and shell (.sh) pairs to ensure cross-platform compatibility and fallback support.

## Key Files

| File | Description |
|------|-------------|
| **Build/Bundle Scripts** | |
| `build-bridge-entry.mjs/.sh` | Bundles Team Bridge entry point to standalone CJS for plugin distribution |
| `build-codex-server.mjs/.sh` | Bundles Codex MCP server for distribution |
| `build-gemini-server.mjs/.sh` | Bundles Gemini MCP server for distribution |
| `build-mcp-server.mjs/.sh` | Bundles main OMC MCP server for distribution |
| `build-skill-bridge.mjs/.sh` | Builds skill bridge from skills/ directory |
| `compose-docs.mjs/.sh` | Composes documentation from partials |
| **Hook Scripts (Runtime)** | |
| `keyword-detector.mjs/.sh` | Detects magic keywords in user prompts ([MAGIC KEYWORD:...], /ralph, /autopilot, /team, etc.) and invokes corresponding skills |
| `permission-handler.mjs/.sh` | Handles tool permission requests |
| `persistent-mode.mjs/.sh` | Manages execution mode persistence across sessions (stop hook) |
| `pre-tool-enforcer.mjs/.sh` | Injects contextual reminders before tool execution (PreToolUse hook) |
| `post-tool-verifier.mjs/.sh` | Monitors tool execution and provides guidance (PostToolUse hook) |
| `session-start.mjs/.sh` | Restores persistent mode states when session starts (session start hook) |
| `session-end.mjs/.sh` | Handles cleanup when session ends (session end hook) |
| **Project Memory Scripts** | |
| `project-memory-session.mjs/.sh` | Session-lifecycle project memory management |
| `project-memory-posttool.mjs/.sh` | Post-tool project memory updates |
| `project-memory-precompact.mjs/.sh` | Pre-compaction project memory processing |
| `pre-compact.mjs/.sh` | Handles pre-compaction logic |
| **Setup & Maintenance** | |
| `plugin-setup.mjs/.sh` | Post-install setup for HUD statusline and configuration |
| `setup-init.mjs/.sh` | Initializes OMC configuration on first setup |
| `setup-maintenance.mjs/.sh` | Maintenance operations during setup |
| **Utilities** | |
| `skill-injector.mjs/.sh` | Injects available skills into context |
| `subagent-tracker.mjs/.sh` | Tracks subagent invocation and state |
| `persistent-mode.cjs` | CommonJS build of persistent-mode for broader compatibility |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `lib/` | Shared library modules (platform detection, stdin utilities) |
| `.claude/` | Claude-specific configuration for scripts context |
| `.omc/` | OMC state and configuration for scripts execution context |

## For AI Agents

### Working In This Directory

**Pattern**: Most production scripts follow a `.mjs` (ESM module) + `.sh` (shell wrapper) pattern:
- `.mjs` files contain the core implementation in Node.js ESM
- `.sh` files are shell wrappers that invoke the corresponding `.mjs` file with proper environment setup
- Both variants must be kept in sync when modifying logic

**When to Update**:
1. Modify the `.mjs` file with the core logic
2. Update the `.sh` wrapper if shell-specific handling changes
3. Both files must pass linting and be executable

**Hook Scripts**: These are invoked by Claude at specific lifecycle points:
- PreToolUse: Executed before any tool is called (pre-tool-enforcer)
- PostToolUse: Executed after any tool completes (post-tool-verifier, persistent-mode)
- SessionStart: Executed when a session begins (session-start)
- SessionEnd: Executed when a session ends (session-end)
- StopHook: Executed when stopping execution (persistent-mode)

Hook scripts receive structured JSON input via stdin and must exit with appropriate status codes.

**Build Scripts**: These use esbuild to bundle TypeScript sources into standalone CommonJS bundles:
- All build scripts output to `bridge/` directory (for plugin distribution)
- Externalize Node.js built-ins and native modules (fs, crypto, @ast-grep/napi, better-sqlite3)
- Include NODE_PATH preamble to resolve global npm modules from plugin cache

### Common Patterns

1. **stdin Reading**: Import `readStdin` from `lib/stdin.mjs` for timeout-protected stdin reading (prevents hangs on Linux/Windows)
2. **JSON Parsing**: Hook scripts parse stdin as JSON to extract context, mode state, and user input
3. **File Operations**: Use Node.js fs module with proper path resolution via `homedir()` and `process.env.CLAUDE_CONFIG_DIR`
4. **Error Handling**: Graceful degradation when optional modules unavailable (e.g., notepad functions may fail if dist not built)
5. **Output**: Most hooks output JSON or structured text; some write to filesystem for state persistence

## Dependencies

### Internal

- `src/hooks/` - Hook type definitions and shared logic
- `src/mcp/` - MCP server implementations (for build-mcp-server)
- `src/team/` - Team bridge entry point (for build-bridge-entry)
- `src/skills/` - Skill implementations (for build-skill-bridge)
- `dist/hooks/` - Compiled hook utilities and notepad functions

### External

- **esbuild** - Used by all build-*.mjs scripts for bundling
- **@ast-grep/napi** - Native AST grep bindings (externalized in bundles)
- **better-sqlite3** - Native SQLite bindings (externalized in bundles)
- **Node.js 18+** - Runtime requirement for all .mjs scripts
- **Bash** - Runtime requirement for all .sh wrappers

<!-- MANUAL: -->
