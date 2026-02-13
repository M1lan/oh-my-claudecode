<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# lib

## Purpose
Low-level library utilities that provide foundational primitives for the rest of the codebase. Contains three concerns: atomic JSON file writes (using temp-file-and-rename to prevent corruption on crash), runtime package version detection, and git worktree path resolution with `.omc/` subdirectory constants.

## Key Files
| File | Description |
|------|-------------|
| `atomic-write.ts` | `writeJsonAtomic()`, `ensureDirSync()` — write JSON to a temp file then atomically rename to target; prevents partial writes on crash |
| `version.ts` | `getRuntimePackageVersion()` — walks up the directory tree from the compiled file to find and read `package.json` at runtime |
| `worktree-paths.ts` | `getWorktreeRoot()`, `OmcPaths` constants, path validation and scoping for `.omc/` directories within a git worktree |

## For AI Agents

### Working In This Directory
- `writeJsonAtomic()` is the required write path for all state files (task JSON, heartbeat files, job status, etc.). Never use `fs.writeFileSync` directly for state files — a crash mid-write would corrupt the file.
- `getWorktreeRoot()` caches its result per `cwd` to avoid repeated `git` subprocess calls. The cache is module-scoped, so it persists across calls within the same process.
- `OmcPaths` is the single source of truth for `.omc/` subdirectory names. All code that constructs `.omc/` paths must use these constants rather than string literals.
- `getRuntimePackageVersion()` tries up to 5 directory levels upward to find `package.json`. It returns `'unknown'` on failure rather than throwing.

### Common Patterns
- Atomic write: `writeJsonAtomic(targetPath, dataObject)` — serialises and writes safely.
- Ensure directory exists before writing: `ensureDirSync(dirname(targetPath))`.
- Worktree root: `const root = getWorktreeRoot(); if (!root) throw new Error('Not in a git repo');`
- OMC path construction: `join(root, OmcPaths.STATE, 'myfile.json')`

## Dependencies

### Internal
None — this is a foundational module and must remain free of internal imports to avoid circular dependencies.

### External
- `node:fs` / `node:fs/promises` — file I/O
- `node:path` — path manipulation
- `node:crypto` — temp filename generation in `atomic-write.ts`
- `node:child_process` — `execSync` for `git rev-parse` in `worktree-paths.ts`

<!-- MANUAL: -->
