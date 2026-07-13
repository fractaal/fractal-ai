# fractal-ai

Personal AI agent configuration and skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [OpenCode](https://github.com/sst/opencode), Gemini, Augment, and [Pi](https://pi.dev).

A single `DEPLOYED-INSTRUCTIONS.md` drives shared context across all supported tools, a portable `skills/` directory provides reusable, tool-invokable capabilities that any compatible agent can pick up, `claude/` holds Claude Code-specific artifacts (settings, hooks, statusline), and `pi/` holds Pi-specific settings and extensions.

## Structure

```
.
├── DEPLOYED-INSTRUCTIONS.md    # Userwide instructions content. Deployed as AGENTS.md / CLAUDE.md
├── AGENTS.md                   # Meta: instructions for working ON this repo (not deployed)
├── skills/                     # Tool-agnostic skills, deployed to shared skill roots
├── claude/                     # Claude Code-specific
│   ├── settings.json           # All portable Claude Code settings (hooks, statusLine, perms, prefs).
│   │                           # Uses ~/... paths in command strings; Claude Code expands ~ at runtime.
│   ├── hooks/                  # PreToolUse / Stop / PostToolUse hook scripts
│   ├── statusline-command.sh   # Statusline (NASApunk ECAM display)
│   └── sync-agents.sh          # Bridges select skills into ~/.claude/agents/
├── pi/                         # Pi-specific settings and extensions
│   ├── settings.json           # Portable Pi user settings
│   └── extensions/             # Pi TypeScript extensions
├── codex/                      # Codex-specific
│   └── config.toml             # Portable Codex settings (merged into ~/.codex/config.toml, not symlinked)
├── mcp/                        # Cross-harness MCP server wiring (Chrome DevTools, Atlassian Rovo)
│   └── README.md               # MCP architecture; entries injected by install.sh, not symlinked
└── deploy/
    ├── install.sh              # Symlinks sources into tool config dirs (POSIX)
    ├── install.local.sh        # GITIGNORED machine-local/private wiring, sourced by install.sh (absent here)
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
| `skills/` | `~/.agents/skills` (shared by Codex Desktop and Pi) |
| `skills/` | `~/.opencode/skills` |
| `skills/` | `~/.claude/skills` |
| `skills/` | `~/.gemini/skills` |
| `skills/` | `~/.augment/skills` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/hooks/` | `~/.claude/hooks` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| `pi/settings.json` | `~/.pi/agent/settings.json` |
| `pi/extensions/` | `~/.pi/agent/extensions` |

`claude/settings.json` is the single source of truth for portable Claude Code config — env vars, permissions, plugins, preferences, **and** the hooks + statusLine. Command strings use `~/...` paths so the same file works on any machine without a render step (Claude Code spawns hooks with `shell:true`, and `/bin/sh` tilde-expands the leading `~` at runtime).

`pi/settings.json` is the single source of truth for portable Pi user settings, including pinned Pi packages. Pi runtime state (`auth.json`, sessions, npm/git package caches) stays under `~/.pi/agent/` and is not tracked here. Shared skills live in `~/.agents/skills`, which Codex Desktop creates/uses and Pi also scans; the installer removes legacy fractal-ai symlinks at `~/.codex/skills` and `~/.pi/agent/skills` to avoid duplicate skill entries. Pi 0.75.1 intentionally has no built-in MCP support, so this repo installs Ben's pinned `fractaal/pi-extension` fork to bridge normal MCP config files into direct Pi tools without blocking Pi startup.

`codex/config.toml` is the source of truth for portable Codex settings (model, approval/sandbox posture, `[features]`, `[notice]`, env policy). It is **merged**, not symlinked: `install.sh` (`ensure_codex_config`) overlays these keys into `~/.codex/config.toml` via `tomlkit` (needs `uv`), leaving the file's per-machine/runtime sections untouched — `[projects.*]` trust paths, `[marketplaces.*]`, `[plugins.*]`, `[hooks.state.*]`, Codex-Desktop's `node_repl`, `[tui.*]`. A symlink is wrong here because that file co-mingles portable prefs with private per-machine state (and Codex rewrites it constantly). The merge rebuilds root-scalars-before-tables so a newly added top-level key can't get reparented under a preceding table. Re-running is safe; a timestamped `.bak` is written each run.

MCP servers are **not** symlinked — each harness keeps MCP config inside a runtime state file that also holds auth and per-machine state. Instead, `install.sh` injects entries idempotently: [Chrome DevTools](https://github.com/ChromeDevTools/chrome-devtools-mcp) into `~/.claude.json` (Claude Code + Pi's bridge) and `~/.codex/config.toml`, and [Atlassian Rovo](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/using-with-other-supported-mcp-clients/) into `~/.claude.json` for Claude Code + Pi. Private/internal MCP servers (endpoints that shouldn't be world-readable in this public repo) are wired by the gitignored `deploy/install.local.sh`, which `install.sh` sources last. See `mcp/README.md` for the architecture and specifics.

`~/.claude/settings.local.json` is **not** part of this repo. It's a per-machine, user-managed override that Claude Code scopes by cwd ancestry — only sessions whose cwd is under `$HOME` see it. Reserve it for genuinely machine-local entries (e.g. distro-specific permission allowlists). Do **not** put hooks or statusLine there; sessions started outside `$HOME` (e.g. `/opt/...`) won't load them.

If a previous version of this repo's installer rendered hooks/statusLine into `~/.claude/settings.local.json`, `install.sh` will detect them and print a one-line `jq` cleanup command. Removing the stale entries is required — Claude Code merges hook arrays across precedence scopes, so leaving them causes every Stop/Edit to fire its hook twice.

The Claude statusline expects `jq` and `perl` on `PATH`, plus a Nerd Font in your terminal. `install.sh` also uses `jq` (best-effort) to detect the legacy stale-keys condition above.

## License

MIT
