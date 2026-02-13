<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# providers

## Purpose
Git hosting provider abstraction layer. Auto-detects the hosting provider from git remote URLs and provides a uniform `GitProvider` interface for PR/MR operations, issue retrieval, and repository metadata across GitHub, GitLab, Bitbucket, Azure DevOps, and Gitea/Forgejo. Used by the `git-master` agent and PR creation skills to issue provider-appropriate CLI commands.

## Key Files
| File | Description |
|------|-------------|
| `types.ts` | Shared interfaces: `ProviderName`, `RemoteUrlInfo`, `PRInfo`, `IssueInfo`, `GitProvider` |
| `index.ts` | `detectProvider(remoteUrl)` — maps remote URLs to `ProviderName`; provider registry singleton; `getProvider()` factory |
| `github.ts` | `GitHubProvider` — wraps `gh` CLI for PR/issue operations |
| `gitlab.ts` | `GitLabProvider` — wraps `glab` CLI for MR/issue operations |
| `bitbucket.ts` | `BitbucketProvider` — Bitbucket-specific adapter |
| `azure-devops.ts` | `AzureDevOpsProvider` — Azure DevOps adapter; handles `dev.azure.com` and `*.visualstudio.com` hosts |
| `gitea.ts` | `GiteaProvider` — Gitea/Forgejo adapter |

## For AI Agents

### Working In This Directory
- All providers implement the `GitProvider` interface from `types.ts`. Adding a new provider requires: a new class file, registering it in `index.ts`, and adding its `ProviderName` to the union type in `types.ts`.
- `detectProvider()` matches on the hostname extracted from the remote URL. Azure DevOps is checked before generic patterns to avoid false matches against `visualstudio.com` subdomains.
- Provider classes use `execFileSync` with timeouts — they are synchronous and throw on CLI errors. Callers must handle exceptions.
- `GitHubProvider` uses the `gh` CLI; `GitLabProvider` uses `glab`. These must be installed separately.
- `PRInfo` uses `headBranch`/`baseBranch` terminology (GitHub style). Provider implementations must map their CLI output to this common shape.

### Common Patterns
- Auto-detect and use provider: `const name = detectProvider(remoteUrl); const provider = getProvider(name);`
- View a PR: `const pr = provider.viewPR(123);` — returns `PRInfo | null`.
- All CLI calls use `execFileSync` with `stdio: ['pipe', 'pipe', 'pipe']` and a 10-second timeout.
- Unknown or self-hosted providers fall back to `ProviderName = 'unknown'`.

## Dependencies

### Internal
None — providers module has no internal imports.

### External
- `node:child_process` — `execFileSync` / `execSync` for CLI invocation
- `gh` (system binary) — GitHub CLI
- `glab` (system binary) — GitLab CLI
- `az devops` (system binary, optional) — Azure DevOps CLI

<!-- MANUAL: -->
