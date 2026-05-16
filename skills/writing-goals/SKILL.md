---
name: writing-goals
description: >-
  Draft `/goal` text that won't spam-loop the model into oblivion. Use when
  the user says "what's a good /goal for this?", "draft me a goal", "set up
  a goal", "give me /goal text", or any variant of asking for goal phrasing
  before they invoke `/goal`. Codifies the structural fixes that prevent the
  /goal stop hook from firing 90+ times in a row because the condition was
  un-meetable by the model alone.
---

# Writing /goal text

`/goal <text>` installs a session-scoped Stop hook that re-fires after every
model turn until the condition holds. Used well, it keeps the model on a
single track for hours. Used poorly, it traps the model in an infinite
re-prompt loop when the condition can only be satisfied by the user or by
real-world events.

This skill exists because of one specific failure mode that has happened
to this user multiple times: the model spamming "Blocked." 90–100 times
while the user was AFK, because the goal condition required hardware
verification (server restart, flight test, paired CC build) that the model
could not perform itself.

## ⚠️ Three properties of a goal that won't trap the model

1. **Statically auditable verification.** The condition should resolve via
   commands the model can run autonomously — `grep`, `cat`, `ls`,
   `luac -p`, reading a perf log, etc. If verification requires
   "user observes X in-game" or "fractal approves the merge", the goal
   condition can never be self-checked and the hook will keep firing.

2. **Blocking gates explicit.** When a step legitimately CAN'T be done
   by the model alone — server restart with players online, jar swap
   on a shared environment, code review approval, hardware build — call
   it out in the goal text with `If blocked, /notify`. This signals the
   model to ping once via the notify skill, then stop normally, rather
   than respond "Blocked." until the heat death of the universe.

3. **Bounded scope.** Single feature, named files, measurable target. Not
   "make the airship faster" but "backend `runControlTick` p50 < 100ms,
   verified by reading `autopilot.perf.log`."

## Template

```
Apply <N> patches and verify the targets:

1. <Patch 1 — file path + concrete change>
2. <Patch 2 — file path + concrete change>
3. <…>

Targets verified by <statically auditable command> after <real-world
verification step, if any>:

- <Metric 1> <comparator> <number> (currently <baseline>)
- <Metric 2> <comparator> <number> (currently <baseline>)

<If a blocking gate exists: name it explicitly. Example:>
Requires <server restart / authorization / hardware build / etc>.
If blocked, /notify.
```

## Concrete example (this codebase, 2026-05-13)

**Good:**
> Backend `runControlTick` p50 drops noticeably below 200ms (target:
> <100ms) after applying (1) skip-redundant-RSC-writes in
> `lib/spring_axis.lua` and `lib/thrust_pair.lua`, and (2) reduced
> `getLimit`/`isRunning` polling cadence. Verified by reading
> `/0/autopilot.perf.log` after a 30s flight test. If blocked, /notify.

Why it works:
- Verification is `cat` the perf log + read the p50 line — model can do it
- Hardware test (fly for 30s) is explicit and one-shot, not a continuous
  pre-condition
- `If blocked, /notify` tells the model to escape rather than spam

**Bad (previous session, real example):**
> Deploy + paired test on /0 + new cockpit CC, verify telemetry roundtrip
> works.

Why it trapped the model: the "paired test" required the user to physically
build a cockpit CC in Minecraft and wire modems between two computers. The
model had no way to verify completion. The hook fired ~95 times.

## Failure modes this skill is preventing

### "Verification requires user observation"

If the goal says "PFD looks correct" or "feels smoother", the model can
never verify and the hook never releases. Translate to numbers:
- "feels smoother" → "draw interval p50 < 50ms in cockpit.perf.log"
- "PFD looks correct" → would be checked by user; gate explicitly with
  /notify and a manual confirmation step

### "Requires action the model can't take"

Server restart, git push, sudo command, hardware swap, third-party API
key generation — these are real, and they're legitimate parts of larger
goals. The fix is **not** to scope them out; it's to make the gate
explicit so the model handles it cleanly:

```
Requires server restart for jar swap — fractal authorization gate per
`feedback_server_restart_protocol.md`. If blocked, /notify.
```

This tells the model: when you reach the restart step, ping the user and
stop. Don't loop.

