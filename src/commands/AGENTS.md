<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# commands

## Purpose

Command expansion utilities that provide SDK-compatible access to OMC slash commands. This thin module reads `.md` command template files from `~/.claude/commands/`, parses their YAML frontmatter and body, and expands `$ARGUMENTS` placeholders so callers can feed the result directly into an SDK `query()` call. It is the bridge between slash command files on disk and programmatic invocation via the Claude Agent SDK.

## Key Files

| File | Description |
|------|-------------|
| `index.ts` | All public exports: `getCommand`, `getAllCommands`, `listCommands`, `expandCommand`, `expandCommandPrompt`, `commandExists`, `expandCommands`, plus the `CommandInfo` and `ExpandedCommand` interfaces |

## For AI Agents

### Working In This Directory

- This module is intentionally thin — it does filesystem reads and string substitution only. Do not add network calls, state management, or analytics here.
- Command files live in `~/.claude/commands/<name>.md`. The module discovers them at runtime via `getClaudeConfigDir()`.
- Frontmatter is a minimal YAML block delimited by `---`. Only the `description:` key is extracted; all other frontmatter fields are ignored.
- `$ARGUMENTS` is the only supported template variable. Replacement is a global string replace, not a template engine.
- The module has no caching — every call reads from disk. If hot-path performance matters, cache results at the call site.

### Common Patterns

```typescript
import { expandCommandPrompt } from 'oh-my-claudecode';
import { query } from '@anthropic-ai/claude-agent-sdk';

// Expand a slash command for SDK use
const prompt = expandCommandPrompt('ultrawork', 'Refactor the auth module');
if (prompt) {
  for await (const msg of query({ prompt })) {
    console.log(msg);
  }
}

// Check existence before expanding
import { commandExists, expandCommand } from 'oh-my-claudecode';
if (commandExists('ralph')) {
  const expanded = expandCommand('ralph', userInput);
}

// Batch expansion
import { expandCommands } from 'oh-my-claudecode';
const results = expandCommands([
  { name: 'ralph', args: 'task one' },
  { name: 'ultrawork', args: 'task two' },
]);
```

## Dependencies

### Internal
- `../utils/paths.js` — `getClaudeConfigDir()` to locate the commands directory

### External
- Node built-ins: `fs` (`readFileSync`, `existsSync`, `readdirSync`), `path`

<!-- MANUAL: -->
