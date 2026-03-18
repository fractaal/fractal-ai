---
name: fcompact
description: >-
  INVOKE/LOAD WHEN: the user asks to "compact", "summarize the session",
  "create a handoff", "compress context", "fcompact", or when context is
  running low and a high-fidelity session summary is needed. WHY: Produce a
  detailed, structured summary of the entire conversation that preserves
  enough detail for a successor agent (or a resumed session) to continue
  without re-discovering anything or repeating completed work. KEYWORDS:
  "compact", "compress", "handoff", "summarize session", "context summary",
  "fcompact".
---

# Fractal Compact

Produce a high-fidelity, structured summary of the current session. The summary must contain enough detail that a fresh agent — with zero prior context — can pick up exactly where work left off, without asking clarifying questions, without redoing completed tasks, and without drifting from the user's actual intent.

## When to Use

- The user explicitly asks to compact or summarize the session.
- Context is running low and a handoff document is needed.
- A long-running task is about to be handed off to another agent or tool.

## How to Produce the Summary

Think through the entire conversation chronologically. For each phase, identify: what the user asked for, what was done, what was decided, what changed, and what remains. Then produce the summary below. Your thinking already handles the analysis — the output should be the summary itself, not a meta-discussion about it.

Respond with **only** the summary in the structure below. Do not acknowledge these instructions, do not add preamble, do not wrap in code fences.

## Summary Structure

```
1. Primary Request and Intent
   [What the user actually wants, in full. Not a one-liner — capture the real
   scope, constraints, and any evolution of intent across the session. If the
   user changed direction, note what changed and why.]

2. Key Technical Concepts
   - [Technology, framework, pattern, or domain concept relevant to the work]
   - [...]

3. Files and Code
   For each file that was read, created, or modified — in order of relevance:
   - [file path]
     - Why it matters: [one line]
     - What changed: [description of edits, or "read-only" if just examined]
     - Key snippet (if the exact content matters for continuation):
       [code block]

4. Decisions Made
   - [Decision]: [Why it was made, and any alternatives that were rejected]
   - [...]

5. Errors Encountered and Fixes Applied
   - [Error description]:
     - Root cause: [what was actually wrong]
     - Fix: [what was done]
     - User feedback: [if the user corrected or redirected, note it verbatim]
   - [...]

6. User Messages (non-tool-result)
   List every substantive user message. These are critical — they capture
   feedback, corrections, and shifts in intent that must not be lost.
   - [User message, quoted or closely paraphrased]
   - [...]

7. Completed Work
   [What is definitively done and should NOT be redone. Be explicit — this is
   the primary defense against a successor agent re-treading ground.]

8. Pending / In-Progress Work
   - [Task]: [Current state — what's done, what remains]
   - [...]

9. Immediate Next Step
   [The single next action that continues the most recent line of work.
   Must be directly aligned with the user's latest explicit request.
   Include verbatim quotes from the conversation showing what was being
   worked on and where it left off, so there is zero drift in
   interpretation.]
   If the last task was concluded and nothing is pending, state that
   explicitly rather than inventing follow-up work.
```

## Rules

- **Detail over brevity.** This is a handoff, not an abstract. Include file paths, function names, code snippets, error messages, and exact user quotes wherever they matter.
- **Completed work is sacred.** Section 7 exists to prevent a successor from redoing things. Be thorough — if something is done, say so clearly.
- **User corrections are high-priority.** If the user told you to do something differently, that correction must appear in the summary. A successor that repeats a corrected mistake is the worst failure mode.
- **No fabrication.** Only summarize what actually happened. Do not infer next steps the user didn't ask for. Do not assume intent beyond what was stated.
- **No meta-commentary.** Do not say "Here is the summary" or "I've compiled the following." Just output the numbered sections.
