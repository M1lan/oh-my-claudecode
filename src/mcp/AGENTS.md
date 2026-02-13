<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# mcp

## Purpose
MCP (Model Context Protocol) server integration layer for oh-my-claudecode. Defines and registers all in-process MCP servers exposed to Claude Code: the Codex (OpenAI) integration providing `ask_codex`, the Gemini (Google) integration providing `ask_gemini`, and the OMC tools server providing LSP, AST, state management, team coordination, notepad, and tracing tools. Also handles prompt persistence for audit trails, background job lifecycle management, and CLI auto-detection.

## Key Files
| File | Description |
|------|-------------|
| `index.ts` | Barrel export for all MCP server factories, tool name registries, and helper utilities |
| `codex-core.ts` | Business logic for Codex CLI integration: spawning, timeout handling, model validation, fallback chain, background execution |
| `codex-server.ts` | In-process SDK MCP server wrapping `codex-core.ts`; exports `codexMcpServer` and `codexToolNames` |
| `codex-standalone-server.ts` | Stdio-based external process MCP server for Codex; mirrors `codex-server.ts` without SDK dependency |
| `gemini-core.ts` | Business logic for Gemini CLI integration: spawning, timeout handling, model validation, fallback chain, background execution |
| `gemini-server.ts` | In-process SDK MCP server wrapping `gemini-core.ts`; exports `geminiMcpServer` and `geminiToolNames` |
| `gemini-standalone-server.ts` | Stdio-based external process MCP server for Gemini |
| `omc-tools-server.ts` | In-process MCP server for all OMC-native tools (LSP, AST, state, team, notepad, trace, python REPL) |
| `job-management.ts` | MCP tool handlers for background job lifecycle: `wait_for_job`, `check_job_status`, `kill_job`, `list_jobs` |
| `job-state-db.ts` | SQLite-backed job state database for persistent background job tracking |
| `prompt-persistence.ts` | Audit trail for prompts/responses; job status file I/O; background job metadata helpers |
| `prompt-injection.ts` | System prompt resolution, agent role validation, untrusted content wrapping, `VALID_AGENT_ROLES` |
| `cli-detection.ts` | Auto-detects installed Codex and Gemini CLI binaries on PATH |
| `mcp-config.ts` | Reads MCP configuration flags (e.g. `isExternalPromptAllowed`) |
| `servers.ts` | Factories for optional external MCP servers: Exa, Context7, Playwright, Filesystem, Memory |
| `shared-exec.ts` | Shared subprocess execution helpers: stdout collector, safe output file writer |
| `standalone-server.ts` | Base/shared logic for standalone stdio MCP server processes |

## For AI Agents

### Working In This Directory
- Each provider (Codex, Gemini) has a `*-core.ts` file containing all business logic and a `*-server.ts` file that wires it into the MCP SDK. Always edit the `-core.ts` file for behaviour changes; the server files are thin wrappers.
- The `omc-tools-server.ts` file is the single registration point for all non-provider OMC tools. Add new OMC tools here.
- Background job state flows through `prompt-persistence.ts` (file-based) and `job-state-db.ts` (SQLite). Changes to job status shape must be reflected in both.
- Model names are validated with `MODEL_NAME_REGEX` in both core files. Invalid names throw before spawning.
- Timeouts are clamped between 5s and 3600s and configurable via `OMC_CODEX_TIMEOUT` / `OMC_GEMINI_TIMEOUT` env vars.

### Common Patterns
- All MCP tool handlers return `{ content: [{ type: 'text', text: string }], isError?: boolean }`.
- Spawned process PIDs are tracked in module-scoped `Set<number>` (`spawnedPids`) to support `kill_job` safety checks.
- System prompts are resolved via `resolveSystemPrompt()` and injected via `buildPromptWithSystemContext()` before passing to CLIs.
- Untrusted file content is wrapped with `wrapUntrustedFileContent()` to prevent prompt injection.
- Provider defaults are overridable via `OMC_CODEX_DEFAULT_MODEL` / `OMC_GEMINI_DEFAULT_MODEL` env vars.
- Fallback model chains are defined in `src/features/model-routing/external-model-policy.ts` and consumed here.

## Dependencies

### Internal
- `src/lib/worktree-paths.ts` — worktree root resolution for `.omc/` path scoping
- `src/features/model-routing/external-model-policy.ts` — model fallback chains
- `src/config/loader.ts` — user config loading

### External
- `child_process` (Node built-in) — spawning Codex/Gemini CLI processes
- `@anthropic-ai/claude-agent-sdk` — MCP SDK server protocol (in-process servers only)
- `better-sqlite3` — SQLite job state database (job-state-db.ts)

<!-- MANUAL: -->
