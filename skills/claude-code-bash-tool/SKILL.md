---
name: claude-code-bash-tool
description: >-
  INVOKE/LOAD BEFORE running any Bash tool call that involves waiting, sleeping,
  polling a long-running process, or making time-based judgment calls. WHY:
  Claude Code's Bash tool auto-backgrounds any command at its timeout
  (default ~120s), so `sleep N` for N > 120 never actually blocks for N seconds
  and the "completed" notification looks identical to a real finish. This breaks
  any attempt to dead-reckon elapsed time and has caused real, expensive mistakes
  (e.g. killing long-running experiments prematurely because perceived elapsed
  time did not match reality). KEYWORDS: "bash timeout", "sleep", "background",
  "elapsed time", "wall clock", "long-running", "poll", "monitor", "how long
  has it been", "kill the run".
---

# Claude Code Bash Tool

Rules and mental model for using Claude Code's Bash tool correctly, especially
around timeouts, backgrounding, and elapsed time.

## Core Mental Model

Claude Code's Bash tool **auto-promotes any command to a background task once
its timeout elapses**. The default timeout is **~120 seconds (2 minutes)**.

Concretely:

- If you run `sleep 3600`, the tool does **not** sleep for an hour. The
  command is backgrounded at ~120s and you receive a "completed"-looking
  notification.
- That notification is **indistinguishable** from a command that actually
  finished on its own. There is no signal that the sleep was cut short.
- Therefore every `sleep N` where `N > 120` is functionally identical: you
  always wait ~2 minutes of wall time, no matter what `N` you chose.

**You cannot dead-reckon elapsed time from sleep commands.** Ever.

## Rules

1. **Never use `sleep` to estimate elapsed time.** If you need to know how much
   time has actually passed, run `date '+%Y-%m-%d %H:%M:%S'` and compare against
   a recorded start time.

2. **Before any time-sensitive judgment call**, call `date`. Examples of
   time-sensitive judgment calls:
   - "This experiment has been training for 2 hours without converging — kill it."
   - "The deploy has been stuck for 30 minutes — roll back."
   - "The queue has been draining for 10 minutes — safe to cut over."

   All of these require a real wall-clock check, not a vibe.

3. **When monitoring long-running processes, do not chain `sleep X && check`.**
   Instead, check the process output directly. If it is not ready, check again
   later. Use `date` to know when you last checked.

4. **Never kill a long-running run based on how long you *think* it has been
   running.** Always verify with:
   - `date` for current wall time
   - The process's own timestamps / epoch counts / log output
   - Actual wall time per epoch computed from the data

## Quick Reference

| Situation | Do | Don't |
|-----------|----|-------|
| "Wait N minutes then check X" | Check X now, check again later, track with `date` | `sleep 600 && check X` |
| "How long has this been running?" | `date` + compare with recorded start | Mental math from sleeps |
| "Is it time to give up on the experiment?" | Read epoch/step timestamps from the log | Guess based on chat elapsed time |
| Short pause (<120s) between steps | `sleep 30` is fine | — |
| Long wait inside a single Bash call | Run the command with `run_in_background: true` and come back to it | `sleep 1800` |

## Origin Story

This rule exists because a Mamba training experiment was killed prematurely:
the perceived elapsed time was "several hours" based on `sleep` commands; the
actual elapsed time, verified after the fact, was ~20 minutes. The run was
terminated and an entire experimental branch was wasted because the Bash tool
gave zero indication that the sleeps had been silently interrupted.

Treat this as the concrete, expensive reason to always verify with `date` and
process-native timestamps before making time-based decisions.

## Red Flags — STOP

If you catch yourself reasoning in any of these shapes, stop and invoke this
skill:

- "It's been running for [N] minutes, so…"  → Did you call `date`? No? Stop.
- "Let me just `sleep 600` and then check." → No. Check now, come back.
- "The long sleep finished, so the job must be done." → The sleep may have been
  cut at 120s. Verify with `date` and the job's own logs.
- "I'll chain sleeps to get a longer wait." → Each one still caps at ~120s
  wall time. Use `run_in_background` or `ScheduleWakeup` instead.
