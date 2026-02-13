<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# installer

## Purpose

Installation system that sets up OMC components in the Claude Code config directory (`~/.claude/`) during `omc update` / `omc install`. It copies agent definitions, skill files, and HUD assets from the npm package into the user's config directory, writes the Claude Code `settings.json` hooks block, and registers the OMC MCP server. Hook scripts are Node.js `.mjs` files (bash hooks were removed in v3.9.0). Cross-platform support is provided via `isWindows()` detection and `MIN_NODE_VERSION` enforcement.

## Key Files

| File | Description |
|------|-------------|
| `index.ts` | Main installer: defines directory constants (`AGENTS_DIR`, `COMMANDS_DIR`, `SKILLS_DIR`, `HOOKS_DIR`, `HUD_DIR`, `SETTINGS_FILE`, `VERSION_FILE`), implements `install()`, `isInstalled()`, `getInstallInfo()`, and all copy/patch helpers |
| `hooks.ts` | Hook script generation: `getHookScripts()` returns the `.mjs` hook file contents; `getHooksSettingsConfig()` returns the `settings.json` hooks block; exports `isWindows`, `MIN_NODE_VERSION` |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `__tests__/` | Jest unit tests: `claude-md-merge.test.ts` (CLAUDE.md section merge logic), `safe-installer.test.ts` (atomic write and permission safety) |

## For AI Agents

### Working In This Directory

- Installation is idempotent. `install()` uses marker-based section replacement to patch `settings.json` and `CLAUDE.md` without destroying existing user content.
- The marker pattern is line-anchored (search from start of line) to prevent false matches inside code blocks. Use `findMarker()` rather than `indexOf` when searching for OMC-managed sections.
- Hook scripts are pure `.mjs` — no bash. When modifying hook behaviour, edit the template strings in `hooks.ts` only. Do not reintroduce bash hooks.
- `CORE_COMMANDS` is intentionally empty since v3.0. Commands are now plugin-scoped skills. Do not add entries to it.
- Atomic writes (write to temp file then rename) are required for any file that Claude Code reads at startup (`settings.json`, `CLAUDE.md`). See `safe-installer.test.ts` for the expected pattern.
- The version written to `VERSION_FILE` (`~/.claude/.omc-version.json`) is read by the auto-update feature to detect installed version. Always update it after a successful install.

### Common Patterns

```typescript
import { install, isInstalled, getInstallInfo } from '../installer/index.js';

// Check before installing
if (!isInstalled()) {
  await install();
}

// Get installed version info
const info = getInstallInfo();
// info.version, info.installedAt, info.configDir

// From hooks.ts — hook script template
import { getHookScripts, getHooksSettingsConfig } from './hooks.js';
const scripts = getHookScripts();       // { 'pre-tool-use.mjs': '...', ... }
const hooksConfig = getHooksSettingsConfig(); // settings.json hooks block
```

**Directory constants (all under `~/.claude/` by default):**

| Constant | Path |
|----------|------|
| `AGENTS_DIR` | `~/.claude/agents/` |
| `COMMANDS_DIR` | `~/.claude/commands/` |
| `SKILLS_DIR` | `~/.claude/skills/` |
| `HOOKS_DIR` | `~/.claude/hooks/` |
| `HUD_DIR` | `~/.claude/hud/` |
| `SETTINGS_FILE` | `~/.claude/settings.json` |
| `VERSION_FILE` | `~/.claude/.omc-version.json` |

## Dependencies

### Internal
- `../utils/config-dir.js` — `getConfigDir()` to resolve `~/.claude/`
- `../lib/version.js` — `getRuntimePackageVersion()`
- `./hooks.js` — hook script content and settings config

### External
- Node built-ins: `fs` (`existsSync`, `mkdirSync`, `writeFileSync`, `readFileSync`, `chmodSync`, `readdirSync`), `path`, `os`, `child_process`

<!-- MANUAL: -->
