<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# utils

## Purpose
Utility functions shared across the codebase. Covers three concerns: configuration directory resolution (respecting the `CLAUDE_CONFIG_DIR` environment variable), cross-platform file system path utilities (forward-slash normalisation, shell quoting, safe deletion), and CJK-aware string width calculation for accurate terminal display layout.

## Key Files
| File | Description |
|------|-------------|
| `config-dir.ts` | `getConfigDir()` — returns the Claude config directory, defaulting to `~/.claude`; respects `CLAUDE_CONFIG_DIR` env var |
| `paths.ts` | Path utilities: `getClaudeConfigDir()`, `toForwardSlash()`, `toShellPath()`, safe file/directory removal helpers |
| `string-width.ts` | `isCJKCharacter()`, `getStringWidth()` — visual width calculation for strings containing CJK double-width characters |

## For AI Agents

### Working In This Directory
- `getClaudeConfigDir()` in `paths.ts` is the canonical way to locate `~/.claude/` from any module. Do not hardcode `~/.claude` anywhere in the codebase — always call this function.
- `config-dir.ts` is a thin leaf module imported by `paths.ts`. Prefer importing from `paths.ts` in most cases.
- `toForwardSlash()` must be applied to any path written into a JSON config file or shell command string — backslashes break shell parsing on Windows.
- `string-width.ts` has no external dependencies by design. For full Unicode support beyond CJK (e.g. emoji, combining characters), consider the `string-width` npm package, but do not add it without discussion.

### Common Patterns
- Import the config dir: `import { getClaudeConfigDir } from '../utils/paths.js'`
- Shell-safe paths: `toShellPath(somePath)` handles quoting for paths with spaces.
- CJK-aware truncation: call `getStringWidth(str)` instead of `str.length` when rendering to terminal columns.

## Dependencies

### Internal
None — this is a foundational utility module with no internal imports.

### External
- `node:os` — `homedir()` for default config directory fallback
- `node:path` — path manipulation
- `node:fs` — file existence checks and removal

<!-- MANUAL: -->
