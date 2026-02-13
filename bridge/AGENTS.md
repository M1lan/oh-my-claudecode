<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# bridge/

## Purpose
The bridge/ directory contains pre-bundled CommonJS (CJS) files and supporting scripts that form the MCP (Model Context Protocol) server layer for the oh-my-claudecode plugin. These are pre-built distribution artifacts - not source files - that are installed into `~/.claude-plugin/` when the plugin is set up. The bridge exposes OMC's tools (state management, notepad, tracing, Codex, Gemini, and team coordination) as MCP tools that Claude Code can invoke during a session.

## Key Files
| File | Description |
|------|-------------|
| `mcp-server.cjs` | Main MCP server bundle; exposes core OMC tools (state, notepad, trace, etc.) to Claude Code |
| `codex-server.cjs` | MCP server bundle for OpenAI Codex CLI integration (`ask_codex` tool) |
| `gemini-server.cjs` | MCP server bundle for Google Gemini CLI integration (`ask_gemini` tool) |
| `team-bridge.cjs` | MCP server bundle for multi-agent team coordination and messaging |
| `gyoshu_bridge.py` | Python bridge script for Gyoshu (Japanese task/agent coordination) integration |
| `run-mcp-server.sh` | Shell launcher that starts the appropriate MCP server process on plugin startup |

## For AI Agents

### Working In This Directory
These files are pre-built bundles. Do not hand-edit CJS files directly - they are generated from source in `src/` via the build process. If a behavior change is needed, edit the TypeScript source in `src/` and rebuild. The Python bridge (`gyoshu_bridge.py`) is an exception and may be edited directly if the Gyoshu integration requires changes. When adding a new MCP server (e.g., for a new external tool), create the source in `src/`, add a build target, and output the bundle here.

### Common Patterns
- Each `*-server.cjs` file is a self-contained Node.js MCP server started by `run-mcp-server.sh`.
- Servers are registered in the plugin's MCP configuration so Claude Code can discover their tools.
- `team-bridge.cjs` manages inter-agent messaging, task lists, and shutdown coordination.
- `run-mcp-server.sh` reads environment variables to determine which servers to start and on which ports.
- Bundles include all dependencies inlined (no `node_modules` required at runtime).

## Dependencies

### Internal
- Built from TypeScript source in `src/mcp/` and `src/bridge/`.
- Installed to `~/.claude-plugin/` by the setup scripts in `src/install/`.
- `run-mcp-server.sh` is referenced by the plugin's MCP server configuration.

### External
- Node.js runtime (for `.cjs` files).
- Python 3 runtime (for `gyoshu_bridge.py`).
- OpenAI Codex CLI (`@openai/codex`) must be installed separately for `codex-server.cjs` to function.
- Google Gemini CLI (`@google/gemini-cli`) must be installed separately for `gemini-server.cjs` to function.

<!-- MANUAL: -->
