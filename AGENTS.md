# fractal-ai (meta)

This file is for agents working **on** this repo, not the userwide instructions content
that gets distributed by it. The userwide content lives in `DEPLOYED-INSTRUCTIONS.md`.

The two slots are deliberately separate. Without this file, the userwide instructions
collapsed into both meanings and there was nowhere to put repo-specific guidance.

## What this repo is

Personal AI agent configuration shared across Claude Code, Codex, OpenCode, Gemini,
Augment, and Pi. A single source of truth, deployed via symlinks by `deploy/install.sh`.

## Layout

- `DEPLOYED-INSTRUCTIONS.md` — userwide playbook content. Distributed as `AGENTS.md` /
  `CLAUDE.md` into each tool's config dir.
- `skills/` — tool-agnostic skills. Distributed to every supported tool's `skills/`.
- `claude/` — Claude Code-only artifacts (`settings.json`, `hooks/`, `statusline-command.sh`,
  `sync-agents.sh`). Distributed only into `~/.claude/`.
- `pi/` — Pi-only artifacts (`settings.json`, `extensions/`, Pi-specific notes). Distributed
  only into `~/.pi/agent/`.
- `deploy/` — install scripts (POSIX + PowerShell).

When adding new content, decide first whether it's tool-agnostic (lives at root or under
`skills/`) or tool-specific (lives under that tool's subdir).

## Working on this repo

- **Push frequently — ideally after every coherent change.** This repo is the live
  source of truth deployed by symlink; uncommitted files and unpushed commits sitting
  here are a liability, not a staging area. Commit atomically as you finish each change
  and `git push` promptly. Do not let local work pile up — the default posture is a
  clean working tree and an in-sync `origin/main`.
- Source-of-truth files only. Generated artifacts (e.g. `~/.claude/agents/code-reviewer.md`,
  produced by `claude/sync-agents.sh`) belong on the consuming machine, not here.
- After editing source files, run `deploy/install.sh` (or `install.ps1`) to refresh
  symlinks. The script is idempotent and backs up any pre-existing real file before
  symlinking over it.
- Portable Claude settings (hooks, statusLine, theme, permissions, etc.) live in
  `claude/settings.json` and are deployed by symlink. Use `~/.claude/...` paths in command
  strings — Claude Code expands `~` at runtime, which keeps the file portable across
  machines without a render step.
- `~/.claude/settings.local.json` is **not** part of this repo. It's a per-machine,
  user-managed override file scoped by Claude Code to the cwd ancestry — i.e. it only
  loads for sessions whose cwd is under `$HOME`. Do not put portable hooks or statusLine
  there; they will silently fail for sessions started outside `$HOME` (e.g. `/opt/...`).
  Reserve it for genuinely machine-local permission allowlists and similar.
- Pi has no built-in MCP support in 0.75.1. This repo bridges normal MCP config files
  into Pi through Ben's pinned `fractaal/pi-extension` fork, which registers
  direct tools named `mcp__<server>__<tool>` without blocking Pi startup. Do not assume Claude.ai
  account-level connectors are available unless they exist as normal MCP server config.
