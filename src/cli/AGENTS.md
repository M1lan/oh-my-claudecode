<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# cli

## Purpose

CLI entry points for the OMC npm package. `index.ts` is the main `omc` executable built on `commander`; it registers top-level commands including `install`, `update`, `config`, `stats`, `cost`, `sessions`, `agents`, `export`, `cleanup`, `backfill`, `wait`, `teleport`, and `doctor`. `analytics.ts` provides the `omc analytics` subcommand group. The `commands/` subdirectory contains one module per CLI subcommand, and `utils/` holds shared helpers (tokscale launcher, formatting, and HUD context builders).

## Key Files

| File | Description |
|------|-------------|
| `index.ts` | Main `omc` CLI binary entry point; registers all top-level commands via `commander` and handles update checks |
| `analytics.ts` | `omc analytics` subcommand group; delegates to stats, cost, and sessions commands |
| `README.md` | User-facing documentation for the CLI |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `commands/` | One file per CLI subcommand: `stats.ts`, `cost.ts`, `sessions.ts`, `agents.ts`, `export.ts`, `cleanup.ts`, `backfill.ts`, `wait.ts`, `teleport.ts`, `doctor-conflicts.ts` |
| `utils/` | Shared CLI utilities: `tokscale-launcher.ts` (TUI wrapper), `formatting.ts` (table/color helpers), and context builders for agents, session, model, git, skills, todos, rate limits, etc. |

## For AI Agents

### Working In This Directory

- All subcommands live in `commands/` as named exports (`statsCommand`, `costCommand`, etc.) and are imported and registered in `index.ts`.
- When adding a new subcommand: create `commands/mynew.ts`, export `mynewCommand`, import and register it in `index.ts` with `program.addCommand(mynewCommand)`.
- Utilities shared across two or more commands belong in `utils/`. Single-command helpers stay in the command file.
- The CLI reads analytics data through `src/analytics/` — never access `token-tracking.jsonl` directly from a command file; use the query-engine or tracker APIs.
- `tokscale-launcher.ts` in `utils/` starts the tokscale TUI; check `isTokscaleCLIAvailable()` before calling `launchTokscaleTUI()`.

### Common Patterns

```typescript
// Adding a new command
// commands/mynew.ts
import { Command } from 'commander';
export const mynewCommand = new Command('mynew')
  .description('Does the new thing')
  .action(async () => { /* ... */ });

// Registering in index.ts
import { mynewCommand } from './commands/mynew.js';
program.addCommand(mynewCommand);

// Using formatting helpers
import { formatTable } from './utils/formatting.js';
console.log(formatTable(rows, headers));
```

## Dependencies

### Internal
- `../analytics/` — token tracking, cost, query engine, export
- `../installer/index.js` — `install`, `isInstalled`, `getInstallInfo`
- `../config/loader.js` — `loadConfig`, `getConfigPaths`
- `../features/auto-update.js` — `checkForUpdates`, `performUpdate`
- `../index.js` — `createSisyphusSession`
- `../lib/version.js` — `getRuntimePackageVersion`

### External
- `commander` — CLI framework
- `chalk` — terminal colours
- Node built-ins: `fs`, `fs/promises`, `path`, `os`, `child_process`

<!-- MANUAL: -->
