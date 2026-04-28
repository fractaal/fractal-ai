# fractal-ai (meta)

This file is for agents working **on** this repo, not the userwide instructions content
that gets distributed by it. The userwide content lives in `DEPLOYED-INSTRUCTIONS.md`.

The two slots are deliberately separate. Without this file, the userwide instructions
collapsed into both meanings and there was nowhere to put repo-specific guidance.

## What this repo is

Personal AI agent configuration shared across Claude Code, Codex, OpenCode, Gemini, and
Augment. A single source of truth, deployed via symlinks by `deploy/install.sh`.

## Layout

- `DEPLOYED-INSTRUCTIONS.md` — userwide playbook content. Distributed as `AGENTS.md` /
  `CLAUDE.md` into each tool's config dir.
- `skills/` — tool-agnostic skills. Distributed to every supported tool's `skills/`.
- `claude/` — Claude Code-only artifacts (`settings.json`, `hooks/`, `statusline-command.sh`,
  `sync-agents.sh`). Distributed only into `~/.claude/`.
- `deploy/` — install scripts (POSIX + PowerShell).

When adding new content, decide first whether it's tool-agnostic (lives at root or under
`skills/`) or tool-specific (lives under that tool's subdir).

## Working on this repo

- Source-of-truth files only. Generated artifacts (e.g. `~/.claude/agents/code-reviewer.md`,
  produced by `claude/sync-agents.sh`) belong on the consuming machine, not here.
- After editing source files, run `deploy/install.sh` (or `install.ps1`) to refresh
  symlinks. The script is idempotent and backs up any pre-existing real file before
  symlinking over it.
- Machine-local Claude settings (hook commands, etc.) live in `~/.claude/settings.local.json`
  and are not part of this repo.
