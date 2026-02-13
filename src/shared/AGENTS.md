<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# shared

## Purpose
Shared TypeScript type definitions used across all modules in oh-my-claudecode. Defines the core domain interfaces including `AgentConfig`, `PluginConfig`, `ModelType`, and other types that multiple modules need to agree on. Acts as the single source of truth for cross-cutting data shapes — no business logic lives here.

## Key Files
| File | Description |
|------|-------------|
| `types.ts` | All shared interfaces and type aliases: `ModelType`, `AgentConfig`, `PluginConfig`, `HookContext`, `ToolDefinition`, and more |
| `index.ts` | Barrel re-export of everything from `types.ts` |

## For AI Agents

### Working In This Directory
- This is a pure types module — no runtime logic, no side effects. Every export must be a type or interface.
- `ModelType` (`'sonnet' | 'opus' | 'haiku' | 'inherit'`) is the canonical model identifier used throughout the codebase. Do not add new model tiers here without updating all consumers.
- `AgentConfig` is the shape expected by the agent catalog loader. Any new agent properties must be added here first, then consumed in the agent loader.
- `PluginConfig` mirrors the shape of the user's `~/.claude/settings.json` plugin configuration block. Keep it in sync with the config loader schema.
- Avoid importing from other `src/` modules here — circular dependencies will break the entire type graph.

### Common Patterns
- Import shared types as: `import type { AgentConfig } from '../shared/index.js'`
- All exports use named exports, never default exports.
- Optional fields use `?` — do not add required fields without updating all construction sites.

## Dependencies

### Internal
None — this module has no internal imports by design.

### External
None — pure TypeScript type declarations only.

<!-- MANUAL: -->
