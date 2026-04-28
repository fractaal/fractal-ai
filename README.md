# fractal-ai

Personal AI agent configuration and skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [OpenCode](https://github.com/sst/opencode), Gemini, and Augment.

A single `DEPLOYED-INSTRUCTIONS.md` drives shared context across all supported tools, a portable `skills/` directory provides reusable, tool-invokable capabilities that any compatible agent can pick up, and a `claude/` subdirectory holds Claude Code-specific artifacts (settings, hooks, statusline) deployed only into `~/.claude/`.

## Structure

```
.
├── DEPLOYED-INSTRUCTIONS.md    # Userwide instructions content. Deployed as AGENTS.md / CLAUDE.md
├── AGENTS.md                   # Meta: instructions for working ON this repo (not deployed)
├── skills/                     # Tool-agnostic skills, deployed to every supported tool
├── claude/                     # Claude Code-specific
│   ├── settings.json           # Portable settings (no machine-specific paths)
│   ├── settings.local.json.template  # Hooks + statusLine, $HOME-rendered per machine by install.sh
│   ├── hooks/                  # PreToolUse / Stop / PostToolUse hook scripts
│   ├── statusline-command.sh   # Statusline (NASApunk ECAM display)
│   └── sync-agents.sh          # Bridges select skills into ~/.claude/agents/
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
| `DEPLOYED-INSTRUCTIONS.md` | `~/.gemini/AGENTS.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.gemini/CLAUDE.md` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.augment/AGENTS.md` |
| `skills/` | `~/.codex/skills` |
| `skills/` | `~/.opencode/skills` |
| `skills/` | `~/.claude/skills` |
| `skills/` | `~/.gemini/skills` |
| `skills/` | `~/.augment/skills` |
| `claude/settings.json` | `~/.claude/settings.json` |
| `claude/hooks/` | `~/.claude/hooks` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |

`settings.json` here is the **portable** Claude Code settings — env vars, permission rules, plugins, and preferences that work on any machine. The hook command paths and statusline command are path-coupled (they reference absolute paths), so they live in `claude/settings.local.json.template`. `install.sh` renders this template per machine — substituting `$HOME` for the actual home directory — and deep-merges into `~/.claude/settings.local.json`. Top-level keys you add manually outside the template (e.g. `permissions.allow` entries, `enabledPlugins` overrides) are preserved across re-runs. **Caveat:** the merge replaces arrays wholesale, so custom entries *inside* `hooks` or `statusLine` (the template-managed sections) get overwritten on re-render — add such entries to the template instead. install.sh backs up the prior file to `*.bak-YYYYMMDD-HHMMSS` before any rewrite; malformed existing JSON is moved to `*.bak-malformed-*` and the template is rendered fresh.

The Claude statusline expects `jq` and `perl` on `PATH`, plus a Nerd Font in your terminal. `jq` is also required by `install.sh` for the settings.local.json template merge.

## License

MIT
