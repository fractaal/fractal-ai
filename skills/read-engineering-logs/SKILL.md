---
name: read-engineering-logs
description: >-
  INVOKE/LOAD WHEN THE USER ASKS TO RECALL PAST WORK, PICK UP WHERE THEY LEFT
  OFF, OR WHEN STARTING A SESSION ON A TOPIC THAT LIKELY HAS PRIOR LOGS. Also
  invoke when the user says things like "remember when we did X?", "what was
  the decision on...", "find my notes about...", "what happened with...", or
  any variation of recalling/searching past engineering context. Uses qmd
  (local search engine) over Obsidian scratchpads via Bash CLI. Default is
  full semantic search via search.sh (expansion + reranking); BM25 and direct
  file retrieval remain available for exact-string and known-filename lookups.
  This is the READ half — for writing new logs, use write-engineering-logs.
  KEYWORDS: "remember", "recall", "find notes", "prior context", "pick up where
  we left off", "what did we decide", "past logs", "search scratchpads".
---

# Read Engineering Logs

## Overview

Search and retrieve context from past Obsidian scratchpad entries using `qmd`. **Default to `~/.claude/skills/read-engineering-logs/search.sh "<query>"`** — it handles freshness (update + embed) and runs full semantic search (1.7B expansion + reranking). Pass `--lean` for M1 Pro or constrained machines (0.6B Qwen3, no reranking). This skill is read-only — it searches and synthesizes past entries but does not write new ones. For writing, see `write-engineering-logs`.

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
4. If the `scratchpads` collection is not listed, create it (path varies by machine):
   ```bash
   # GPD Win Max 2 (CachyOS):
   qmd collection add "$HOME/Scratchpads" --name scratchpads
   # MacBook (M1 Pro):
   qmd collection add "$HOME/Library/CloudStorage/Dropbox/DropsyncFiles/MindPalace/Scratchpads" --name scratchpads
   ```
5. Add context to help the search engine understand the corpus:
   ```bash
   qmd context add qmd://scratchpads "Engineering scratchpads — daily session logs containing decisions, implementation details, debugging trails, architecture discussions, and design notes from pair-programming sessions across multiple projects."
   ```
6. Run initial indexing and embedding:
   ```bash
   qmd update
   qmd embed
   ```
   > First `qmd embed` is slow — it vectorizes every chunk (~0.4s/chunk on M1, faster on the GPD). Subsequent runs only embed newly-added chunks. Both commands are no-ops when nothing has changed.

After bootstrap, the collection persists across sessions. On subsequent runs, check `qmd collection list` and skip steps 4-6 if `scratchpads` already exists.

## Search Strategy

### Tier 1: Direct File Retrieval

Use when the user references a specific date, project name, or topic that maps directly to a filename.

```bash
qmd get "Scratchpads/2026-02-23-fluid-jitter-fix.md"
qmd multi-get "Scratchpads/2026-02-*-fluid*.md" --max-bytes 20480
qmd ls scratchpads
```

**When to use**: User says "pull up last Friday's notes", or references a known filename/date/topic.

### Tier 2: Full Semantic Search — **DEFAULT**

Invoke the wrapper with the query as the first argument. It handles freshness (update + embed) and runs full semantic search. Pass any extra `qmd query` flags after the query.

```bash
~/.claude/skills/read-engineering-logs/search.sh "approach to fluid jitter mitigation"
~/.claude/skills/read-engineering-logs/search.sh "memory agent session handoff" -n 10
~/.claude/skills/read-engineering-logs/search.sh "qmd architecture" --full --json
```

**When to use**: Almost always. Handles synonyms, paraphrases, conceptual queries, general recall. Handles exact-string queries too — qmd auto-detects a "strong BM25 signal" and skips LLM expansion when the keywords already hit hard.

**Expected timing on GPD Win Max 2 (Ryzen AI 9 HX 370)**:
- ≤5s — `qmd update` + `qmd embed` are clean no-ops, BM25 signal is strong, LLM expansion skipped
- ~10–20s — full expansion + reranking pass
- ~30–45s — first cold-process semantic query (model load dominates); subsequent queries much faster

**On M1 Pro or constrained machines**, pass `--lean`:
```bash
~/.claude/skills/read-engineering-logs/search.sh "approach to fluid jitter mitigation" --lean
```
This swaps to 0.6B Qwen3 expansion and disables reranking. Expect 60–90s cold, ~20s warm.

### Tier 3: BM25 Keyword Search — fast exact-match escape hatch

For mechanical lookups where semantic matching adds nothing — specific function names, exact error text, file paths, literal identifiers. Zero model loading, sub-second.

```bash
qmd search "SphFluidSolver pressure normalization" --md -n 10 -c scratchpads
qmd search "TypeError: cannot read property" --md -n 10 -c scratchpads
```

**When to use**: The query is a literal string you expect to appear verbatim in a scratchpad. Otherwise prefer Tier 2 — it handles exact strings too via BM25 fusion, just with more overhead.

### Combining Tiers

For thorough recontextualization (picking up a multi-session project), combine:
1. Tier 1 to pull all scratchpads for the topic by filename pattern.
2. Tier 2 with the project name or a conceptual query to surface entries that use different naming.

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

- **NEVER run multiple `qmd` commands in parallel.** Always run them sequentially (one at a time, waiting for each to finish). Parallel invocations multiply model loads. The serializing wrapper (`~/.fractals-toolbox/common/bin/qmd`) enforces this via lockfile, but don't rely on it — design your invocations to be sequential.
- Never fabricate or hallucinate scratchpad content. Only surface what `qmd` actually returns.
- Always attribute excerpts to their source file and date.
- When multiple scratchpads cover the same topic across dates, present them chronologically to show how the work evolved.
- If `qmd` returns low-relevance results (scores below 0.3), note the uncertainty rather than presenting weak matches as authoritative.
- When using `search.sh`, it already sets `--md` and `-c scratchpads`; don't duplicate them.
- If the user asks for something with no scratchpad trail, say so clearly and suggest starting a new log via `write-engineering-logs`.

## Advanced: Tuning and Fallbacks

### Environment variables (apply to both direct `qmd query` and `search.sh`)

- `QMD_GENERATE_MODEL` — expansion model. qmd default is 1.7B; `search.sh --lean` overrides to `Qwen3-0.6B-Q4_K_M`.
- `QMD_EMBED_MODEL` / `QMD_RERANK_MODEL` — embedder / reranker. Defaults (`embeddinggemma-300M`, `qwen3-reranker-0.6B`) are already small; rarely worth changing.
- `QMD_EXPAND_CONTEXT_SIZE` / `QMD_RERANK_CONTEXT_SIZE` / `QMD_EMBED_CONTEXT_SIZE` — context window caps.
- `QMD_LLAMA_GPU` — `metal` | `vulkan` | `cuda` | `false` | `auto` (default).

### Lean-model fallback (M1 Pro / constrained machines)

Pass `--lean` to swap to 0.6B expansion and disable reranking:
```bash
~/.claude/skills/read-engineering-logs/search.sh "<query>" --lean
```

### Embedder-only probe (cheapest semantic option)

No expansion, no reranker, no LLM load — pure vector similarity:
```bash
qmd vsearch "<query>" --md -c scratchpads -n 10
```
Useful when even `search.sh` is too slow, or for quick "is there anything on this topic" checks.
