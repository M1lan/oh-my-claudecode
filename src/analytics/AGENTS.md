<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# analytics

## Purpose

Comprehensive token tracking, cost estimation, and session analytics for Claude API usage. This module collects per-session token counts and model pricing data from HUD stdin events and offline transcript files, persists them to `~/.omc/state/token-tracking.jsonl`, and exposes query, export, and summary APIs consumed by the CLI analytics subcommands and the `learn-about-omc` skill. It also integrates with the external `tokscale` CLI for live pricing lookups.

## Key Files

| File | Description |
|------|-------------|
| `types.ts` | Shared interfaces: `TranscriptEntry`, `TokenUsage`, `CostBreakdown`, `SessionTokenStats`, `AggregateTokenStats`, `PRICING` map |
| `token-tracker.ts` | Singleton `TokenTracker` class; appends `TokenUsage` records to `token-tracking.jsonl` and maintains an in-memory session index |
| `cost-estimator.ts` | Synchronous cost calculation from hardcoded pricing; `calculateCost()` is the fast path used by the HUD |
| `session-manager.ts` | Reads/writes `SessionMetadata` and `SessionHistory` via the state-manager; tracks task counts, errors, and git diff stats |
| `session-types.ts` | Types for `SessionMetadata`, `SessionAnalytics`, `SessionHistory`, `SessionSummary`, `SessionTag` |
| `metrics-collector.ts` | Aggregates multi-session stats into rollup summaries for CLI display |
| `query-engine.ts` | Filters and sorts `TokenUsage` records from the JSONL log; supports date ranges, session IDs, model names |
| `export.ts` | Exports analytics data to CSV or JSON for external tooling |
| `token-extractor.ts` | Extracts token counts from HUD stdin JSON in real time; creates `TokenSnapshot` deltas |
| `output-estimator.ts` | Estimates output tokens when API response data is unavailable; extracts session IDs from stdin |
| `analytics-summary.ts` | Produces human-readable analytics summaries used by the `learn-about-omc` skill |
| `transcript-scanner.ts` | Scans `~/.claude/projects/` for JSONL transcript files to process offline |
| `transcript-parser.ts` | Parses individual transcript JSONL entries into `TranscriptEntry` objects |
| `transcript-token-extractor.ts` | Walks parsed transcript entries and extracts `TokenUsage` records |
| `session-catalog.ts` | Derives a session list from `token-tracking.jsonl` without reading session-history state |
| `tokscale-adapter.ts` | Wraps the `tokscale` CLI; provides async pricing lookups with fallback to hardcoded values |
| `backfill-dedup.ts` | Deduplication logic for backfill runs (deprecated; kept for backward compatibility) |
| `backfill-engine.ts` | Reads legacy transcript files and backfills the JSONL log (deprecated) |
| `index.ts` | Re-exports all public symbols from the module |

## For AI Agents

### Working In This Directory

- The persistent log is `~/.omc/state/token-tracking.jsonl`. Each line is a `TokenUsage` JSON object. Append-only; never truncate or rewrite.
- `getTokenTracker()` returns the singleton; call `recordUsage()` to add a record.
- Cost calculations must remain synchronous for the HUD fast path. Use `calculateCost()` from `cost-estimator.ts`. Async pricing from `tokscale-adapter.ts` is only for CLI display.
- Backfill (`backfill-engine.ts`, `backfill-dedup.ts`) is deprecated. Do not add new callers. `tokscale-adapter.ts` replaces that path.
- Model name normalisation happens in `cost-estimator.ts` via `normalizeModelName()`. All new pricing lookups must go through that function.

### Common Patterns

```typescript
// Record token usage from HUD stdin
import { getTokenTracker } from './token-tracker.js';
const tracker = getTokenTracker();
await tracker.recordUsage(tokenUsageObject);

// Fast synchronous cost for HUD
import { calculateCost } from './cost-estimator.js';
const cost = calculateCost({ modelName, inputTokens, outputTokens, cacheCreationTokens, cacheReadTokens });

// Query historical usage
import { QueryEngine } from './query-engine.js';
const engine = new QueryEngine();
const records = await engine.query({ sessionId, dateRange });
```

## Dependencies

### Internal
- `../features/state-manager/index.js` — state read/write for session metadata
- `../hooks/omc-orchestrator/index.js` — `getGitDiffStats()` used by session-manager
- `../utils/paths.js` — config directory resolution
- `../lib/version.js` — runtime version

### External
- `tokscale` CLI (optional, for live pricing) — invoked via child process in `tokscale-adapter.ts`
- Node built-ins: `fs`, `fs/promises`, `path`, `os`, `child_process`

<!-- MANUAL: -->
