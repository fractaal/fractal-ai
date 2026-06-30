---
name: write-engineering-logs
description: >-
  LEGACY / EXPLICIT-REQUEST ONLY. Use only when the user specifically asks for a
  curated manual note in Obsidian/Scratchpads, or when critical context happened
  outside agent transcripts and would otherwise be lost. For normal session
  continuity and recall, rely on read-agent-sessions; do not self-invoke this as
  routine bookkeeping.
---

# Write Engineering Logs (Legacy / Explicit-Request Only)

`read-agent-sessions` is now the default durable record: agent transcripts are
prerendered as friendly Markdown into the Obsidian/MindPalace corpus and
searchable across Claude, Pi, and Codex. Do **not** maintain a parallel manual
Scratchpad log just because work is non-trivial.

Use this skill only when one of these is true:

- Ben explicitly asks you to write a curated note / scratchpad / engineering log.
- A decision or operational fact happened outside the transcript and should be
  preserved in a human-readable note.
- You are intentionally creating a compact reference artifact that is more than
  session recall.

If none of those apply, keep the relevant context in-channel, in commits, in the
North Star/plan, or in repo docs so `read-agent-sessions` can recover it later.

## Minimal workflow when explicitly requested

1. Pick the note path Ben requested, or a clearly named dated scratchpad.
2. Run `date '+%Y-%m-%d %H:%M'` and prefix the entry with that timestamp.
3. Append only the curated facts that are worth preserving: decision, rationale,
   commands/results, and any next action.
4. Do not mirror the whole conversation; the transcript already does that.
