---
name: read-engineering-logs
description: >-
  INVOKE/LOAD WHEN THE USER ASKS TO RECALL PAST WORK, PICK UP WHERE THEY LEFT
  OFF, OR WHEN STARTING A SESSION ON A TOPIC THAT LIKELY HAS PRIOR LOGS. Also
  invoke when the user says things like "remember when we did X?", "what was
  the decision on...", "find my notes about...", "what happened with...", or
  any variation of recalling/searching past engineering context. Uses qmd
  (local search engine, BM25 mode preferred) to search Obsidian scratchpads via Bash CLI.
  This is the READ half — for writing new logs, use write-engineering-logs.
  KEYWORDS: "remember", "recall", "find notes", "prior context", "pick up where
  we left off", "what did we decide", "past logs", "search scratchpads".
---

# Read Engineering Logs

## Overview

Search and retrieve context from past Obsidian scratchpad entries using `qmd`. **Prefer BM25 search (`qmd search`) over hybrid/vector search (`qmd query`).** The hybrid mode is too resource-heavy for the host machine. This skill is read-only — it searches and synthesizes past entries but does not write new ones. For writing, see `write-engineering-logs`.

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
   qmd update
   ```
   > Skip `qmd embed` unless you specifically need Tier 3 hybrid search (which should be rare — see Search Strategy).

After bootstrap, the collection persists across sessions. On subsequent runs, check `qmd collection list` and skip steps 4-6 if `scratchpads` already exists.

## Pre-Search Freshness

Before every search operation (any tier), always run:

```bash
qmd update
```

This is a fast no-op when nothing has changed (~1s). This ensures results always reflect the latest writes, including any made earlier in the current session by `write-engineering-logs`.

> **Note:** Do NOT run `qmd embed` routinely — embedding is only needed for vector/hybrid search (Tier 3), which should be avoided. BM25 only needs `qmd update`.

## Search Strategy

Choose the cheapest sufficient tier based on the query. **Default to Tier 2 (BM25).** Do NOT use Tier 3 (`qmd query`) unless Tier 2 has already been tried and returned nothing useful — it loads vector models and LLM re-rankers that saturate CPU/memory on this machine.

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

### Tier 2: Keyword Search (BM25) — **DEFAULT**

**This is the preferred search tier.** Use for nearly all searches — exact terms, function names, error messages, conceptual queries, and general recall. Fast, lightweight, no model loading.

```bash
qmd search "SphFluidSolver pressure normalization" --md -n 10 -c scratchpads
```

**When to use**: Almost always. This is your go-to. For conceptual queries, try rephrasing with multiple keyword variations before escalating to Tier 3. For example, for "what was our approach to fluid jitter?" try:
```bash
qmd search "fluid jitter fix approach" --md -n 10 -c scratchpads
```

### Tier 3: Hybrid Search (BM25 + Vector + Re-ranking) — **AVOID**

> **WARNING: `qmd query` is resource-heavy.** It loads vector models and LLM re-rankers that saturate CPU/memory on this machine. **Only use as a last resort** when Tier 2 has already been tried with multiple keyword variations and returned nothing useful.

```bash
qmd query "decision on fluid simulation architecture and jitter mitigation" --md -n 5 -c scratchpads
```

**When to use**: Only after Tier 2 has failed. Before using this, you must have already tried at least 2 different BM25 keyword searches. If you do use this tier, you must first run `qmd embed` (in addition to `qmd update`) to ensure vectors are fresh.

### Combining Tiers

For thorough recontextualization (e.g., picking up a multi-session project), combine:
1. Tier 1 to find all scratchpads for the topic by filename pattern.
2. Tier 2 with multiple keyword variations to catch entries that use different naming.

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
