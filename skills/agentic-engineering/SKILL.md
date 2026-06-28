---
name: agentic-engineering
description: >-
  INVOKE/LOAD WHEN designing, implementing, or reviewing systems where an AI
  agent is the operator: agent harnesses, tool wrappers, background tasks,
  monitors/log streamers, MCP tools, compaction, memory/session persistence,
  goal loops, queues, retries, task registries, or any cap/timeout/truncation
  policy. Use especially when words like timeout, max lines, max bytes, safety
  cap, watchdog, background task, monitor, log tail, compaction, dropped events,
  resumability, recourse, fail closed, or long-running command appear.
---

# Agentic Engineering

Agentic systems are not normal human-operated UIs. The operator is a model with
lossy context, bounded tool results, compaction, restarts, and imperfect memory.
The harness therefore has one prime directive:

> **Constrain context. Preserve work. Preserve recourse.**

A model-facing stream may be summarized, throttled, truncated, or moved behind a
lookup tool. The underlying user work must not be destroyed merely because the
model-facing path became inconvenient.

This skill exists because of repeated harness failures where safety/display caps
were treated as execution policy:

- A Bash wrapper had a default hard kill after 30 minutes even after returning a
  background task id. Long-running work died because the harness assumed “too
  long” was a safety fact.
- A Bash wrapper killed commands after 64 MiB of output. The correct response to
  large output is to rotate/spill/index logs, not kill the process producing the
  evidence.
- Monitor/log tools previously failed closed when output exceeded a display
  budget: the model saw “too much output” behavior but had little or no recourse
  to inspect the durable raw stream.

These are the same bug: **bounding observability by killing work or removing
recourse.** Do not repeat it.

---

## When This Applies

Use this skill for any subsystem that mediates between real work and model
context:

- shell/Bash wrappers and long-running command execution
- background task managers, worker pools, queues, schedulers, and goal loops
- monitor/log streaming tools, deployment log tailers, watch-mode tests
- MCP tools and tool-result rendering/truncation
- session persistence, compaction, memory, summaries, and continuation prompts
- retries, watchdogs, leases, timeouts, heartbeats, cancellation, and cleanup
- any `MAX_*`, timeout, byte cap, line cap, rate limit, queue bound, or drop policy

If the system contains a phrase like “kill after,” “max output,” “dropped lines,”
“too many events,” “timeout,” “safety cap,” or “summarized for model context,”
run this review.

---

## Core Model

Agentic work has three separate planes. Keep them separate.

1. **Execution plane** — the real work: processes, jobs, workers, deploys,
   renders, tests, crawls, migrations.
2. **Evidence plane** — facts about the work with durability matched to the
   ownership contract: full logs, exit status, artifacts, timestamps, state
   transitions, task id, ownership, cwd, command, environment summary. Do not
   imply cross-process recovery unless the system actually owns that lifecycle.
3. **Context plane** — the bounded view shown to the model: tail, summary,
   progress event, compacted transcript, UI notification.

Most harness bugs come from confusing the context plane with the execution plane.
A context budget can justify dropping an injected line. It does **not** justify
killing the job.

---

## Non-Negotiable Design Rules

### 1. Bound context, not work

It is acceptable to cap:

- lines injected into the transcript
- bytes shown in a tool result
- update frequency
- summary size
- in-memory ring-buffer size

It is not acceptable to kill or abandon the underlying task because one of those
caps fired. Instead, spill to the system's evidence plane — a durable log when
that lifecycle is supported, or a live in-memory/task-status surface when the
work is explicitly owned by the current process — and return a pointer.

```text
Bad:  if outputBytes > 64MiB: kill(process)
Good: if outputBytes > displayBudget: rotateLog(); return { logPath, grepTool, tailTool }
```

### 2. Long-running work is normal

Agent tasks routinely run for hours: renders, builds, migrations, downloads,
research, evals, log watches, peer agents, cloud deploys. A default runtime cap
is not “safety” by itself.

- Do not impose arbitrary kill timers like “30 minutes because the harness says
  so.”
- If a kill deadline exists, it must be explicit, user/model-requested, visible
  in the task record, and changeable.
- Defaults should preserve work indefinitely unless there is a real resource
  threat.

### 3. Output volume is observability pressure, not execution failure

Large output means the display/indexing strategy is wrong or insufficient. It
should trigger degraded observability, not process death.

Preferred responses:

- append to durable log files
- rotate/compress logs
- keep a bounded in-memory tail
- expose `tail`, `head`, `range`, `grep`, and `stats`
- summarize recent meaningful events
- report dropped/suppressed counts for model-facing injections

Do **not** kill the producer just because it is noisy.

### 4. Every cap needs recourse

For every limit, answer: **what can the next agent do when this fires?**

- Max injected lines → where is the full log?
- Max output bytes → where did overflow go?
- Max event rate → how many events were suppressed, and where is the raw source?
- Max retained tasks → where is the archive, session event, or explicit “not retained” boundary?
- Compaction → what state can reconstruct what was running, and is it scoped to the live process or durable beyond it?
- Timeout → can it be extended, disabled, or intentionally killed later?

A cap without recourse is a trap.

### 5. Discoverability must match the ownership boundary

The model may lose the original tool result containing the task id during normal
turns or compaction. Therefore long-running work needs discoverable state inside
whatever runtime still owns it.

