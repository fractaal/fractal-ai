---
name: consulting-other-agents
description: >-
  INVOKE/LOAD BEFORE asking another AI agent for an opinion, second pass, or
  cross-check — Codex CLI, a peer Claude via tmux, Gemini, sgpt, etc. Two
  failure modes this skill exists to prevent: (1) piping the agent's stdout
  through `tail`/`head` so the response never appears because buffering, and
  (2) framing the query in a way that confirms your premise instead of
  inviting disagreement. Both have caused real wasted hours.
  Keyword triggers: "ask codex", "consult codex", "second opinion", "cross-check
  with codex", "spawn a peer agent", "have gemini check", "what does codex
  think", "bring up codex", "invoke another agent".
---

# Consulting Other Agents

You are about to ask Codex, a peer Claude, Gemini, or another agent CLI for
input — a code review, a doc lookup, a cross-check on a tricky semantic, a
second opinion before shipping. This skill prevents the two specific ways you
keep wasting that consultation.

## Canonical invocations (use these verbatim — do not improvise)

These are the patterns that have actually worked in past sessions. Improvising
on flags or quoting has burned real time on this codebase. **When in doubt,
copy one of these exactly and substitute only the prompt-file path.**

### `codex exec` — Codex CLI (preferred for backend / correctness questions)

```bash
# Write your prompt to a file FIRST, then invoke.
codex exec --dangerously-bypass-approvals-and-sandbox \
  -m gpt-5.5 \
  -c model_reasoning_effort=high \
  --skip-git-repo-check \
  - < /tmp/codex-prompt.md \
  > /tmp/codex.out 2>&1
```

Non-negotiables:

- **`--dangerously-bypass-approvals-and-sandbox`**. Codex's own help text
  says this flag is "intended solely for running in environments that are
  externally sandboxed" — which is what Ben's machine is (we're the
  external sandbox). DO NOT use `--full-auto`: it puts Codex in
  `workspace-write` sandbox mode, which silently narrows the writable
  filesystem (Codex couldn't `git worktree add` to a sibling dir, couldn't
  edit `agent-worker/` while launched from the repo root, returned
  "Read-only file system" errors — *real cost paid on 2026-05-13 wiki
  semantic search work*). The trinity model treats Codex as a peer
  engineer with full repo authority; sandboxing them to a subset of the
  filesystem breaks that contract. Without the flag entirely, codex
  blocks forever on interactive approval prompts and only emits the
  cryptic `Reading additional input from stdin...`. Looks exactly like
  "still working." Is not.
- **Prompt via stdin redirect (`- < /tmp/prompt.md`)**, not as a quoted
  positional argument. Long prompts as `"$(cat …)"` are fragile under
  shell expansion (backticks, dollar signs, embedded quotes in your
  prompt all break it). The dash literal `-` tells codex "instructions
  are coming on stdin."
- **`-c model_reasoning_effort=high`** unless you have a specific reason
  to want lower effort. Codex's value is rigor; lower effort wastes the
  invocation.
- **Redirect to a file, run in background.** Codex consultations can take
  10+ minutes. Use the Bash tool's `run_in_background=true` so you get
  notified on completion. Read the file when done. NEVER pipe the live
  process through `tail`/`head`/`sed`/`awk` — those buffer until EOF.
- **DO NOT** combine multiple commands on the same line as the codex
  invocation without `&&` / `;` separators. Bash will glue them into one
  command and they will all become additional codex arguments.

If you want output to flow to a pane in real time AND land in a file, the
proven pattern is `tee` inside `tmux-workers`:

```bash
tmux send-keys -t "$PANE" \
  "codex exec --dangerously-bypass-approvals-and-sandbox -m gpt-5.5 -c model_reasoning_effort=high - < /tmp/prompt.md 2>&1 | tee /tmp/codex.out" Enter
```

### `claude -p` — peer Claude (preferred for taste / frontend / writing review)

```bash
claude -p "$(cat /tmp/prompt.md)" --dangerously-skip-permissions > /tmp/claude.out 2>&1
```

`claude -p` accepts the prompt as a positional arg cleanly because the
CLI shells out internally; `--dangerously-skip-permissions` is required
unless you've aliased it. For long sessions, prefer `tmux-workers`'
`spawn_agent.sh`.

### Resuming a Codex session

