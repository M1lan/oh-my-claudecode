# oh-my-claudecode v4.15.0: add antigravity (agy), surface usage hint

## Release Notes

Release with **2 new features**, **8 bug fixes**, **2 other changes** across **22 merged PRs**.

### Highlights

- **feat(providers): add antigravity (agy) CLI as drop-in alternative to gemini** (#3315)
- **feat(hud): surface usage hint for API-key users when built-in usage unavailable (#3277)** (#3277)

### New Features

- **feat(providers): add antigravity (agy) CLI as drop-in alternative to gemini** (#3315)
- **feat(hud): surface usage hint for API-key users when built-in usage unavailable (#3277)** (#3277)

### Bug Fixes

- **fix(hooks): encode project paths in transcript resolution**
- **fix(jsonc): tolerate trailing commas in JSONC config files**
- **fix(post-tool-rules-injector): honor existing skip guards**
- **fix(team): verify cursor worker start submission** (#3296)
- **fix: configurable magic keyword triggers** (#3289)
- **fix(persistent-mode): bound thinking-only continuation loops** (#3280)
- **fix(session-search): fix Windows worktree transcript resolution + converge the encoder** (#3276)
- **fix(session-search): strip drive colon so current-scope search finds transcripts on Windows** (#3274)

### Documentation

- **docs(release): include PR #3300 in v4.14.8 notes**
- **docs: clarify psmux Windows team caveats** (#3312)
- **docs: clarify OMC automation and SDK surfaces**
- **docs: audit Claude Code changelog compatibility** (#3303)

### Other Changes

- **ci: run path-handling tests on a real Windows runner**
- **ci: move workflows to GitHub-hosted runners** (#3287)

### Stats

- **22 PRs merged** | **2 new features** | **8 bug fixes** | **0 security/hardening improvements** | **2 other changes**
