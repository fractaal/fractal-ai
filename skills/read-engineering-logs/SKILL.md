---
name: read-engineering-logs
description: >-
  LEGACY / BACKFILL ONLY. Prefer read-agent-sessions for recalling prior work,
  because it searches Claude, Pi, and Codex transcripts directly. Use this only
  when the user specifically asks for old Obsidian/Scratchpad notes or when you
  have reason to believe the answer predates / lives outside agent transcripts.
---

# Read Engineering Logs (Legacy / Backfill Only)

Default recall path: **use `read-agent-sessions` first.** It covers the actual
agent transcripts across harnesses and has both lexical and semantic search.

This legacy skill is only for historical curated notes that are not recoverable
from session transcripts, especially older Obsidian/Scratchpad material.

## When to use

- Ben explicitly asks for Obsidian notes, scratchpads, engineering logs, or a
  named historical note file.
- `read-agent-sessions` is thin/inconclusive and you need pre-existing curated
  notes as a backfill corpus.
- You already know the relevant artifact is a manual note rather than an agent
  session.

## How to use

Use the existing qmd/search wrapper for the historical notes corpus if available:

```bash
~/.claude/skills/read-engineering-logs/search.sh "<query>"
```

For exact filenames or literal strings, use direct `qmd` lookup/search against
the notes collection if it is configured on the machine.

## Rules

- Do not self-invoke this just because a task is non-trivial.
- Do not suggest starting a new manual log by default; rely on the transcript
  unless Ben asks for a curated note.
- Attribute any retrieved historical note clearly, and say when results are thin
  instead of filling gaps from memory.
