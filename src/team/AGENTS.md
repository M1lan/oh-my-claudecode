<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# team

## Purpose
Claude Code native team coordination system. Manages multi-agent teams where each "worker" is a Claude Code subprocess running inside a tmux pane or git worktree. Handles the full worker lifecycle: registration, heartbeats, task distribution via JSON files, message routing through inbox/outbox directories, activity and audit logging, git worktree isolation, permission enforcement, usage tracking, and graceful worker restart/recovery. Also includes an MCP bridge that exposes team coordination as MCP tools.

## Key Files
| File | Description |
|------|-------------|
| `types.ts` | All team-specific interfaces: `BridgeConfig`, `TaskFile`, `InboxMessage`, `OutboxMessage`, `HeartbeatData`, `WorkerBackend`, `WorkerCapability`, etc. |
| `index.ts` | Barrel export for all public APIs |
| `unified-team.ts` | Merges Claude native team config with MCP shadow registry into a single `UnifiedTeamMember[]` view |
| `task-file-ops.ts` | CRUD operations on task JSON files in `~/.claude/tasks/{team}/` |
| `task-router.ts` | Assigns pending tasks to available workers based on status and ownership |
| `message-router.ts` | Routes messages between team members via inbox/outbox file system protocol |
| `inbox-outbox.ts` | Low-level inbox/outbox file I/O: read, write, rotate, cursor management |
| `outbox-reader.ts` | Polls worker outboxes and delivers messages to recipients |
| `heartbeat.ts` | Writes and reads worker heartbeat files; `isWorkerAlive()` liveness check |
| `team-registration.ts` | Registers/deregisters workers in the MCP shadow registry |
| `team-status.ts` | Aggregates and reports overall team health and per-worker status |
| `tmux-session.ts` | Creates and manages tmux sessions/panes for worker subprocesses |
| `git-worktree.ts` | Provisions and tears down git worktrees for isolated worker environments |
| `merge-coordinator.ts` | Coordinates merging of worktree branches back to the main branch |
| `mcp-team-bridge.ts` | Exposes team coordination as MCP tool handlers (TaskCreate, TaskUpdate, etc.) |
| `bridge-entry.ts` | Entry point for the bridge daemon process; reads `BridgeConfig` and starts polling |
| `worker-health.ts` | Monitors worker health; detects stalled or crashed workers |
| `worker-restart.ts` | Restarts crashed or stalled workers with backoff |
| `activity-log.ts` | Appends timestamped activity entries to `.omc/logs/activity.jsonl` |
| `audit-log.ts` | Writes immutable audit records for permission-sensitive operations |
| `permissions.ts` | Path and command permission enforcement for `BridgeWorkerPermissions` |
| `capabilities.ts` | Defines and queries `WorkerCapability` sets (what tools a worker can use) |
| `usage-tracker.ts` | Tracks per-worker token/cost usage across task executions |
| `summary-report.ts` | Generates human-readable summary reports for completed team runs |
| `fs-utils.ts` | Team-scoped filesystem helpers (directory creation, safe reads) |

## For AI Agents

### Working In This Directory
- Task state lives in JSON files at `~/.claude/tasks/{teamName}/{id}.json` (shape: `TaskFile`). Never mutate task files directly — use `task-file-ops.ts` functions.
- Worker liveness is determined by heartbeat recency via `isWorkerAlive()` in `heartbeat.ts`. The threshold is configurable in `BridgeConfig`.
- Message delivery is eventually consistent: workers poll their inbox directory. Do not assume synchronous delivery.
- `BridgeConfig.permissionEnforcement` has three modes: `'off'` (default), `'audit'` (log violations), `'enforce'` (block violations). Enforcement logic lives in `permissions.ts`.
- Git worktree operations in `git-worktree.ts` use `child_process.execSync` — they are synchronous and may throw on git errors.
- `unified-team.ts` is the preferred way to enumerate all team members regardless of backend type.

### Common Patterns
- Task status transitions: `pending` -> `in_progress` -> `completed` (or back to `pending` on retry).
- Worker self-registration on startup via `team-registration.ts`; deregistration on clean shutdown.
- Heartbeat write interval is `pollIntervalMs` (default 3000ms); liveness window is typically `3 * pollIntervalMs`.
- Outbox rotation is triggered when line count exceeds `BridgeConfig.outboxMaxLines` (default 500).
- All file I/O in this module uses atomic writes from `src/lib/atomic-write.ts`.

## Dependencies

### Internal
- `src/lib/atomic-write.ts` — safe JSON file writes
- `src/lib/worktree-paths.ts` — `.omc/` path resolution
- `src/utils/paths.ts` — `getClaudeConfigDir()` for `~/.claude/` paths
- `src/platform/process-utils.ts` — cross-platform process kill

### External
- `node:fs`, `node:path`, `node:child_process` — filesystem and process management
- `tmux` (system binary) — worker pane management

<!-- MANUAL: -->
