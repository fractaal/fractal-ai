---
name: write-engineering-logs
description: >-
  INVOKE/LOAD *NEARLY ALWAYS* WHEN WORKING ON ANY NON-TRIVIAL TASK. WHY:
  Maintain a comprehensive, ongoing log in Obsidian scratchpads to preserve chat
  context, decisions, and implementation details across sessions and tools. This
  is the WRITE half — use for logging during planning, code review, debugging,
  feature work, and bugfixes. Default to the daily scratchpad
  Scratchpads/YYYY-MM-DD-topic-name.md (create if missing) via Obsidian tools.
  For READING/SEARCHING past logs, use the companion skill read-engineering-logs.
  KEYWORDS: "engineering logs", "scratchpads", "logs", "dailies", "write notes",
  "doctor's notes".
---

# Write Engineering Logs

## Overview

Write an exhaustive, living "doctor's notes" trail in Obsidian that mirrors the full conversation: issue, discussion, decisions, and implementation as it happens. This skill is write-only — it appends to scratchpads but does not search or retrieve past entries. For recall and search, see `read-engineering-logs`.

## Workflow

1. Select the target note (default daily scratchpad).
2. Append a new entry after each significant exchange or decision.
3. Append again before implementation, after implementation, after tests/reviews, and at session end.
4. If information changes, append a correction/update instead of rewriting history.
5. Write in the moment; do not batch updates for later.

## Note Selection

- Default path: `Scratchpads/YYYY-MM-DD-<optional-topic-name-here>.md` using the current local date.
- If the date is unclear, run `date +%F` to determine it.
- Create the file if missing by using `obsidian_append_content` (append creates the note).
- If the user specifies another note path, use that path instead.

## Obsidian Tooling

- Prefer `obsidian_append_content` for updates; it creates the file if missing.
- Use `obsidian_get_file_contents` only when needed to reference existing notes.

## Content Requirements (be exhaustive)

- Issue/goal being addressed.
- Key discussion points, alternatives considered, and reasoning.
- Decisions made and why.
- Implementation details: files touched, functions/classes, logic changes, API contracts, config changes.
- Commands run or intended, with outcomes.
- Tests run and results (or explicitly note if not run).
- Open questions, risks, follow-ups, and next steps.
- The "story" of your conversation, from the beginning to current.

## Style (flexible)

- Use narrative plus bullets as needed; do not omit details to "save space".
- Keep entries chronological; add timestamps if helpful.
- Mirror the conversation with factual, concrete language.