```bash
# Session IDs live in ~/.codex/sessions/YYYY/MM/DD/<uuid>.jsonl
CODEX_SESSION=$(ls -t ~/.codex/sessions/$(date +%Y/%m/%d)/ 2>/dev/null \
  | head -1 | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
codex exec resume "$CODEX_SESSION" --dangerously-bypass-approvals-and-sandbox \
  -c model_reasoning_effort=high \
  - < /tmp/followup-prompt.md \
  > /tmp/codex-followup.out 2>&1
```

## The two failure modes this skill prevents

### Failure 1 — piping agent stdout through `tail`/`head`

You think this is fine:

```bash
codex exec --model gpt-5.5 'long prompt...' 2>&1 | tail -60
```

**It is not fine.** `tail` and `head` are stream filters that buffer
their input until **EOF** before writing anything to stdout. While Codex
is still working — web-searching, calling tools, streaming reasoning — the
pipe sits at zero bytes. From the outside it looks identical to "the agent
hung." Real cost paid in this codebase: a Codex consultation ran for 30+
minutes producing 0 bytes of visible output because the upstream `tail`
never released the buffer, and the question turned out to be answered
elsewhere by the time you noticed.

The same trap fires with `head`, `awk`, and `sed` filters that read to EOF
before printing. `grep --line-buffered` is the rare exception.

**Use one of these patterns instead:**

**A) Run in background with a real output file.** Best for any agent
invocation that might take more than ~30 seconds:

```bash
# Note: Bash tool's run_in_background=true automatically writes to a file
# you can read separately. Use that. Then `cat` or `grep` the file when
# the bg job completes. NEVER pipe through tail mid-flight.
```

**B) `tee` to a file and let stdout flow.** Best when you want to see
output live AND keep a record:

```bash
codex exec --model gpt-5.5 'prompt...' 2>&1 | tee /tmp/codex-$$.out
# Read the file afterward, not the tail of the pipe
```

**C) Just don't pipe.** Codex/Claude/Gemini output is rarely so large
that you can't take it raw. If you're worried about clutter, capture to a
file and grep specific sections:

```bash
codex exec --model gpt-5.5 'prompt...' > /tmp/codex.out 2>&1
grep -A20 'Recommendation' /tmp/codex.out
```

**D) For long-running, parallel, or fully-interactive consultations**,
use the `tmux-workers` skill instead — it handles the pane lifecycle, has
a `spawn_agent.sh` helper that uses `tee` correctly, and supports
session-ID resume.

### Failure 2 — leading the witness

You think this is asking for an opinion:

> "I am building a proxy that translates Anthropic to OpenAI Responses
> format. I observe ~20% cache hit rate without `prompt_cache_key`.
> Should I set `prompt_cache_key=session_id`, or leave it unset? Be
> specific and recommend (a), (b), or (c)."

**It is not asking for an opinion. It is asking for a rubber stamp.**

The query pre-establishes:
- The problem framing ("proxy translates X to Y") — what if that's the wrong abstraction?
- The data point as valid ("~20% hit rate") — what if it's measured wrong?
- The decision space as ternary (a/b/c) — what if the right answer is "you're solving the wrong problem"?

When you consult another agent, **the entire value is that they might catch
the thing you've already convinced yourself of.** A leading question
forecloses on that value before it can fire.

Real cost paid in this codebase: a Codex consultation framed as "should
input_tokens be (full) or (full - cached) when proxying Codex usage to
Anthropic shape?" — when the actual answer to the underlying problem
("autocompact doesn't fire on Codex sessions") was **"the SDK doesn't even
read from `message_delta`, it reads from `message_start`."** Codex
couldn't have caught that with the question as asked. The framing
restricted the answer space to the wrong dimension entirely.

**Frame the query to leave room for disagreement at every level:**

- State what you're trying to **accomplish**, not what you think the
  solution is.
- Describe what you've **observed**, with caveats about what might be
  wrong with your measurements.
- Describe your **current hypothesis**, but explicitly invite challenge
  to the hypothesis, the framing, and the entire problem statement.
- Ask "what am I missing?" or "is this even the right question?" — not
  just "is (a) or (b) right?"
- If you must give multiple-choice options, **always include "the
  premise is wrong, here's why"** as an explicit possibility.

A reusable opening shape:

