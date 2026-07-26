# Bug: finished review agents linger as idle teammate lanes, invisible to TaskList

## Summary

One-shot review agents spawned via the `Agent` tool with `run_in_background: false`
did **not** return synchronously. They came back as `in_process_teammate` lanes
("The agent is now running and will receive instructions via mailbox"), delivered
their reports into the session transcript rather than as tool results, and then —
once finished — parked as idle lanes that kept showing as alive for the rest of the
session.

Two separable defects:

1. **`run_in_background: false` did not produce a synchronous agent result.** The
   caller expected a blocking call returning the agent's report; it got a teammate
   lane plus, much later, an `idle_notification`.
2. **A finished teammate lane is neither visible nor reapable through the task
   tools.** `TaskList` returned `No tasks found` while both lanes were live.
   `TaskStop <name>` *does* work (it reported `task_type: in_process_teammate` with
   real task IDs `ta0m00ne6` / `tnwd00yb9`), but nothing surfaces those names or IDs,
   so an operator watching the roster sees agents "still running" with no documented
   way to enumerate or stop them.

Net effect for the caller: it polled for results that were never coming as tool
results, then had to extract the reports out of the subagent transcript JSONL by
hand (`jq` over `~/.claude/projects/<project>/<session>.jsonl`) to read them at all.

## Observed 2026-07-26

Session `bf78eb99-46b9-482a-9496-8660debd2232`, cwd `~/mysrc/rmux`,
Claude Code 2.1.220, OMC on `mymain`.

```text
Agent(subagent_type: oh-my-claudecode:critic,    name: plan-critic,    run_in_background: false)
Agent(subagent_type: oh-my-claudecode:architect, name: plan-architect, run_in_background: false)
  -> "Spawned successfully ... will receive instructions via mailbox"   (both)

TaskList  -> "No tasks found"                                (while both were live)
03:51:00Z -> {"type":"idle_notification","from":"plan-critic","idleReason":"available"}
03:52:04Z -> {"type":"idle_notification","from":"plan-architect","idleReason":"available"}
   ... lanes still listed as alive ~2h later, doing nothing ...
TaskStop plan-critic     -> stopped ta0m00ne6 (in_process_teammate)
TaskStop plan-architect  -> stopped tnwd00yb9 (in_process_teammate)
```

Both agents completed their work correctly. The defect is purely in lifecycle and
observability, not in agent output.

## Reproduction

1. In a session with OMC loaded, call `Agent` twice in one message with
   `run_in_background: false` and distinct `name` values.
2. Wait for both to finish (`idle_notification`, `idleReason: available`).
3. Call `TaskList` → no entries, despite live lanes.
4. Observe the lanes still presented as alive indefinitely.
5. `TaskStop <name>` reaps them, proving they were tracked as
   `in_process_teammate` tasks all along.

## Root cause — what is proven vs unproven

**Unproven that OMC causes defect 1.** Searched OMC for any rewrite of the flag:

- `src/hooks/bridge.ts:2629` inspects `originalTaskInput?.run_in_background === true`
  only to emit a `[BACKGROUND PERMISSIONS]` warning when a background agent might
  need tools it cannot interactively request. Inspect-only, no mutation.
- `src/features/delegation-enforcer.ts:112` merely declares `run_in_background?: boolean`
  on its input interface for model enforcement.
- No code found in `src/`, `hooks/`, `agents/`, or `skills/` that sets or flips
  `run_in_background` on an outgoing `Agent` call.

So teammate-lane spawning and idle parking look like **Claude Code core behavior**
(`in_process_teammate` is a harness task type), not something OMC introduces. This
note lives here because OMC is the layer that pushes heavy delegation — the defect
surfaces constantly under OMC usage patterns — but the fix may well belong upstream.
Do not file this as an OMC code defect without first reproducing with OMC disabled
(`DISABLE_OMC=1`).

**Proven:** `TaskList` does not enumerate `in_process_teammate` lanes, and
`TaskStop` by lane name does reap them.

## Impact

- Wasted turns polling for results that arrive by a different channel.
- Reports recoverable only by parsing subagent transcript JSONL — and the tool docs
  explicitly warn against reading the `.output` symlink because it is the full
  transcript and will overflow context. There is no sanctioned cheap read path.
- Idle lanes accumulate across a long session with no enumeration and no reaping
  documented, so the operator cannot tell finished work from running work.
- OMC's own guidance ("delegate multi-file changes, refactors, reviews...") makes
  the accumulation worse the more correctly the operator follows it.

## Workaround

Treat one-shot agents as fire-and-harvest:

1. Spawn, then wait for the completion/idle notification rather than expecting a
   synchronous tool result.
2. Harvest the report (transcript extraction, or have the agent write its report to
   a file under `~/tmp/` — more reliable and far cheaper in context; a brief that
   ends "write your full report to `~/tmp/<name>.md`" sidesteps the whole problem).
3. `TaskStop <name>` immediately once harvested, so the roster reflects reality.

Asking the agent to persist its own report is the pragmatic fix available today and
is what actually worked in the session above.

## Next steps

1. Reproduce with `DISABLE_OMC=1` to attribute defect 1 to core or to OMC.
2. If core: report upstream with the transcript above.
3. If OMC: find the rewrite path and stop it.
4. Regardless of owner, consider an OMC-side convenience: have delegation guidance
   (and the review-oriented skills) instruct one-shot agents to write reports to
   `~/tmp/` and instruct the caller to `TaskStop` after harvest.

Tracker: `oh-my-claudecode-omc-teammate-idle-lane-leak-yie`.
