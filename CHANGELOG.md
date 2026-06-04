# oh-my-claudecode v4.14.5: Japanese katakana keyword, add Grok Build, full multi-repo workspace

## Release Notes

Release with **4 new features**, **1 security improvement**, **5 bug fixes**, **2 other changes** across **48 merged PRs**.

### Highlights

- **feat(keyword-detector): Japanese katakana keyword detection (with 〜について教えて informational guard)** (#3193)
- **feat(team): add Grok Build as a team worker + ask provider** (#3159)
- **feat(multi-repo): full multi-repo workspace support**
- **feat: persist ultragoal and enforce Claude goal activation** (#3102)
- **fix(security): enforce directory boundary in isTrustedPrefix (CLI trusted-path)** (#3152)

### New Features

- **feat(keyword-detector): Japanese katakana keyword detection (with 〜について教えて informational guard)** (#3193)
- **feat(team): add Grok Build as a team worker + ask provider** (#3159)
- **feat(multi-repo): full multi-repo workspace support**
- **feat: persist ultragoal and enforce Claude goal activation** (#3102)

### Security & Hardening

- **fix(security): enforce directory boundary in isTrustedPrefix (CLI trusted-path)** (#3152)

### Bug Fixes

- **fix(plugin): keep source hooks manifest direct-node** (#3201)
- **fix(multi-repo): validate team .omc paths against getOmcRoot, not the sub-repo**
- **fix(ci): make the full test suite green on Linux after the dev merge**
- **fix(multi-repo): accept repo subdirs as cwd; stop workspace search at $HOME**
- **fix(multi-repo): route dev-merged paths through getOmcRoot/resolveOmcStateRoot**

### Documentation

- **docs: add model × agent compatibility matrix (#3092)** (#3092)

### Other Changes

- **ci: use gajae self-hosted linux runner** (#3180)
- **chore(models): bump built-in Opus HIGH default to Claude Opus 4.8** (#3175)

### Stats

- **48 PRs merged** | **4 new features** | **5 bug fixes** | **1 security/hardening improvement** | **2 other changes**
