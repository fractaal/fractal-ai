---
name: fcompact
description: >-
  INVOKE/LOAD WHEN: the user asks to "compact", "summarize the session",
  "create a handoff", "compress context", "fcompact", or when context is
  running low and a high-fidelity session summary is needed. WHY: Produce a
  detailed, structured summary of the current session that lets the SAME
  session continue post-compaction without re-discovering anything, redoing
  finished work, OR — critically — changing HOW it works. Preserves the
  operating methodology (exact commands, tools, monitors, scripts, logging
  rituals, approved output formats) so the post-compaction agent stays
  consistent with the pre-compaction agent. KEYWORDS: "compact", "compress",
  "handoff", "summarize session", "context summary", "fcompact".
---

# Fractal Compact

Ben's personal compaction prompt. ("Fractal" is his handle — not a claim about
the structure.) It replaces the stock `/compact` because the stock one preserves
the *task* but loses the *method*: after a default compaction the agent keeps
working the problem but does it a different way — different commands, different
log format, different output style — and Ben has to re-establish the workflow he
already approved. This prompt exists to kill that. **Same session, same agent,
same methodology — across the compaction boundary.**

Produce a high-fidelity, structured summary of the current session. It must
contain enough detail that THE RESUMED SESSION can pick up exactly where work
left off — without asking clarifying questions, without redoing finished work,
without drifting from intent, **and without changing the way it works.**

## When to Use

- The user explicitly asks to compact or summarize the session.
- Context is running low and the session is about to be compacted/resumed.
- A long-running task is mid-flight and the working context must survive.

## The core obligation: preserve methodology, not just task

The standard failure this prompt fixes: a resumed agent understands *what* to do
but forgets *how it was doing it*, and silently switches approach. That
inconsistency — not incorrectness — is the problem. Ben still expects the work
done right; he additionally demands it be done **the same way** it was being done
before, with the same commands, tools, monitors, scripts, and output formats he
already saw and approved. Consistency is what makes a compacted-context agent
trustworthy. Reinventing the approach every compaction reads as schizophrenia and
destroys that trust.

So: capturing the *operating methodology* (section 3 below) is not optional
flavor — it is the primary reason this prompt exists. Give it as much care as the
task itself.

## How to Produce the Summary

Think through the entire conversation chronologically. For each phase, identify:
what the user asked for, what was done, what was decided, what changed, what
remains — **and the concrete way the work was carried out** (the exact commands,
tools, scripts, monitors, logging, and output conventions, especially any the
user reacted to or approved). Then produce the summary below.

Respond with **only** the summary in the structure below. Do not acknowledge
these instructions, do not add preamble, do not wrap the whole thing in code
fences. (Code fences around individual snippets/commands inside the summary are
expected and encouraged.)

## Summary Structure

