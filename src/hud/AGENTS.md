<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# hud

## Purpose

Heads-up display (HUD) system that renders real-time status information as a statusline for Claude Code. The HUD binary (`index.ts`) is invoked on every Claude Code hook event; it reads stdin JSON, extracts token usage, queries OMC state files, fetches rate limit data from the Anthropic OAuth API, and outputs a formatted statusline string. Rendered elements include context window usage, token/cost analytics, active execution mode state (ralph, ultrawork, autopilot, PRD), agent activity, todos, skills, git info, session health, and rate limit bars.

## Key Files

| File | Description |
|------|-------------|
| `index.ts` | HUD entry point; orchestrates stdin read, token recording, state queries, and render pipeline |
| `render.ts` | Composes final statusline string from `HudRenderContext` by calling element renderers |
| `state.ts` | Reads/writes HUD state file (`~/.omc/state/hud.json`); manages running task list and HUD config |
| `omc-state.ts` | Read-only readers for ralph, ultrawork, PRD, and autopilot state files with staleness detection (2-hour TTL) |
| `types.ts` | All HUD types: `HudRenderContext`, `SessionHealth`, `StatuslineStdin`, `RateLimits`, `HudConfig`, mode state interfaces |
| `stdin.ts` | Parses Claude Code stdin JSON; extracts context window percent, model name |
| `transcript.ts` | Parses the current session transcript to find running agents and skill invocations |
| `usage-api.ts` | Fetches rate limit utilisation from `api.anthropic.com/api/oauth/usage`; reads credentials from macOS Keychain or `~/.claude/.credentials.json`; caches results (30s success, 15s failure) |
| `analytics-display.ts` | Formats token/cost analytics lines for HUD output using analytics module data |
| `background-tasks.ts` | Reads background task state for display in the HUD |
| `background-cleanup.ts` | Removes stale background task state files |
| `colors.ts` | Terminal colour helpers (`bold`, `dim`, ANSI escape codes) |
| `sanitize.ts` | Strips problematic characters from HUD output before writing to stdout |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `elements/` | Individual statusline element renderers — one file per HUD segment: `agents.ts`, `autopilot.ts`, `background.ts`, `context.ts`, `cwd.ts`, `git.ts`, `limits.ts`, `model.ts`, `permission.ts`, `prd.ts`, `ralph.ts`, `session.ts`, `skills.ts`, `thinking.ts`, `todos.ts` |

## For AI Agents

### Working In This Directory

- The HUD runs on every hook event and must complete quickly. Avoid synchronous I/O in the hot path; prefer the cached values already loaded by `state.ts` and `usage-api.ts`.
- Each element renderer in `elements/` receives `HudRenderContext` and returns a string (empty string if nothing to show). Element renderers must never throw — wrap risky operations in try/catch and return `''` on failure.
- `omc-state.ts` reads state files written by execution modes (ralph, ultrawork, autopilot). Files older than 2 hours are treated as stale and ignored.
- Token recording (`recordTokenUsage()` in `index.ts`) is fire-and-forget — errors are swallowed so they never break HUD rendering.
- `usage-api.ts` caches the OAuth API response; do not bypass the cache by calling the API directly.
- When adding a new HUD element: create `elements/mynew.ts`, export a `renderMynew(ctx: HudRenderContext): string` function, import it in `render.ts`, and add it to the render composition.

### Common Patterns

```typescript
// New element renderer (elements/mynew.ts)
import type { HudRenderContext } from '../types.js';

export function renderMynew(ctx: HudRenderContext): string {
  if (!ctx.mynewData) return '';
  try {
    return `[${ctx.mynewData.value}]`;
  } catch {
    return '';
  }
}

// Registering in render.ts
import { renderMynew } from './elements/mynew.js';
// ... add renderMynew(ctx) to the parts array in render()

// Reading OMC mode state (read-only)
import { readRalphStateForHud } from './omc-state.js';
const ralphState = readRalphStateForHud(); // null if absent or stale
```

## Dependencies

### Internal
- `../analytics/token-extractor.js` — `extractTokens`, `TokenSnapshot`
- `../analytics/output-estimator.js` — `extractSessionId`
- `../analytics/token-tracker.js` — `getTokenTracker`
- `../features/auto-update.js` — `compareVersions`
- `../lib/version.js` — `getRuntimePackageVersion`
- `../utils/paths.js` — `getClaudeConfigDir`

### External
- Node built-ins: `fs`, `path`, `os`, `https`, `child_process`

<!-- MANUAL: -->