### "Open-ended quality goal"

"Make the API faster" or "improve the UX" — these have no completion
criterion. Always pin a specific metric and threshold. If the user wants
open-ended exploration, that's a conversation, not a /goal.

### "Multiple unrelated objectives"

If the goal text covers three independent features, the hook will fire
until ALL three are done. Better to set the goal for ONE objective,
complete it, then set a new /goal for the next. Goals are session-scoped
and easy to replace; don't try to make one goal carry a full sprint.

## Output format

When the user asks for /goal text, produce:

1. The **goal text itself**, formatted with clear bullet points / numbered
   patches.
2. A brief **"why this shape"** section calling out:
   - What makes it statically verifiable
   - What blocking gates are made explicit
   - What scope is intentionally excluded

3. **Stop**. Wait for the user to either run `/goal <text>` themselves or
   ask for revisions. Don't invoke /goal on their behalf — they need to
   own the install of a session-scoped hook.

## When NOT to use /goal at all

- The work is exploratory ("let's see if we can…")
- The completion criterion is taste-based and only the user can rule it
- The task has multiple independent objectives that should run sequentially
- The user just wants to iterate freely on a feature without a stop gate

In those cases, suggest the user skip /goal and just iterate with normal
conversation.

## Coordination guards for goals that drive peer agents

When a /goal coordinates long-running peer-agent work (Codex CLI,
peer Claude, etc.) — i.e. the model's job is to brief, kick off,
and verify, while the bulk of the implementation is happening in
another agent — specific failure modes recur. Bake guards against
them INTO the goal text itself, because the goal text is re-injected
every Stop-hook firing and so the guards stay in front of the model
the entire time the loop is running.

The known failure modes (each backed by a feedback memory under
`~/.claude/projects/<project>/memory/` — reference these by name in
the goal text so the model can recall and act on them):

1. **"In-flight" status spam.** When the Stop hook fires while a
   background agent is mid-task, do NOT produce a chain of single-line
   "still in flight" responses. Either (a) do real value-add work that
   doesn't race with the agent (pre-draft the next brief, audit code
   the agent has already materialized, update docs/memory), or (b)
   block on the PID via `tail --pid=PID -f /dev/null` inside a
   foreground Bash call so the turn doesn't end. See
   `feedback_blocking_wait_on_background_pid.md`. **Big asterisk:**
   blocking is the LAST resort — useful work always wins.

2. **Diff-shaped briefs muzzle peer agents.** Briefing Codex with
   "current code: X, change to: Y" or "do only these N patches,
   nothing else" wastes the engineer's code-level insight and demotes
   them from peer to hands. Brief at the INTENT level — what to
   achieve and why — and let the peer decide how. See
   `feedback_peer_briefing_intent_level.md`. The project CLAUDE.md is
   usually explicit too: "DO NOT write subagent prompts that say
   'don't touch X' or 'this is a SEPARATE follow-up task.'"

3. **Wrong Codex invocation sandboxes the agent.** Use
   `codex exec --dangerously-bypass-approvals-and-sandbox`, NOT
   `--full-auto`. The latter puts Codex in `workspace-write` sandbox
   and silently blocks writes to sibling directories or worktree
   creation — Codex's only signal is a cryptic "Read-only file
   system" error mid-flight. The `consulting-other-agents` skill
   carries the canonical invocation.

4. **Mixed-location chunks.** If a multi-chunk feature splits across
   the primary checkout + a worktree, you end up with an awkward
   deploy sequence (commit one location first, then merge the other).
   Pick the location ONCE for the whole feature, up front. See
   `feedback_worktree_consistency_across_chunks.md`.

The recommended pattern: a peer-coordinating goal includes an explicit
"🚨 Coordination guards" block near the top that names each guard and
references the relevant feedback memory. This makes the guards
operative every turn the Stop hook fires.

## Related skills

- `notify`: invoked from inside the model when a /goal is genuinely
  blocked on user action. The "If blocked, /notify" idiom routes to this.
- `consulting-other-agents`: if the goal involves a peer-review step
  (Codex / Claude / Gemini), include that explicitly in the goal so the
  model doesn't try to skip it. Also carries the canonical
  `codex exec` invocation (with the `--dangerously-bypass-approvals-and-sandbox`
  flag — see guard #3 above).