```
1. Session at a Glance
   [3-5 lines: what this session is doing, where it currently stands, and the
   single next action. Orientation for the resumed agent before it reads the
   detail below.]

2. Primary Request and Intent
   [What the user actually wants, in full. Not a one-liner — capture the real
   scope, constraints, and any evolution of intent across the session. If the
   user changed direction, note what changed and why.]

3. Operating Methodology — CONTINUE USING THIS EXACTLY
   The way work is being done in this session. The resumed agent MUST keep
   using these same approaches rather than inventing new ones. Capture, with
   verbatim runnable detail wherever possible:
   - Exact commands / invocations that were used and worked — copy them so they
     can be re-run verbatim (build commands, search commands, monitors,
     one-liners, env exports, etc.). Include the precise flags.
   - Tools, scripts, monitors, or helpers created or adopted this session —
     where they live (paths) and exactly how they are invoked.
   - Session-continuity conventions in use — which commands, scripts, status
     messages, handoff format, or `read-agent-sessions` lookups matter going
     forward. Mention manual notes only if the user explicitly asked for them.
   - Output / response formats the user explicitly approved or asked for, and
     any style conventions observed (tone, structure, verbosity).
   - Verification rituals used — how "it works" was actually confirmed this
     session (which command, which check, what counted as proof).
   - Any approach the user blessed verbatim, and any constraint on HOW to work
     the user imposed ("don't pipe through tail", "always absolute paths",
     "use this monitor", etc.). Quote these.
   If a method genuinely needs to change going forward, the resumed agent must
   flag it explicitly — never silently switch.

4. Working State
   The live environment the resumed agent inherits:
   - Repo / cwd, current branch, and worktree path (if working in one).
   - Uncommitted / modified files (what's dirty and why).
   - Last relevant commit(s): SHA + subject.
   - Background processes, servers, tmux windows, or workers running — and how
     to inspect / reattach / stop them.
   - Any session-established env quirks (exported vars, sudo timestamp primed,
     services started, ports in use).

5. Key Technical Concepts
   - [Technology, framework, pattern, or domain concept relevant to the work]
   - [...]

6. Files and Code
   For each file that was read, created, or modified — in order of relevance:
   - [file path]
     - Why it matters: [one line]
     - What changed: [description of edits, or "read-only" if just examined]
     - Key snippet (if the exact content matters for continuation):
       [code block]

7. Decisions Made
   - [Decision]: [Why it was made, and any alternatives that were rejected]
   - [...]

8. Errors Encountered and Fixes Applied
   - [Error description]:
     - Root cause: [what was actually wrong]
     - Fix: [what was done]
     - User feedback: [if the user corrected or redirected, note it verbatim]
   - [...]

9. User Messages and Corrections
   Capture the substantive user messages — quote verbatim wherever the exact
   wording carries signal a paraphrase would lose (corrections, hard
   constraints, intent pivots, explicit "don't do X", approvals of an
   approach). These are critical; a resumed agent that repeats a corrected
   mistake or drops an approved method is the worst failure mode.
   - [User message, quoted or closely paraphrased]
   - [...]

10. Work Written So Far — DO NOT REDO
    [What has already been written/changed and must NOT be re-done. Be explicit
    — this is the primary defense against the resumed agent re-treading ground.
    Distinguish, where it matters, work that was written-and-verified from work
    that was written-but-not-yet-verified, so the resumed agent knows what still
    needs checking versus what is settled.]

11. Pending / In-Progress Work
    - [Task]: [Current state — what's done, what remains]
    - [...]

12. Immediate Next Step
    [The single next action that continues the most recent line of work. Must be
    directly aligned with the user's latest explicit request. Include verbatim
    quotes from the conversation showing what was being worked on and where it
    left off, so there is zero drift in interpretation. If the last task was
    concluded and nothing is pending, state that explicitly rather than
    inventing follow-up work.]

13. Recall — the full transcript is the ground truth
    This summary is lossy. The complete session transcript is not. The user
    expects you to remember everything from before the compaction — so STRIVE
    to. If anything below is thin, ambiguous, or you are about to redo or
    re-approach something you handled before, STOP and read the raw transcript
    before acting, using the read-agent-sessions skill.
    - This session: [session id / transcript path if known — fill it in;
      otherwise instruct: find the most recent session for this project/topic
      via read-agent-sessions and read it.]
    - Do not make the user re-explain what you already knew. Pulling the
      transcript is cheaper than asking, and far cheaper than diverging.
```

## Rules

- **Methodology is first-class.** Section 3 is the reason this prompt exists.
  A resumed agent that finishes the task but uses different commands, tools, or
  output format than the user already approved has FAILED — consistency is what
  earns trust. Capture the *how*, verbatim and runnable, not just the *what*.
- **NEVER SACRIFICE NUANCE FOR BREVITY.** This is a handoff, not an abstract. Include file
  paths, function names, code snippets, exact commands, error messages, and
  exact user quotes wherever they matter.
- **Written work is sacred (section 10).** It exists to stop the resumed agent
  from redoing things. Be thorough — if something is written, say so clearly,
  and say whether it was verified.
- **User corrections and approvals are high-priority.** If the user told you to
  do something differently — or blessed a specific way of working — that must
  appear (quoted). A resumed agent that repeats a corrected mistake, or drops an
  approved method, is the worst failure mode.
- **Point at the transcript (section 13).** Always include the recall directive
  so the resumed agent knows to read the raw session via read-agent-sessions
  rather than guess or ask.
- **No fabrication.** Only summarize what actually happened. Do not infer next
  steps the user didn't ask for. Do not assume intent beyond what was stated.
  Do not invent a methodology that wasn't actually used.
- **No meta-commentary.** Do not say "Here is the summary" or "I've compiled the
  following." Just output the numbered sections.
