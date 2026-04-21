---
name: read-claude-sessions
description: Read and recover context from local Claude Code session history stored under ~/.claude/projects. Use when continuing work that started in Claude, locating a prior Claude session by ID/topic/project, searching raw Claude transcripts, or rendering readable excerpts from session JSONL files without re-deriving the file layout and ad hoc commands each time.
---

# Read Claude Sessions

Use this skill to inspect raw Claude Code session history in `~/.claude/projects`
without having to remember the storage layout or the JSONL format.

## Workflow

1. Use `recent` to see candidate sessions.
2. Use `find` if you know a session ID prefix, project path fragment, branch, or
   rough first prompt.
3. Use `grep` if you only know raw transcript text such as `dsneo`, a file path,
   or a tool name.
4. Use `summary` on the chosen session before reading the whole transcript.
5. Use `render` to print a readable transcript excerpt when you need the actual
   flow of the conversation.

## Script

Use the helper script:

```bash
/Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py
```

It defaults to `~/.claude/projects`, skips `subagents/`, and understands both
session ID prefixes and direct file paths.

## Commands

### See recent sessions

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py recent --limit 15
```

Filter to a project bucket or cwd fragment:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py recent --project symph-aria --limit 10
```

### Find a session from partial info

By session ID prefix, slug, cwd fragment, branch, or first user prompt:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py find 9d774dcd
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py find dsneo
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py find symph-aria --limit 20
```

### Search raw transcript text

Use this when you know a literal string that appeared in the transcript:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py grep "devservers-neo"
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py grep "start_devserver_neo" --ignore-case
```

### Summarize one session

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py summary 9d774dcd
```

This prints:
- resolved file path
- start/end timestamps
- cwd, branch, slug, project bucket
- message and tool counts
- first user prompt
- last assistant text

### Render a readable transcript excerpt

Start of session:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py render 9d774dcd --limit 30
```

Tail of session:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py render 9d774dcd --tail 30
```

Include meta/system noise when needed:

```bash
python /Users/benjude/.fractal-ai/skills/read-claude-sessions/scripts/claude_sessions.py render 9d774dcd --tail 50 --include-meta --max-chars 500
```

## Notes

- Claude sessions are raw JSONL transcripts, not curated summaries. Prefer
  `summary` before `render`.
- `grep` is best for exact strings. `find` is better for session IDs, cwd
  fragments, branches, slugs, and rough prompt recall.
- If a session contains too much noise, render a smaller window with `--tail`
  first, then expand.
- After recovering context, combine the result with repo state, scratchpads, and
  current git history before making new edits.
