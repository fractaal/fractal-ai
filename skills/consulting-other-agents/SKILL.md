---
name: consulting-other-agents
description: >-
  INVOKE/LOAD BEFORE asking another AI agent for an opinion, second pass, or
  cross-check — Pi (GPT-5.x, preferred for backend / correctness), a peer
  Claude via tmux, Gemini, sgpt, etc. Four failure modes this skill exists
  to prevent: (1) piping the agent's stdout through `tail`/`head` so the
  response never appears because buffering, (2) framing the query in a way
  that confirms your premise instead of inviting disagreement, (3) briefing
  the peer at the diff/line level so it just executes your pre-decided
  solution instead of applying its own judgment, and (4) — as the agent
  being briefed — taking the briefer's claims about the codebase as fact
  instead of verifying them. Each one wastes the consultation.
  Keyword triggers: "ask pi", "consult pi", "second opinion", "cross-check",
  "spawn a peer agent", "have gemini check", "what does pi think",
  "invoke another agent".
---

# Consulting Other Agents

You are about to ask Pi, a peer Claude, Gemini, or another agent CLI for
input — a code review, a doc lookup, a cross-check on a tricky semantic, a
second opinion before shipping. This skill prevents the specific ways you
keep wasting that consultation.

## Canonical invocations (use these verbatim — do not improvise)

These are the patterns that have actually worked in past sessions. Improvising
on flags or quoting has burned real time on this codebase. **When in doubt,
copy one of these exactly and substitute only the prompt-file path.**

### `pi` — Pi CLI (GPT-5.x; THE default for backend / correctness consultations)

Pi runs GPT-5.5 and is the go-to for backend, correctness, and code-review consultations. **Always use Pi over Codex** — they're the same model family, but Pi is more reliable in practice (reads shared instruction files, no auth flakiness, better interactive workflow).

Pi is interactive REPL only — no headless `pi exec`. Drive it via the `tmux-workers` skill (load that before invoking):

```bash
PANE=$(~/.claude/skills/tmux-workers/scripts/launch-agent.sh --cmd pi \
  --dir <workdir> --name pi-<task>)
~/.claude/skills/tmux-workers/scripts/send-keys-then-enter.sh "$PANE" \
  'Read /tmp/<brief>.md in full and report back.'
# Block via Monitor tool (Claude Code) — never inline wait-for.sh, it burns
# your context. Capture the pane scrollback when Pi goes idle.
```

Same brief discipline applies as for all agents — brief in a file (send-keys submits on first newline), intent-level not diff-level, no leading questions, mark codebase claims as beliefs not facts. The four failure modes below apply identically to Pi.

### `codex exec` — Codex CLI (DEPRECATED — use Pi instead)

> **Don't bother with Codex.** Pi and Codex are both GPT-5.x — same model family, same strengths. Pi is strictly better in this environment: it reads shared instruction files, has no auth issues, and works interactively via tmux. The section below is kept only as reference if Pi is somehow unavailable.

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
  "Read-only file system" errors). The trinity model treats Codex as a peer
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
unless you've aliased it. For a sustained peer — many briefs across one
session — run it interactively via the `tmux-workers` skill rather than
repeated one-shots.

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

## The failure modes this skill prevents

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
use the `tmux-workers` skill instead — it handles the full interactive
pane lifecycle: launch the agent CLI, brief it, block until it goes idle,
read it back, and steer it mid-task.

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

**This is not only about big "(a)/(b)/(c)" decisions — it bites hardest on
small factual questions, where it is easiest to miss.** A specific
*question* is fine — "what does the perm path do in prod? trace it"; the
agent still has to go find out, you don't know the answer. A specific
*answer*, handed back as a menu, is leading — the real slip from this very
codebase: "did the real Discord permission check actually run in prod, OR
has `channelAuthorized` only ever defaulted to true?" The "OR … defaulted
true" is *your hypothesis* — smuggled in as one of two options, and if
reality is a third thing the agent is primed straight past it.

**The rule: if your hypothesis is in the question, you crossed the line. If
only the thing-to-find-out is in the question, you didn't.** A question the
agent answers by *producing the actual content* is open; one it answers
"yes, confirmed / no" is you outsourcing a verdict on analysis you already
did. The far end: "does `X` flip to 6 under `os.time() % 231.21`?"
— you have done 100% of the analysis; the agent is now a calculator for your
theory, zero judgement added.

