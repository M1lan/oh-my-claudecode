# oh-my-claudecode v4.15.10: Bug Fixes

## Release Notes

Release with **3 bug fixes** across **4 merged PRs**.

### Highlights

- **fix(hud): keep watch mode running between polls** (#3659)
- **fix(team): deliver POSIX supervised worker launch through attempt descriptor** (#3657)
- **fix(rules-injector): bound upward rule walk when no project root exists** (#3654)

### Bug Fixes

- **fix(hud): keep watch mode running between polls** (#3659)
- **fix(team): deliver POSIX supervised worker launch through attempt descriptor** (#3657)
- **fix(rules-injector): bound upward rule walk when no project root exists** (#3654)

### Stats

- **4 PRs merged** | **0 new features** | **3 bug fixes** | **0 security/hardening improvements** | **0 other changes**

### Install / Update

The npm CLI and the Claude Code marketplace/plugin are separate install tracks, not either/or replacements. Update whichever track you use; if you have both installed, update both. CLI-dependent skill paths such as `ask`, `ccg`, and CLI-backed `team` require the `omc` CLI from the npm package.

**CLI / runtime:**

```bash
npm install -g oh-my-claude-sisyphus@4.15.10
```

**Claude Code plugin:**

```text
/plugin marketplace update omc
```

**Full Changelog**: https://github.com/Yeachan-Heo/oh-my-claudecode/compare/v4.15.9...v4.15.10

## Contributors

Thank you to all contributors who made this release possible!

@Iams4kura @Yeachan-Heo
