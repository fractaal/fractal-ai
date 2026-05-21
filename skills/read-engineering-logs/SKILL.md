---
name: read-engineering-logs
description: >-
  INVOKE/LOAD WHEN THE USER ASKS TO RECALL PAST WORK, PICK UP WHERE THEY LEFT
  OFF, OR WHEN STARTING A SESSION ON A TOPIC THAT LIKELY HAS PRIOR LOGS. Also
  invoke when the user says things like "remember when we did X?", "what was
  the decision on...", "find my notes about...", "what happened with...", or
  any variation of recalling/searching past engineering context. Uses qmd
  (local search engine) over Obsidian scratchpads via Bash CLI. Default is a
  lean-model semantic query wrapped in ./search.sh; the official Obsidian CLI
  remains available for exact-string and known-filename lookups.
  This is the READ half — for writing new logs, use write-engineering-logs.
  KEYWORDS: "remember", "recall", "find notes", "prior context", "pick up where
  we left off", "what did we decide", "past logs", "search scratchpads".
---

# Read Engineering Logs

## Overview

Search and retrieve context from past Obsidian scratchpad entries using `qmd`. **Default to the wrapper script `~/.claude/skills/read-engineering-logs/search.sh "<query>"`** — it preloads a lean-model preset (0.6B Qwen3 expansion instead of qmd's 1.7B default), runs `qmd update` + `qmd embed` for freshness, and invokes `qmd query --no-rerank` for semantic retrieval. This gives high-quality semantic results without pinning the M1 Pro. This skill is read-only — it searches and synthesizes past entries but does not write new ones. For writing, see `write-engineering-logs`.

All commands run via Bash CLI, making this skill portable across any AI agent (Claude Code, Codex, OpenCode). Use the official `obsidian` CLI for known-file reads and exact text search; do not use the Obsidian MCP tools.

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
6. Run initial indexing and embedding:
   ```bash
   qmd update
   qmd embed
   ```
   > First `qmd embed` is slow — it vectorizes every chunk (~0.4s/chunk on M1). Subsequent runs only embed newly-added chunks. The wrapper calls both on every invocation; both are no-ops when nothing has changed.

After bootstrap, the collection persists across sessions. On subsequent runs, check `qmd collection list` and skip steps 4-6 if `scratchpads` already exists.

## Search Strategy

### Tier 1: Direct File Retrieval via Obsidian CLI

Use when the user references a specific date, project name, or topic that maps directly to a filename.

```bash
obsidian read path="Scratchpads/2026-02-23-fluid-jitter-fix.md"
obsidian files folder="Scratchpads" ext=md
obsidian search:context query="fluid jitter" path="Scratchpads" limit=10
```

**When to use**: User says "pull up last Friday's notes", references a known filename/date/topic, or asks for a literal phrase that should appear verbatim. Use `obsidian read` for exact files and `obsidian search:context` for exact text with surrounding line context.

### Tier 2: Lean LLM Semantic Search — **DEFAULT**

Invoke the wrapper with the query as the first argument. It handles env vars, freshness, and the right qmd flags. Pass any extra `qmd query` flags after the query.

```bash
~/.claude/skills/read-engineering-logs/search.sh "approach to fluid jitter mitigation"
~/.claude/skills/read-engineering-logs/search.sh "memory agent session handoff" -n 10
~/.claude/skills/read-engineering-logs/search.sh "qmd architecture" --full --json
```

**When to use**: Almost always. Handles synonyms, paraphrases, conceptual queries, general recall. Handles exact-string queries too — qmd auto-detects a "strong BM25 signal" and skips LLM expansion when the keywords already hit hard.

**Expected timing on M1 Pro**:
- ≤5s — `qmd update` + `qmd embed` are clean no-ops, BM25 signal is strong, LLM expansion skipped
- ~20s — LLM expansion skipped, reranking pass runs
- ~60–90s — first cold-process semantic query with expansion (model load dominates); subsequent queries in the same process are much faster

CPU stays low (~15–20%) the whole time. If you see the machine grinding, that's a different problem — report it.

### Tier 3: Exact Obsidian CLI Search — fast literal escape hatch

For mechanical lookups where semantic matching adds nothing — specific function names, exact error text, file paths, literal identifiers. Zero model loading, sub-second.

```bash
obsidian search:context query="SphFluidSolver pressure normalization" path="Scratchpads" limit=10
obsidian search:context query="TypeError: cannot read property" path="Scratchpads" limit=10 format=json
```

**When to use**: The query is a literal string you expect to appear verbatim in a scratchpad. Otherwise prefer Tier 2 — it handles exact strings too via BM25 fusion, just with more overhead.

### Combining Tiers

For thorough recontextualization (picking up a multi-session project), combine:
1. Tier 1 to pull known scratchpads or exact Obsidian search hits for the topic.
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

- **NEVER run multiple `qmd` / `search.sh` commands in parallel.** Always run them sequentially (one at a time, waiting for each to finish). Parallel invocations multiply model loads and will freeze the machine. Obsidian CLI exact searches are cheap, but when combining them with qmd, keep the qmd invocation sequential and isolated.
- Never fabricate or hallucinate scratchpad content. Only surface what `qmd` or `obsidian` actually returns.
- Always attribute excerpts to their source file and date.
- When multiple scratchpads cover the same topic across dates, present them chronologically to show how the work evolved.
- If `qmd` returns low-relevance results (scores below 0.3), note the uncertainty rather than presenting weak matches as authoritative.
- `search.sh` already sets `--md` and `-c scratchpads`; don't duplicate them.
- If `obsidian` is not on PATH, say the Obsidian CLI is unavailable/needs registration instead of falling back to the Obsidian MCP tools.
- If the user asks for something with no scratchpad trail, say so clearly and suggest starting a new log via `write-engineering-logs`.

## Advanced: Overriding the Preset

`search.sh` uses `${VAR:-default}` indirection — export any of these before calling the script to override per-invocation:

- `QMD_GENERATE_MODEL` — expansion model (default: `Qwen3-0.6B-Q4_K_M`). Swap to a different GGUF if you want even smaller / larger. Alternative constants exported from qmd's `src/llm.ts`: `LFM2_GENERATE_MODEL`, `LFM2_INSTRUCT_MODEL`.
- `QMD_EMBED_MODEL` / `QMD_RERANK_MODEL` — embedder / reranker. Defaults (`embeddinggemma-300M`, `qwen3-reranker-0.6B`) are already small; rarely worth changing.
- `QMD_EXPAND_CONTEXT_SIZE` / `QMD_RERANK_CONTEXT_SIZE` / `QMD_EMBED_CONTEXT_SIZE` — context window caps.
- `QMD_LLAMA_GPU` — `metal` | `vulkan` | `cuda` | `false` | `auto` (default).

For an even cheaper semantic probe (embedder-only — no expansion, no reranker, no LLM load), bypass the wrapper and call `qmd vsearch "<query>" --md -c scratchpads -n 10` directly. Useful when even the lean preset is still too slow on a particular box.
