---
name: read-agent-sessions
description: Search and read session history across all agent harnesses (Claude Code, Pi, Codex CLI). Use when continuing work from a prior session, locating a session by topic/ID/project, searching raw transcripts, or rendering readable excerpts — regardless of which harness produced the session.
---

# Read Agent Sessions

Unified search and inspection across **all** local agent session histories:
- **Claude Code** — `~/.claude/projects/` (includes session names from auto-rename)
- **Pi** — `~/.pi/agent/sessions/` (includes session names from auto-rename extension)
- **Codex CLI** — `~/.codex/sessions/` (derives name from first user message)

All commands search every harness by default. Results include a harness tag
`(Claude)`, `(Pi)`, or `(Codex)` for provenance. Use `--harness claude|pi|codex`
to narrow when needed.

## CLI

```bash
read-agent-sessions <command> [options]
```

The wrapper lives at:
```
~/.fractal-ai/skills/read-agent-sessions/scripts/read-agent-sessions
```

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

### Restrict to one harness

Any command accepts `--harness`:

```bash
read-agent-sessions recent --harness pi --limit 10
read-agent-sessions grep --harness codex "pacman"
```

## Workflow

1. `recent` to see candidates across all harnesses.
2. `find` if you know a session ID, name, project path, branch, or rough prompt.
3. `grep` for exact strings in raw transcripts.
4. `summary` on the chosen session before reading the full transcript.
5. `render` to print a readable transcript excerpt.

## Notes

- Sessions are raw JSONL transcripts, not curated summaries. Use `summary`
  before `render`.
- `grep` searches raw JSON lines — good for exact strings. `find` searches
  parsed metadata — better for session names, IDs, branches, and prompt recall.
- Claude and Pi sessions include human-assigned session names (from auto-rename).
  Codex sessions derive a name from the first user message.
- After recovering context, combine with repo state, engineering logs, and
  current git history before making decisions.
