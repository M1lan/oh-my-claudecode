<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-13 | Updated: 2026-02-13 -->

# agents/

## Purpose
The agents/ directory contains markdown prompt templates that define the persona, responsibilities, constraints, and behavior of every specialized AI agent available in oh-my-claudecode. Each file is a self-contained system prompt that is injected when a subagent of that type is spawned via the Task tool. These templates are the authoritative source of truth for agent roles across the orchestration system.

## Key Files
| File | Description |
|------|-------------|
| `analyst.md` | Data and codebase analyst; investigates metrics, patterns, and findings |
| `api-reviewer.md` | Reviews API surface design, contracts, versioning, and compatibility |
| `architect.md` | System architecture decisions, component boundaries, and technical strategy |
| `build-fixer.md` | Diagnoses and repairs failing builds, CI errors, and compilation issues |
| `code-reviewer.md` | General-purpose code review for correctness, clarity, and maintainability |
| `critic.md` | Adversarial reviewer that stress-tests plans and proposals |
| `debugger.md` | Root-cause analysis and bug reproduction for runtime failures |
| `deep-executor.md` | Autonomous multi-step implementer for complex or ambiguous tasks |
| `dependency-expert.md` | Fetches and interprets official SDK/framework docs before implementation |
| `designer.md` | UI/UX and frontend design review and implementation guidance |
| `executor.md` | Precise implementer for well-scoped code changes; smallest viable diff |
| `explore.md` | Read-only codebase explorer; builds context without making changes |
| `git-master.md` | Git operations, branching strategy, commit hygiene, and history management |
| `information-architect.md` | Structures information, documentation hierarchies, and content models |
| `performance-reviewer.md` | Identifies bottlenecks, profiling strategies, and optimization opportunities |
| `planner.md` | Breaks large requests into ordered, atomic implementation tasks |
| `product-analyst.md` | Product metrics, feature analysis, and data-driven decision support |
| `product-manager.md` | Requirements gathering, prioritization, and product framing |
| `qa-tester.md` | Manual and exploratory testing strategies and defect reporting |
| `quality-reviewer.md` | Holistic code quality, architecture smell, and technical debt assessment |
| `quality-strategist.md` | Test coverage strategy, quality gates, and long-term quality planning |
| `researcher.md` | External research, documentation lookup, and knowledge synthesis |
| `scientist.md` | Hypothesis-driven experimentation, benchmarking, and analysis |
| `security-reviewer.md` | Vulnerability scanning, threat modeling, and secure-coding enforcement |
| `style-reviewer.md` | Enforces code style, naming conventions, and formatting rules |
| `test-engineer.md` | Writes and maintains automated test suites (unit, integration, e2e) |
| `ux-researcher.md` | User research synthesis, usability analysis, and experience recommendations |
| `verifier.md` | Final verification agent; confirms builds pass, tests green, no diagnostics |
| `vision.md` | High-level product vision alignment and strategic coherence review |
| `writer.md` | Documentation, changelogs, READMEs, and developer-facing content |

## For AI Agents

### Working In This Directory
These files are read-only prompt templates consumed by the orchestration layer. Do not modify them unless explicitly asked to update agent behavior. When adding a new agent, create a new `.md` file following the naming convention `{role}.md` using lowercase with hyphens. Each file should define: role, responsibilities, constraints, tool preferences, and output format.

### Common Patterns
- Agent files open with a `<Role>` block describing the agent's core identity.
- Constraints are listed explicitly (e.g., "Work ALONE. Task tool is BLOCKED.").
- Output format sections specify the expected structure of agent responses.
- Each agent template is self-contained and must not rely on other agent files at runtime.

## Dependencies

### Internal
- Referenced by `src/agents/` (TypeScript orchestration layer) when spawning subagents.
- Copied or symlinked into `~/.claude/modules/` during plugin installation.
- Listed in `~/.claude/CLAUDE.md` agent catalog section.

### External
None - pure markdown template files.

<!-- MANUAL: -->
