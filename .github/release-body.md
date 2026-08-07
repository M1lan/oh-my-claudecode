# oh-my-claudecode v4.15.8: add Kimi usage

## Release Notes

Release with **1 new feature**, **11 bug fixes**, **17 other changes** across **30 merged PRs**.

### Highlights

- **feat(hud): add Kimi usage monitoring** (#3610)

### New Features

- **feat(hud): add Kimi usage monitoring** (#3610)

### Bug Fixes

- **fix(ultragoal): restore fail-closed recovery when /goal guard blocks tools** (#3632)
- **fix(ast-tools): surface unavailable languages** (#3628)
- **fix(team): make worker startup acknowledgement durable** (#3588)
- **fix(doctor): make team-routing provider probes Windows-safe** (#3602)
- **fix(installer): accept TOML literal strings in Codex MCP registry parser** (#3603)
- **fix(installer): install hooks when settings.json has none** (#3599)
- **fix(installer): allow contained symlink config roots** (#3538)
- **fix(launch): stop omc re-login from isolated profile auth drift** (#3572)
- **fix(installer): preserve custom agent definitions** (#3539)
- **fix(hud): parse per-model weekly quotas from limits[] weekly_scoped entries** (#3577)
- **fix(post-tool-verifier): key background detection off tool_input** (#3579)

### Other Changes

- **ci: authorize final reconciled head for PR #3588** (#3616)
- **ci: authorize post-merge head for PR #3588** (#3615)
- **ci: authorize reconciled head for PR #3588** (#3614)
- **ci: authorize terminal head for PR #3603** (#3604)
- **ci: authorize terminal generated head for PR #3588** (#3598)
- **ci: authorize signed final head for PR #3588** (#3596)
- **ci: authorize final generated head for PR #3588** (#3594)
- **ci: authorize corrected head for PR #3538** (#3593)
- **ci: authorize signed generated head for PR #3588** (#3592)
- **ci: authorize exact generated head for PR #3588** (#3590)
- **ci: authorize rebased head for PR #3538** (#3589)
- **ci: authorize exact generated closure for PR #3572** (#3587)
- **ci: authorize rebased head for PR #3539** (#3585)
- **ci: restore exact-head authorization for PR #3539** (#3583)
- **ci: authorize signed merge head for PR #3539** (#3582)
- **ci: authorize repaired closure for PR #3539** (#3581)
- **ci: authorize exact generated closure for PR #3539 (dev)** (#3580)

### Stats

- **30 PRs merged** | **1 new feature** | **11 bug fixes** | **0 security/hardening improvements** | **17 other changes**

### Install / Update

The npm CLI and the Claude Code marketplace/plugin are separate install tracks, not either/or replacements. Update whichever track you use; if you have both installed, update both. CLI-dependent skill paths such as `ask`, `ccg`, and CLI-backed `team` require the `omc` CLI from the npm package.

**CLI / runtime:**

```bash
npm install -g oh-my-claude-sisyphus@4.15.8
```

**Claude Code plugin:**

```text
/plugin marketplace update omc
```

**Full Changelog**: https://github.com/Yeachan-Heo/oh-my-claudecode/compare/v4.15.7...v4.15.8

## Contributors

Thank you to all contributors who made this release possible!

@ltspace @Yeachan-Heo
