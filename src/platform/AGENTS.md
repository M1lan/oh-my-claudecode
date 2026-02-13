<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# platform

## Purpose
Platform abstraction layer providing OS detection and cross-platform process management utilities. Exports boolean helpers for OS identification (`isWindows()`, `isMacOS()`, `isLinux()`, `isUnix()`) and a cross-platform process tree kill function that uses `taskkill /T` on Windows and negative-PID group signals on Unix.

## Key Files
| File | Description |
|------|-------------|
| `index.ts` | OS detection helpers (`isWindows`, `isMacOS`, `isLinux`, `isUnix`, `isPathRoot`), `PLATFORM` constant; re-exports from `process-utils.ts` |
| `process-utils.ts` | `killProcessTree(pid, signal)` — async cross-platform process tree termination with Windows and Unix implementations |

## For AI Agents

### Working In This Directory
- All OS-conditional code in the codebase should branch on `isWindows()` / `isMacOS()` / `isLinux()` from this module rather than checking `process.platform` directly.
- `killProcessTree()` defaults to `SIGTERM` on Unix. Pass `SIGKILL` only as a last resort. On Windows, `/F` (force) is used only when the signal maps to `SIGKILL`.
- `isPathRoot()` correctly handles both Unix (`/`) and Windows (`C:\`) filesystem roots by using `path.parse().root`.
- This module has no state — all exports are pure functions or derived constants.

### Common Patterns
- Platform branch: `if (isWindows()) { /* win32 path */ } else { /* unix path */ }`
- Kill a spawned process group: `await killProcessTree(child.pid!, 'SIGTERM')`
- Path root check: `while (!isPathRoot(dir)) { dir = dirname(dir); }`

## Dependencies

### Internal
None — foundational platform module.

### External
- `node:path` — `path.parse()` for root detection
- `node:child_process` — `execSync` / `execFile` for process management
- `node:util` — `promisify`
- `node:fs/promises` — async file operations in process-utils

<!-- MANUAL: -->
