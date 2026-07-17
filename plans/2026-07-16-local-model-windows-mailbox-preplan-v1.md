# Pre-plan: local-model Windows and mailbox merge work

Status: preliminary brief only. Do not implement these topics in current merge.
Tracker: `oh-my-claudecode-rc3`

## Goal

Commission a frontier-model planning session that produces a concrete plan for a
well-selected local MLX or Ollama model plus purpose-built harness to resolve and
verify deferred Windows-platform and mailbox-notification merge work.

## Required planning phases

1. Scope exact deferred conflicts and acceptance tests. Separate Windows-platform
   behavior from mailbox-notification behavior; preserve current non-Windows and
   non-mailbox behavior.
2. Select local model by a small representative benchmark. Compare at most three
   installed candidates using the same bounded prompt, context, and tests. Record
   correctness, repair iterations, elapsed time, and token/context use.
3. Design task-specific harness before implementation: bounded context packing,
   branch/base/theirs extraction, conflict classification, local-model prompt,
   patch application, typecheck/test gates, automatic diagnostic feedback, retry
   limit, rollback, and human escalation criteria.
4. After the real implementation plan is complete, run a discrete meta-harness
   improvement phase for relevant `~` home-folder and shell environment tooling.
   Keep changes SCM-first, small, tested, reusable, and separate from project code.
5. Execute the real plan through the selected local model and new harness. Frontier
   model supervises contracts and evidence; it does not directly implement covered
   work unless operator explicitly overrides.
6. Re-run the meta-harness phase after execution. Compare before/after metrics from
   phase 2: success rate, retries, intervention count, elapsed time, context cost,
   and test results. Retain only improvements supported by evidence.
7. Extract proven reusable loop into `~/loops/` or the appropriate `~/.config/sh`
   harness component; update its tests and roadmap. Do not duplicate project logic.

## Real-plan deliverables

- Conflict inventory with `path:line` evidence and explicit defer boundaries.
- Local-model benchmark protocol, model choice, and rejection reasons.
- Harness architecture, commands, failure modes, retry budget, and evidence format.
- Ordered project implementation tasks and focused verification matrix.
- Separate pre-execution and post-execution meta-harness phases.
- Before/after comparison and extraction criteria aligned with NORTH STAR.

## Current-merge rule

Resolve these conflicts only enough to preserve `mymain` behavior and complete the
merge safely. Do not import new Windows-platform or mailbox-notification features.
Record exact deferred upstream commits/files for the later real plan.
