<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# config

## Purpose

Configuration loading and validation for the OMC plugin. `loader.ts` defines the `DEFAULT_CONFIG` object with all agent model assignments, feature flags, MCP server toggles, permission limits, magic keyword mappings, intelligent model routing tiers, external model provider settings (Codex, Gemini), and delegation routing. It merges three sources in priority order: hardcoded defaults, user JSONC config, project JSONC config, and environment variables (highest precedence). `index.ts` re-exports the public surface.

## Key Files

| File | Description |
|------|-------------|
| `loader.ts` | Core implementation: `DEFAULT_CONFIG`, `loadConfig()`, `loadJsoncFile()`, `loadEnvConfig()`, `deepMerge()`, `getConfigPaths()`, `findContextFiles()`, `loadContextFromFiles()`, `generateConfigSchema()` |
| `index.ts` | Re-exports all public symbols from `loader.ts` |

## For AI Agents

### Working In This Directory

- Config file locations (from `getConfigPaths()`):
  - User: `~/.config/claude-sisyphus/config.jsonc` (or `getConfigDir()`-based path)
  - Project: `.claude/sisyphus.jsonc` in the current working directory
- JSONC format (JSON with comments and trailing commas) is parsed via `jsonc-parser`. Do not use `JSON.parse` on these files.
- `deepMerge()` does deep recursive merge of plain objects; arrays are replaced, not concatenated.
- Environment variables always win. All supported env vars are listed in `loadEnvConfig()`. When adding a new feature flag, add the env var handler there and document it.
- `generateConfigSchema()` returns a JSON Schema object for editor autocomplete. Keep it in sync when adding new config keys.
- `findContextFiles()` walks up the directory tree from `cwd` looking for `AGENTS.md` and `CLAUDE.md` files — this is the auto-context-injection mechanism.

### Common Patterns

```typescript
import { loadConfig } from '../config/loader.js';

// Load merged config (defaults + user + project + env)
const config = loadConfig();

// Check a feature flag
if (config.features.parallelExecution) { /* ... */ }

// Access model routing tier
const tier = config.routing.defaultTier; // 'LOW' | 'MEDIUM' | 'HIGH'

// Find AGENTS.md/CLAUDE.md files for context injection
import { findContextFiles, loadContextFromFiles } from '../config/loader.js';
const files = findContextFiles(process.cwd());
const context = loadContextFromFiles(files);
```

**Supported environment variables (partial list):**

| Variable | Effect |
|----------|--------|
| `OMC_PARALLEL_EXECUTION` | `true`/`false` — toggle parallel execution |
| `OMC_LSP_TOOLS` | `true`/`false` — toggle LSP tool integration |
| `OMC_MAX_BACKGROUND_TASKS` | Integer — max concurrent background tasks |
| `OMC_ROUTING_ENABLED` | `true`/`false` — toggle model routing |
| `OMC_ROUTING_DEFAULT_TIER` | `LOW`/`MEDIUM`/`HIGH` |
| `OMC_CODEX_DEFAULT_MODEL` | Default Codex model ID |
| `OMC_GEMINI_DEFAULT_MODEL` | Default Gemini model ID |
| `OMC_DELEGATION_ROUTING_ENABLED` | `true`/`false` |
| `EXA_API_KEY` | Enables Exa MCP server with this key |

## Dependencies

### Internal
- `../shared/types.js` — `PluginConfig`, `ExternalModelsConfig`, `DelegationRoutingConfig`
- `../utils/paths.js` — `getConfigDir()`

### External
- `jsonc-parser` — parses JSONC files
- Node built-ins: `fs` (`readFileSync`, `existsSync`), `path`, `os`

<!-- MANUAL: -->
