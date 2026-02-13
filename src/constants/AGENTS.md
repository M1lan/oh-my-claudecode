<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# constants

## Purpose
Application-wide string constants for oh-my-claudecode. Provides canonical identifiers for execution modes (`autopilot`, `ralph`, `ultrawork`, etc.), tool categories (`lsp`, `ast`, `codex`, etc.), and hook event names (`PreToolUse`, `PostToolUse`, etc.). Eliminates scattered string literals and provides TypeScript `const` union types for compile-time safety.

## Key Files
| File | Description |
|------|-------------|
| `names.ts` | `MODES`, `TOOL_CATEGORIES`, `HOOK_EVENTS` objects with `as const`, plus derived union types `ModeName`, `ToolCategory`, `HookEvent` |
| `index.ts` | Barrel re-export of everything from `names.ts` |

## For AI Agents

### Working In This Directory
- This module has zero runtime logic — only `const` object declarations and `typeof` derived types.
- When adding a new mode, tool category, or hook event: add the entry to the appropriate object in `names.ts` only. The union type is derived automatically.
- Import pattern: `import { MODES, type ModeName } from '../constants/index.js'`
- Never import from `names.ts` directly — always use `index.ts` to allow future splitting.
- String values must remain stable across releases — they are written to state files and config on disk.

### Common Patterns
- Mode guard: `if (mode === MODES.AUTOPILOT) { ... }`
- Exhaustive switch: use `ModeName` as the switch type for compile-time completeness checking.

## Dependencies

### Internal
None — foundational constants module with no imports.

### External
None.

<!-- MANUAL: -->
