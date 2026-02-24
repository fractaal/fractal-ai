---
name: read-engineering-logs
description: INVOKE/LOAD WHEN THE USER ASKS TO RECALL PAST WORK, PICK UP WHERE THEY LEFT OFF, OR WHEN STARTING A SESSION ON A TOPIC THAT LIKELY HAS PRIOR LOGS. Also invoke when the user says things like "remember when we did X?", "what was the decision on...", "find my notes about...", "what happened with...", or any variation of recalling/searching past engineering context. Uses qmd (local hybrid search engine) to search Obsidian scratchpads via Bash CLI. This is the READ half — for writing new logs, use write-engineering-logs. KEYWORDS: "remember", "recall", "find notes", "prior context", "pick up where we left off", "what did we decide", "past logs", "search scratchpads".
---

# Read Engineering Logs

## Overview

Search and retrieve context from past Obsidian scratchpad entries using `qmd`, a local hybrid search engine (BM25 + vector + LLM re-ranking). This skill is read-only — it searches and synthesizes past entries but does not write new ones. For writing, see `write-engineering-logs`.

All commands run via Bash CLI, making this skill portable across any AI agent (Claude Code, Codex, OpenCode).

## Bootstrap (First Run)

Before first use, ensure `qmd` is installed and the scratchpads collection is indexed.

1. Check if `qmd` is available:
   ```bash
   which qmd
   ```
2. If not found, install via bun:
   ```bash
   bun install -g @tobilu/qmd
   ```
3. Check if the scratchpads collection exists:
   ```bash
   qmd collection list
   ```
4. If the `scratchpads` collection is not listed, create it:
   ```bash
   qmd collection add "/Users/benjude/Library/CloudStorage/Dropbox/DropsyncFiles/MindPalace/Scratchpads" --name scratchpads
   ```
5. Add context to help the search engine understand the corpus:
   ```bash
   qmd context add qmd://scratchpads "Engineering scratchpads — daily session logs containing decisions, implementation details, debugging trails, architecture discussions, and design notes from pair-programming sessions across multiple projects."
   ```
6. Run initial indexing:
   ```bash
   qmd update && qmd embed
   ```

After bootstrap, the collection persists across sessions. On subsequent runs, check `qmd collection list` and skip steps 4-6 if `scratchpads` already exists.

## Pre-Search Freshness

Before every search operation (any tier), always run:

```bash
qmd update && qmd embed
```

Both are fast no-ops when nothing has changed (~1s total). This ensures results always reflect the latest writes, including any made earlier in the current session by `write-engineering-logs`.

## Search Strategy

Choose the cheapest sufficient tier based on the query. Do not always escalate to Tier 3.

### Tier 1: Direct File Retrieval

Use when the user references a specific date, project name, or topic that maps directly to a filename.

```bash
# Get a specific file
qmd get "Scratchpads/2026-02-23-fluid-jitter-fix.md"

# Get multiple files by pattern
qmd multi-get "Scratchpads/2026-02-*-fluid*.md" --max-bytes 20480

# List files to find candidates
qmd ls scratchpads
```

**When to use**: User says "pull up last Friday's notes", "the fluid sim scratchpad", or references a known date/topic.

### Tier 2: Keyword Search (BM25)

Use for exact terms, function names, error messages, or specific identifiers. Fast, no model loading.

```bash
qmd search "SphFluidSolver pressure normalization" --md -n 10 -c scratchpads
```

**When to use**: User asks about a specific function, class, error message, or technical term.

### Tier 3: Hybrid Search (BM25 + Vector + Re-ranking)

Use for conceptual, semantic, or open-ended questions where keyword matching alone would miss relevant context.

```bash
qmd query "decision on fluid simulation architecture and jitter mitigation" --md -n 5 -c scratchpads
```

**When to use**: User asks "what was our approach to...", "remember when we discussed...", "what were the trade-offs for...", or any question requiring semantic understanding beyond exact keywords.

### Combining Tiers

For thorough recontextualization (e.g., picking up a multi-session project), combine:
1. Tier 1 to find all scratchpads for the topic by filename pattern.
2. Tier 3 to find semantically related entries that might use different naming.

## Invocation Modes

### Explicit Query (user asks directly)

When the user explicitly asks to search past logs, be verbose and transparent:

1. Run the appropriate search tier.
2. Present results with source attribution:

```
## Prior Context: <topic>

**From Scratchpads/<filename> (<date>):**
> <relevant excerpt>

**From Scratchpads/<filename> (<date>):**
> <relevant excerpt>

### Summary
<synthesized answer drawing from the retrieved entries>

### Source Files
- Scratchpads/<file1>.md
- Scratchpads/<file2>.md
```

3. If results are thin or inconclusive, say so explicitly rather than speculating.

### Silent Recontextualization (self-invoked)

When self-invoking to recontextualize at the start of a session or mid-conversation:

1. Search silently — do not narrate the search process to the user.
2. Internalize the retrieved context.
3. Weave prior context naturally into the conversation (e.g., "Based on prior session notes, we were working on X and had decided Y.").
4. Do NOT dump raw search results or say "I searched your scratchpads and found..."
5. If nothing relevant is found, proceed without comment.

## Rules

- **NEVER run multiple `qmd` commands in parallel.** Always run them sequentially (one at a time, waiting for each to finish before starting the next). Parallel `qmd` invocations saturate CPU/memory and will freeze the machine. This applies to all tiers — even if you need multiple searches (e.g., Tier 1 + Tier 3 combined), run them one after another, never concurrently.
- Never fabricate or hallucinate scratchpad content. Only surface what `qmd` actually returns.
- Always attribute excerpts to their source file and date.
- When multiple scratchpads cover the same topic across dates, present them chronologically to show how the work evolved.
- If `qmd` returns low-relevance results (scores below 0.3), note the uncertainty rather than presenting weak matches as authoritative.
- Prefer `--md` output format for clean, parseable results.
- Always scope searches to the scratchpads collection with `-c scratchpads`.
- If the user asks for something with no scratchpad trail, say so clearly and suggest starting a new log via `write-engineering-logs`.