If there is a real subtlety the agent would be fooled by without it — e.g.
"a log line `channel_authorized: true` can mean *defaulted on a web
channel*, not *checked*" — give it as **context** ("here is how the code
works"), which arms the agent, never as **the question** ("is it the
defaulted case?"), which leads it. Same fact: context arms, question-shape
leads.

And watch the **compression step**: a clean, open brief still gets squashed
into a leading one-liner when you summarise it for the actual send. The
one-liner is where the leading sneaks back in. Check it there too.

### Failure 3 — muzzling the peer

You think this is a thorough, helpful brief:

> "Patch the embeddings module. Do ONLY these 4 things, nothing else:
> (1) set `autoTruncate=false` in the request body, (2) accept both
> `token_count` and `tokenCount` in the response, (3) assert the vector
> length matches the configured dimension, (4) return a 400 (not a 500)
> on a non-dict request body. Each covered by a new test."

**It is not a brief. It is you writing the code and using the peer as a
typist.**

A diff-shaped brief — exact strings, full signatures, "change line X to
Y", "do ONLY these N things", "don't touch Z", "that's a separate task"
— strips the peer of the one thing you invoked them for: code-level
judgment you do not have. A peer handed "(1) set `autoTruncate=false`"
cannot tell you `autoTruncate` might belong as a caller-supplied
parameter, cannot spot the fifth bug sitting next to your four, cannot
flag an integration change you never thought to ask for. You pre-decided
the decomposition; all the peer can do is type it — and then the
consultation is worth nothing, because you would have gotten the same
result writing it yourself.

This is easy to miss because a brief feels *most* thorough exactly when
it is *most* over-specified: four precise patches read as diligence.
They are the opposite — they are you doing the engineer's thinking and
leaving them no room to do it better, or to tell you that you are wrong.

**Brief at intent, not diff.** State what to achieve and why; let the
peer decide how. Before sending, scan the brief and rewrite or delete
every line that matches the left column:

| ❌ Muzzle — rewrite it or cut it | ✅ Intent — what a brief should be |
|---|---|
| "Change line 292 to `raise HTTPException(400, …)`" | "A non-dict request body should fail loud as a 400, not crash into a 500." |
| Exact `old_string` → `new_string` diff blocks | "The API truncates oversized input silently by default — wrong for an indexer. Address it." |
| Full method signatures with type hints | "Match the lifecycle pattern already in `src/main.py`." |
| "Do ONLY these N things, nothing else" | "Here is the full picture, and the parts I think matter most — your call on the rest." |
| "Don't touch X" / "X is a separate task" | *(delete it — give the full context and let the peer flag what actually connects)* |
| Test-by-test "add a test that asserts X" | "This needs test coverage; you decide which cases matter." |

Constraints, intent, and pointers to existing patterns — yes, always.
Implementation choices belong to the engineer. If a particular shape is
genuinely load-bearing, pseudocode the *flow*, not the *signatures*, and
say why it has to be that way.

A leading question (Failure 2) forecloses the peer's *answer*; a muzzling
brief forecloses the peer's *work*. Same skill, same waste — the
consultation thrown away before it can fire.

### Failure 4 — inheriting the briefer's unverified claims

The first three failures are about the agent *doing* the consulting. This
one is about the agent *being* consulted — and the claims a brief smuggles
in.

A brief is never just a task. It carries the briefer's **beliefs about the
codebase**: "the ingress is the web adapter," "X is handled in `foo.ts`,"
"the only caller is `Y`," "that type already has the field." Those beliefs
are not facts. The briefer is a peer who can be wrong — that is the entire
reason you were consulted.

You think a brief like this hands you solid ground to build on:

> "aria-chat's web messages come in through the gateway's `/v1/chat`
> adapter — add the `//` handling there."

It does not. That sentence is a *hypothesis*. If it is wrong — if aria-chat
actually writes the database directly and never touches that adapter — then
every line you write on top of it is wrong, and **you will not find out**,
because the brief told you where to look and you looked only there.

