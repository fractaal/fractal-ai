---
name: read-claude-sessions
description: "[DEPRECATED — use read-agent-sessions] Read and recover context from local Claude Code session history. This skill has been superseded by read-agent-sessions which searches across Claude, Pi, and Codex simultaneously."
---

# Read Claude Sessions (Deprecated)

**This skill has been replaced by `read-agent-sessions`.**

Use `read-agent-sessions` instead — it searches across Claude, Pi, and Codex
simultaneously. Same commands, same workflow, unified results.

```bash
read-agent-sessions recent --limit 15
read-agent-sessions find "some query"
read-agent-sessions grep "exact string"
read-agent-sessions summary <session-id>
read-agent-sessions render <session-id> --tail 30
```

The CLI is on PATH as `read-agent-sessions`.