Do **not** invent a durable resume contract when the process/session is the true
owner. If child processes are supposed to die with the harness, then a live
in-memory registry plus a list/status tool is better than stale on-disk metadata
that pretends a later process can safely resume or kill work it no longer owns.
Use durable task records only when the work is intentionally designed to outlive
the current harness process and you have a safe identity/ownership model for it.

A good task record includes:

- stable task id / monitor id
- status: running, completed, failed, killed, unknown/stale
- command or job description
- cwd / project / branch if relevant
- pid/process group or external job id
- started_at, updated_at, ended_at
- exit code / signal / explicit kill reason
- log paths and artifact paths
- whether output was suppressed/truncated/dropped in the context plane
- how to inspect, stop, or clean it up

There must be a list/status tool or injected ephemeral-floating context that
lets the agent rediscover still-running tasks within the valid ownership
boundary.

### 6. Kills must be intentional and attributable

Killing work is destructive. It must have an actor and a reason.

Valid kill reasons:

- user explicitly asked
- model intentionally called a kill/cancel tool and stated why
- real machine/resource danger with a recorded reason
- task-specific deadline explicitly requested at launch

Invalid kill reasons:

- “default safety cap”
- “too much output for the transcript”
- “too many lines for the UI”
- “the polling call timed out”
- “the model did not check back quickly enough”

### 7. Fail degraded, not closed

When observability is overwhelmed, degrade gracefully:

```text
Live stream too noisy → pause injection, keep raw log, emit sparse summaries.
Tail too large → show last N lines plus log path and grep command.
Event queue too full → coalesce by event type and report suppressed counts.
Compaction too large → summarize and preserve task registry pointers for the live owner; do not promise recovery after owner death unless implemented.
Tool result too large → write full result to file and return path + preview.
```

A model should always have a next move.

---

## Agentic Engineering Checklist

Before implementing or approving a harness/tool cap, answer these in writing.

### Execution preservation

- What real work is happening underneath this tool?
- Under what conditions can the harness kill, cancel, orphan, or abandon it?
- Are those conditions explicit user/model choices, or hidden defaults?
- If the model-facing call times out, does the underlying work continue safely?

### Durable evidence

- Where is full output stored?
- Is it durable across the boundaries the system actually promises: turns, compaction, process restarts, or only the live process?
- Can the agent inspect the head, tail, arbitrary ranges, and grep/search it?
- Are truncation, dropped events, and suppressed updates counted and visible?

### Discovery and resume

- How does a later agent list all active tasks?
- What if it lost the original task id?
- Does the status surface include enough context to decide what to do next?
- Are completed/killed/failed tasks retained long enough to explain outcomes?

### Context-plane limits

- Which limits are purely for transcript/UI safety?
- Do any of them accidentally affect execution?
- When a limit fires, what exact recourse is returned to the model?
- Is the recourse usable without remembering hidden paths or prior tool output?

### Cancellation and cleanup

- Is cancel/kill separate from inspect/status?
- Does killing record actor, timestamp, signal, and reason?
- Are cleanup policies separate from execution policies?
- Could retention cleanup delete evidence the agent still needs?

### Product fit

- Is the cap based on a real product/resource requirement or an arbitrary guess?
- If it protects the machine, should it notify/ask before killing?
- If it protects context, why is it touching execution at all?

---

## Recommended Tool Surfaces

Long-running tools should usually expose this minimum set:

```text
start/run        -> returns id immediately or after a short foreground preview
list             -> all known active/recent tasks with compact status
status(id)       -> status, metadata, recent tail, suppression/truncation counts
read(id, range)  -> durable log ranges, head/tail, byte or line offsets
grep(id, query)  -> search durable logs/artifacts
kill(id, reason) -> explicit destructive cancellation
cleanup(id)      -> explicit artifact/task-record cleanup when appropriate
```

If the tool streams into the transcript, streaming is an optimization — not the
only source of truth.

---

## Anti-Patterns

### “Safety cap” with no threat model

A cap is not safety unless it names the concrete harm it prevents and why killing
is the least-bad response. “Thirty minutes is long” is not a threat model.

### Output-size kill switches

Output volume can fill disks eventually, but the first response should be log
rotation, compression, backpressure, warning, or user notification — not killing
without recourse.

### Transcript as the only log

If the only way to know what happened is “the model saw the tool output earlier,”
the system is not resumable.

### Fail-closed truncation

Returning “too much output” without a path to the full output is worse than a
large result. It converts an observability problem into a dead end.

### Hidden task registries

If a process is still running but no tool can list it, it is effectively lost.
That is acceptable only for truly external/user-owned processes, and even then
say so.

### Cleanup as correctness

Deleting old records may be necessary, but do not make cleanup the only thing
preventing context bloat. Archive or summarize before deleting evidence.

---

## Review Language Ben Expects

Use direct language when reviewing these systems:

- “This cap bounds the transcript, but it also kills the work. That is wrong.”
- “This should spill to a log and return a pointer, not fail closed.”
- “The agent can inspect this only if it remembers the id. Add list/discovery.”
- “The kill is not attributable. Record actor, reason, and timestamp.”
- “This is a context-plane problem leaking into the execution plane.”

---

## One-Line Summary

If an agentic subsystem gets overwhelmed, it should preserve the work, preserve
the evidence, and give the model a smaller doorway back in — not burn the house
down because the doorway got crowded.