Real cost paid in this codebase: a brief asserted aria-chat's message
ingress flowed through the gateway. It did not — aria-chat's server wrote
Firestore directly, bypassing the gateway entirely. The consulted agent
took the claim on faith, scoped its work to the gateway paths, and the
direct-write path was never examined. A feature shipped with a hole in it;
the bug then cost a second round of investigation and a second agent to
fix. One unverified sentence, inherited whole.

**Treat every codebase claim in a brief as a lead, not a fact.** Before you
build on "X is in `Y`" / "the flow goes through `Z`" / "the only caller is
`W`":

- **Verify the load-bearing ones yourself** — `grep`, read the file,
  confirm. The claims your work *depends on* get checked; incidental ones
  can slide.
- **"It's in this file, trust me" earns *more* scrutiny, not less.** A
  confident pointer is still a peer who might be wrong; confidence is not
  evidence. The more a claim would cost if wrong, the harder you check it.
- **If the code contradicts the brief, the code wins.** Say so plainly,
  back to the briefer. Catching exactly this is why you were consulted —
  inheriting their map defeats the point.

And the symmetric duty when **you write the brief**: mark codebase claims
as beliefs, not facts. "I *think* the ingress is the web adapter — verify"
tells the recipient what to check. "The ingress is the web adapter"
launders an assumption into a fact and propagates your blind spot straight
into their work.

**The same trap, as a question.** A brief also smuggles beliefs in as
*leading questions* — "is it A or B?" where A and B are the briefer's two
hypotheses. Answer the question they *should* have asked, not the one they
did: go find what the thing actually is, even when all you were handed was
their two-item menu. If the real answer is "neither — it's C," that is the
answer — and C is exactly what the leading question was shaped to hide. The
menu is a lead, not a fence.

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
| Pi (interactive via `tmux-workers`) | Backend implementation, code-level correctness, mechanical rigor, standards enforcement. GPT-5.x. **The default for all non-Claude consultations** | Frontend design, taste-driven UI work, conversational/social nuance, brand/voice feel |
| Claude (any model, via `claude -p` or in-session) | Frontend design, taste, system thinking, drafting communication / writing for humans, ideation, architectural sketching | Mechanical code-implementation correctness — confidently missing a subtle wiring or off-by-one is the recurring failure mode |
| Gemini (`gemini -p`) | Fast, cheap, broad second opinions | Depth on niche systems or long-context reasoning |
| sgpt | One-shot CLI scratch | Anything sustained or multi-step |

**Pairing principle:** the *strength* shape of the task picks the
*drafter*. The *opposite* shape picks the *reviewer*. So:

- Backend code drafted by Pi → reviewed by Claude only when the question
  is taste-shaped (e.g. naming, comment quality, user-facing copy embedded
  in code). For correctness review, prefer a peer Pi. An independent Claude
  with a code-review skill loaded is a distant second — use it only when Pi
  is unavailable.
- Frontend / UI / copy / conversational behavior drafted by Claude →
  reviewed by Pi when the question is correctness-shaped (does this state
  machine cover all transitions? does this event handler leak?). For taste
  review, prefer a peer Claude or human eyes.

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

Before you launch a Pi worker, invoke `claude -p`, or any equivalent, confirm:

- [ ] **Output capture is sane.** Either `run_in_background=true` (Bash
      tool will write to a file you can read), or `tee /tmp/x.out`, or
      no pipe at all. **Never** `| tail -N` or `| head -N` mid-flight.
- [ ] **Query invites disagreement.** Includes "challenge the framing,"
      "is the premise wrong," or explicit "here's what I haven't
      verified" disclaimers. Does not bake your conclusion into the
      question.
- [ ] **The brief is intent-level, not diff-level.** Scan it for exact
      strings, full signatures, `old_string`→`new_string` blocks, "do
      only these N things", "don't touch X", "separate task". Every
      match → rewrite at intent level or delete. (See Failure 3.)
- [ ] **You can act on either answer.** If the consultation comes back
      "you're wrong about X," do you have the time/context to redirect?
      If not, you're not really consulting — you're confirming.
- [ ] **Codebase claims are marked as beliefs, not facts.** Any "X is in
      `Y`" / "the flow goes through `Z`" / "the only caller is `W`" in the
      brief is flagged as *to be verified*, so the peer knows to check it
      rather than inherit it. (See Failure 4.)

If any checkbox is unchecked, fix the call before sending.
