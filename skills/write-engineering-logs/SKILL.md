---
name: write-engineering-logs
description: >-
  INVOKE/LOAD *NEARLY ALWAYS* WHEN WORKING ON ANY NON-TRIVIAL TASK. WHY:
  Maintain a comprehensive, ongoing log in Obsidian scratchpads to preserve chat
  context, decisions, and implementation details across sessions and tools. This
  is the WRITE half — use for logging during planning, code review, debugging,
  feature work, and bugfixes. Default to the daily scratchpad
  Scratchpads/YYYY-MM-DD-topic-name.md (create if missing) via the official
  Obsidian CLI.
  For READING/SEARCHING past logs, use the companion skill read-engineering-logs.
  KEYWORDS: "engineering logs", "scratchpads", "logs", "dailies", "write notes",
  "doctor's notes".
---

# Write Engineering Logs

## Overview

Write an exhaustive, living "doctor's notes" trail in Obsidian that mirrors the full conversation: issue, discussion, decisions, and implementation as it happens. This skill is write-only — it appends to scratchpads but does not search or retrieve past entries. For recall and search, see `read-engineering-logs`.

## Workflow

1. Select the target note (default daily scratchpad).
2. **Before every append**, get the current datetime by running `date '+%Y-%m-%d %H:%M'` and prefix the entry with a timestamp header (e.g. `### 2026-03-11 14:32`). This is mandatory — scratchpad files are often updated across multiple days, so the filename date alone is not reliable.
3. Append a new entry after each significant exchange or decision.
4. Append again before implementation, after implementation, after tests/reviews, and at session end.
5. If information changes, append a correction/update instead of rewriting history.
6. Write in the moment; do not batch updates for later.

## Note Selection

- Default path: `Scratchpads/YYYY-MM-DD-<optional-topic-name-here>.md` using the current local date.
- If the date is unclear, run `date +%F` to determine it.
- Create the file only if it is missing; do not blindly run `obsidian create` on an existing path because Obsidian may create a numbered duplicate.
- If the user specifies another note path, use that path instead.

## Obsidian CLI Tooling

Use the official `obsidian` CLI, not the Obsidian MCP tools.

1. Confirm the CLI is registered:
   ```bash
   command -v obsidian
   obsidian version
   ```
   If `obsidian` is missing, tell the user the Obsidian CLI is not registered on this machine instead of falling back to MCP.
2. Build the full timestamped entry in a shell variable or temporary file, preserving newlines:
   ```bash
   entry=$'### 2026-03-11 14:32\nSummary of what happened...\n'
   ```
3. Ensure the target scratchpad exists, then append:
   ```bash
   note="Scratchpads/2026-03-11-topic-name.md"
   folder="${note%/*}"
   if ! obsidian files folder="$folder" ext=md | grep -Fx -- "$note" >/dev/null; then
     obsidian create path="$note" content=""
   fi
   obsidian append path="$note" content="$entry"
   ```
   `obsidian append` does not reliably create missing files, but `obsidian create` may create a numbered duplicate if the file already exists. Check the file list first.
4. Read existing notes only when needed:
   ```bash
   obsidian read path="Scratchpads/2026-03-11-topic-name.md"
   ```

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
- Every entry MUST start with a `### YYYY-MM-DD HH:MM` timestamp header. No exceptions.
- Mirror the conversation with factual, concrete language.
