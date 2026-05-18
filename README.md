# fractal-ai

Personal AI agent configuration and skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [OpenCode](https://github.com/sst/opencode), Gemini, Augment, and [Pi](https://pi.dev).

A single `DEPLOYED-INSTRUCTIONS.md` drives shared context across all supported tools, a portable `skills/` directory provides reusable, tool-invokable capabilities that any compatible agent can pick up, `claude/` holds Claude Code-specific artifacts (settings, hooks, statusline), and `pi/` holds Pi-specific settings and extensions.

## Structure

```
.
├── DEPLOYED-INSTRUCTIONS.md    # Userwide instructions content. Deployed as AGENTS.md / CLAUDE.md
├── AGENTS.md                   # Meta: instructions for working ON this repo (not deployed)
├── skills/                     # Tool-agnostic skills, deployed to every supported tool
├── claude/                     # Claude Code-specific
│   ├── settings.json           # All portable Claude Code settings (hooks, statusLine, perms, prefs).
│   │                           # Uses ~/... paths in command strings; Claude Code expands ~ at runtime.
│   ├── hooks/                  # PreToolUse / Stop / PostToolUse hook scripts
│   ├── statusline-command.sh   # Statusline (NASApunk ECAM display)
│   └── sync-agents.sh          # Bridges select skills into ~/.claude/agents/
├── pi/                         # Pi-specific settings and extensions
│   ├── settings.json           # Portable Pi user settings
│   └── extensions/             # Pi TypeScript extensions
└── deploy/
    ├── install.sh              # Symlinks sources into tool config dirs (POSIX)
    └── install.ps1             # Same on PowerShell / Windows
```

### DEPLOYED-INSTRUCTIONS.md vs AGENTS.md

These are two intentionally separate slots:

- `DEPLOYED-INSTRUCTIONS.md` is the userwide content that gets distributed under the names `AGENTS.md` / `CLAUDE.md` in every tool's config directory.
- `AGENTS.md` (this repo's own) is meta — it tells agents how to work **on** this repo. It is NOT distributed.

Without the rename, both slots collapsed onto one filename and there was no place to keep repo-specific guidance.

## Setup

Clone this repo to `~/.fractal-ai` (or set `FRACTAL_AI_HOME` to your preferred location), then run the install script to symlink into supported tools:

```bash
git clone https://github.com/fractaal/fractal-ai.git ~/.fractal-ai
~/.fractal-ai/deploy/install.sh
```

On Windows (PowerShell — requires Developer Mode or admin):

```powershell
git clone https://github.com/fractaal/fractal-ai.git "$HOME\.fractal-ai"
& "$HOME\.fractal-ai\deploy\install.ps1"
```

The install scripts symlink into the following locations, backing up any existing files first:

| Source | Target |
|---|---|
| `DEPLOYED-INSTRUCTIONS.md` | `~/.codex/AGENTS.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.opencode/AGENTS.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.claude/CLAUDE.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.pi/agent/AGENTS.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.gemini/AGENTS.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.gemini/CLAUDE.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.augment/AGENTS.md` |
| `skills/` | `~/.codex/skills` |
| `skills/` | `~/.opencode/skills` |
| `skills/` | `~/.claude/skills` |
| `skills/` | `~/.pi/agent/skills` |
| `skills/` | `~/.gemini/skills` |
| `skills/` | `~/.augment/skills` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/hooks/` | `~/.claude/hooks` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `pi/settings.json` | `~/.pi/agent/settings.json` |
| `pi/extensions/` | `~/.pi/agent/extensions` |

`claude/settings.json` is the single source of truth for portable Claude Code config — env vars, permissions, plugins, preferences, **and** the hooks + statusLine. Command strings use `~/...` paths so the same file works on any machine without a render step (Claude Code spawns hooks with `shell:true`, and `/bin/sh` tilde-expands the leading `~` at runtime).

`pi/settings.json` is the single source of truth for portable Pi user settings, including pinned Pi packages. Pi runtime state (`auth.json`, sessions, npm/git package caches) stays under `~/.pi/agent/` and is not tracked here. Pi 0.75.1 intentionally has no built-in MCP support, so this repo installs Ben's `fractaal/pi-extension@async-mcp-startup` fork to bridge normal MCP config files into direct Pi tools without blocking Pi startup.

`~/.claude/settings.local.json` is **not** part of this repo. It's a per-machine, user-managed override that Claude Code scopes by cwd ancestry — only sessions whose cwd is under `$HOME` see it. Reserve it for genuinely machine-local entries (e.g. distro-specific permission allowlists). Do **not** put hooks or statusLine there; sessions started outside `$HOME` (e.g. `/opt/...`) won't load them.

If a previous version of this repo's installer rendered hooks/statusLine into `~/.claude/settings.local.json`, `install.sh` will detect them and print a one-line `jq` cleanup command. Removing the stale entries is required — Claude Code merges hook arrays across precedence scopes, so leaving them causes every Stop/Edit to fire its hook twice.

The Claude statusline expects `jq` and `perl` on `PATH`, plus a Nerd Font in your terminal. `install.sh` also uses `jq` (best-effort) to detect the legacy stale-keys condition above.

## License

MIT
