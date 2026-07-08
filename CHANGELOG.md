# oh-my-claudecode v4.15.3: support disabled keyword, support native TypeScript, add antigravity (agy)

## Release Notes

Release with **4 new features**, **31 bug fixes**, **4 other changes** across **69 merged PRs**.

### Highlights

- **feat(keyword-detector): support disabled keyword config**
- **feat(lsp): support native TypeScript 7 server** (#3405)
- **feat(providers): add antigravity (agy) CLI as drop-in alternative to gemini** (#3315)
- **feat(hud): surface usage hint for API-key users when built-in usage unavailable (#3277)** (#3277)

### New Features

- **feat(keyword-detector): support disabled keyword config**
- **feat(lsp): support native TypeScript 7 server** (#3405)
- **feat(providers): add antigravity (agy) CLI as drop-in alternative to gemini** (#3315)
- **feat(hud): surface usage hint for API-key users when built-in usage unavailable (#3277)** (#3277)

### Bug Fixes

- **fix(keyword-detector): stop ralph false-firing on proper-noun/identifier mentions** (#3435)
- **fix(rules-injector): parse multi-line rule arrays authored with CRLF** (#3415)
- **fix(subagent-tracker): mark unmatched stop telemetry** (#3417)
- **fix(installer): deploy hook libs before entrypoints** (#3407)
- **fix(hooks): raise UserPromptSubmit timeouts to stop 3s skill-injector abort** (#3398)
- **fix(learner): respect OMC_STATE_DIR in skill-sessions state path** (#3397)
- **fix(team): tolerate slow worker start submit repaint** (#3395)
- **fix: hide nested hook child processes on Windows** (#3385)
- **fix(keyword-detector): exempt quoted spans from activation-intent checks**
- **fix(hud): show enterprise billing-period spend for non-USD currencies** (#3367)
- **fix(model-routing): support Claude Sonnet 5 defaults** (#3370)
- **fix(model-routing): stop halving the indented code-block count** (#3364)
- **fix: respect home path boundary in HUD cwd** (#3360)
- **fix(hud): render cwd as ~ and forward slashes on Windows** (#3359)
- **fix(project-memory): normalize hot-path separators for Windows scope affinity** (#3357)
- **fix(worktree): anchor .omc state to superproject, not git submodule** (#3350)
- **fix(perf): widen CI envelope for subagent-lock benchmark (#3352)** (#3352)
- **fix: honor disabled tools in standalone MCP** (#3346)
- **fix(installer): prune legacy standalone hook files** (#3342)
- **fix(persistent-mode): keep stop reinforcement quiet while a delegated subagent is running** (#3338)
- **fix: let ultragoal guard escape standalone deadlock** (#3343)
- **fix(session-search): encode underscores in project dir name (current-scope returns 0 matches)** (#3330)
- **fix(ccg): default to antigravity advisor** (#3327)
- **fix(hooks): encode project paths in transcript resolution**
- **fix(jsonc): tolerate trailing commas in JSONC config files**
- **fix(post-tool-rules-injector): honor existing skip guards**
- **fix(team): verify cursor worker start submission** (#3296)
- **fix: configurable magic keyword triggers** (#3289)
- **fix(persistent-mode): bound thinking-only continuation loops** (#3280)
- **fix(session-search): fix Windows worktree transcript resolution + converge the encoder** (#3276)
- **fix(session-search): strip drive colon so current-scope search finds transcripts on Windows** (#3274)

### Documentation

- **docs(readme): update Discord invite link** (#3373)
- **docs(release): clarify install tracks** (#3362)
- **docs(release): include PR #3300 in v4.14.8 notes**
- **docs: clarify psmux Windows team caveats** (#3312)
- **docs: clarify OMC automation and SDK surfaces**
- **docs: audit Claude Code changelog compatibility** (#3303)

### Other Changes

- **ci(guard): fail PRs that commit dist/ or bridge/ build artifacts** (#3351)
- **chore: rebuild session search encoder artifacts** (#3333)
- **ci: run path-handling tests on a real Windows runner**
- **ci: move workflows to GitHub-hosted runners** (#3287)

### Stats

- **69 PRs merged** | **4 new features** | **31 bug fixes** | **0 security/hardening improvements** | **4 other changes**