```
I'm trying to accomplish [outcome]. Here's what I observe in production:
[data]. Here's my current hypothesis: [hypothesis]. Here's the fix I'm
considering: [fix].

Before I ship: please challenge the framing as well as the fix. Specifically:
- Is the observed data sufficient to support the hypothesis, or am I
  measuring the wrong thing?
- Is the hypothesis the right diagnosis, or could the same symptom come
  from somewhere I haven't looked?
- Is the fix solving the right problem, or am I about to invest in the
  wrong layer?

If the premise is wrong, say so plainly. I'd rather scrap and restart
than ship a fix to the wrong thing.
```

## When to consult other agents at all

Cross-agent consultation has a real cost (tokens, latency, your attention).
Use it when:

- **You're about to ship something non-trivial** and your reasoning has
  been mostly self-generated. Same-model self-review is the weakest form
  of review.
- **You're stuck on a question with sparse documentation** — provider
  APIs, undocumented behaviors, edge cases. Codex is especially valuable
  for OpenAI-domain questions; a peer Claude is good for general
  architecture; Gemini is cheap-fast for quick second opinions.
- **You suspect you might have a blind spot** but can't identify it.
- **Your last several decisions have been based on assumption rather
  than verification.** A peer can probe the assumptions.

Skip consultation when:

- The question has a definitive doc/source answer you can read directly.
- The work is fully reversible and small (just try it).
- You've already consulted on the same question and the data hasn't
  changed.

## Strength-zone mapping

The agents Ben runs are not interchangeable. They have roughly
complementary strengths. Pick the agent whose strength zone matches the
shape of the question — not the one you happen to already be running in.

| Agent | Strong at | Weaker at |
|---|---|---|
| Codex CLI (`codex exec`) | Backend implementation, code-level correctness, mechanical rigor, standards enforcement, doc lookups (broadly — including but not limited to the OpenAI/Codex domain) | Frontend design, taste-driven UI work, conversational/social nuance, brand/voice feel |
| Claude (any model, via `claude -p` or in-session) | Frontend design, taste, system thinking, drafting communication / writing for humans, ideation, architectural sketching | Mechanical code-implementation correctness — confidently missing a subtle wiring or off-by-one is the recurring failure mode |
| Gemini (`gemini -p`) | Fast, cheap, broad second opinions | Depth on niche systems or long-context reasoning |
| sgpt | One-shot CLI scratch | Anything sustained or multi-step |

**Pairing principle:** the *strength* shape of the task picks the
*drafter*. The *opposite* shape picks the *reviewer*. So:

- Backend code drafted by Codex → reviewed by Claude only when the
  question is taste-shaped (e.g. naming, comment quality, user-facing
  copy embedded in code). For correctness review, prefer a peer Codex
  or an independent Claude with a code-review skill loaded.
- Frontend / UI / copy / conversational behavior drafted by Claude →
  reviewed by Codex only when the question is correctness-shaped (does
  this state machine cover all transitions? does this event handler
  leak?). For taste review, prefer a peer Claude or human eyes.

The *wrong* direction is the weaker agent reviewing the stronger
agent's strength zone with no shape-flip. That review will produce
plausible-sounding but unreliable feedback because the reviewer can't
actually see what they're looking at.

**Self-knowledge note for whichever agent is reading this:** before you
invoke a peer, ask "is this task in *my* strength zone or theirs?" If
it's in theirs, you are not the right drafter, and the peer call isn't a
"cross-check" — it's a redirect. Be willing to hand the work over rather
than half-do it and then ask for confirmation.

## Checklist before invoking

Before you hit Enter on a `codex exec` (or equivalent), confirm:

- [ ] **Output capture is sane.** Either `run_in_background=true` (Bash
      tool will write to a file you can read), or `tee /tmp/x.out`, or
      no pipe at all. **Never** `| tail -N` or `| head -N` mid-flight.
- [ ] **Query invites disagreement.** Includes "challenge the framing,"
      "is the premise wrong," or explicit "here's what I haven't
      verified" disclaimers. Does not bake your conclusion into the
      question.
- [ ] **You can act on either answer.** If the consultation comes back
      "you're wrong about X," do you have the time/context to redirect?
      If not, you're not really consulting — you're confirming.

If any checkbox is unchecked, fix the call before sending.
