---
name: read-agent-sessions
description: Search and read session history across all agent harnesses (Claude Code, Pi, Codex CLI). Use when continuing work from a prior session, locating a session by topic/ID/project, searching transcripts lexically (grep/find) or semantically by meaning (search), or rendering readable excerpts — regardless of which harness produced the session.
---

# Read Agent Sessions

Unified search and inspection across **all** local agent session histories:
- **Claude Code** — `~/.claude/projects/` (includes session names from auto-rename)
- **Pi** — `~/.pi/agent/sessions/` (includes session names from auto-rename extension)
- **Codex CLI** — `~/.codex/sessions/` (derives name from first user message)

All commands search every harness by default. Results include a harness tag
`(Claude)`, `(Pi)`, or `(Codex)` for provenance. Use `--harness claude|pi|codex`
to narrow when needed.

> **Lexical *and* semantic.** `grep`/`find` match exact strings and parsed
> metadata. `search` matches **meaning** — conceptual recall across every
> harness's sessions ("that time we debugged the eGPU stutter") even when you
> don't remember the words used. All three are commands of *this* skill; reach
> for whichever fits. (`search` is `qmd`-backed over the prerendered `sessions`
> corpus — see below — but you never leave this skill to use it.)

## CLI

```bash
read-agent-sessions <command> [options]
```

The wrapper lives at:
```
~/.fractal-ai/skills/read-agent-sessions/scripts/read-agent-sessions
```

## Interactive TUI (for Ben, not agents)

Everything below is also driveable by hand from a full-screen terminal UI — so
Ben never has to ask an agent "which session was that?". It's the same engine
(same providers, same summarize/render, same `qmd` semantic search), just with a
search bar, a scrollable session list, and a live transcript inspector.

```bash
read-agent-sessions tui     # subcommand on the same wrapper
sessions-tui                # standalone launcher (~/.local/bin)
```

Runs via `uv run` with `textual` declared inline (PEP 723) — no global install.
First launch indexes all sessions (~7s, streaming newest-first); subsequent
launches are instant via an mtime-keyed cache at
`~/.cache/agent-sessions-tui/index.json`.

In the TUI:
- **Type** to live-filter by metadata (name, prompt, cwd, branch, id, model).
- **`g: <term>`** + Enter → raw lexical grep across transcript JSONL (ranked by hits).
- **`s: <term>`** + Enter → semantic search via `qmd` (ranked by relevance).
- **↑/↓** browse; the right pane renders the full transcript (roles colored,
  tool calls, thinking).
- **`/`** focus search · **Tab** focus transcript · **Ctrl+H** cycle harness
  filter · **Ctrl+T** toggle thinking · **Ctrl+O** reveal file · **Ctrl+Y** copy
  session id · **Ctrl+R** rescan · **q** quit.

The TUI app lives at `tui/sessions_tui.py` next to this skill.

## Commands

### List recent sessions

```bash
read-agent-sessions recent --limit 15
read-agent-sessions recent --project symph-aria
```

### Find a session from partial info

By session ID prefix, name, cwd fragment, branch, or first user prompt:

```bash
read-agent-sessions find "deploy fix"
read-agent-sessions find 9d774dcd
read-agent-sessions find symph-aria --limit 20
```

### Search raw transcript text

```bash
read-agent-sessions grep "devservers-neo"
read-agent-sessions grep "start_devserver" --ignore-case
```

### Semantic search (meaning-based)

Conceptual recall across all harnesses' sessions — finds the right session even
when you don't remember the exact words. Backed by `qmd` over the prerendered
`sessions` corpus; the freshness pass (and `prerender`, below) are handled for
you, so this is a single self-contained command.

```bash
read-agent-sessions search "the time we fixed eGPU stutter when docked"
read-agent-sessions search "decision on zram swappiness" -n 5
read-agent-sessions search "kanshi external monitor" --prerender   # render brand-new sessions first
read-agent-sessions search "qmd indexing" --no-refresh             # skip freshness pass; query as-is
read-agent-sessions search "fluid jitter" --lean                   # 0.6B + no rerank (constrained machines)
```

By default `search` runs `qmd update`+`embed` first (fast no-ops when nothing
changed) so the index reflects already-rendered sessions. Add `--prerender` to
also render brand-new sessions on demand; pass `--no-refresh` to skip straight
to the query. Semantic search spans all harnesses — `--harness` does not apply.

### Summarize one session

```bash
read-agent-sessions summary 9d774dcd
```

Prints: path, harness, session name, timestamps, cwd, branch, message/tool
counts, first user prompt, last assistant text.

### Render a readable transcript excerpt

```bash
read-agent-sessions render 9d774dcd --limit 30
read-agent-sessions render 9d774dcd --tail 30
read-agent-sessions render 9d774dcd --tail 50 --include-meta --max-chars 500
```

### Prerender sessions for semantic search

Render every session to friendly Markdown in the Obsidian/MindPalace corpus so
`qmd` can index it. This is the **producer** step behind `search` above — it
populates the `sessions` collection that semantic search queries. It is
automated session rendering behind `read-agent-sessions`, not a separate manual
Scratchpad bookkeeping step.

```bash
read-agent-sessions prerender                 # incremental; skips already-rendered
read-agent-sessions prerender --dry-run        # show what would render, write nothing
read-agent-sessions prerender --force          # re-render everything
read-agent-sessions prerender --min-turns 3    # skip sessions with < N user turns (default 3)
```

Default output dir: `~/Dropbox/DropsyncFiles/MindPalace/Sessions` (override with
`--output`). A `prerender-sessions.sh` **Stop hook runs this automatically in the
background** after each Claude session, so the corpus stays fresh on its own; the
next `search` (or `search --prerender`) picks up anything newer. You rarely need
to run `prerender` by hand.

### Restrict to one harness

Any command accepts `--harness`:

```bash
read-agent-sessions recent --harness pi --limit 10
read-agent-sessions grep --harness codex "pacman"
```

## Workflow

1. `recent` to see candidates across all harnesses.
2. `find` if you know a session ID, name, project path, branch, or rough prompt;
   `search` if you only remember the *gist* (semantic, meaning-based).
3. `grep` for exact strings in raw transcripts.
4. `summary` on the chosen session before reading the full transcript.
5. `render` to print a readable transcript excerpt.

## Notes

- Sessions are raw JSONL transcripts, not curated summaries. Use `summary`
  before `render`.
- `grep` searches raw JSON lines — good for exact strings. `find` searches
  parsed metadata — better for session names, IDs, branches, and prompt recall.
  `search` is the semantic option — meaning-based recall when you don't have an
  exact string to match. Lexical first when you know the words; `search` when not.
- Claude and Pi sessions include human-assigned session names (from auto-rename).
  Codex sessions derive a name from the first user message.
- After recovering context, combine with repo state, project docs/instructions,
  and current git history before making decisions.
