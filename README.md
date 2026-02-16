# fractal-ai

Personal AI agent configuration and skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), and [OpenCode](https://github.com/sst/opencode).

A single `AGENTS.md` drives shared context across all supported tools, and a portable `skills/` directory provides reusable, tool-invokable capabilities that any compatible agent can pick up.

## Structure

```
.
├── AGENTS.md              # Shared agent instructions (context, code discipline, tool usage)
├── deploy/
│   ├── install.sh         # Symlinks AGENTS.md & skills/ into tool config dirs (POSIX)
│   └── install.ps1        # Same as above (PowerShell / Windows)
└── skills/
    ├── alignment-gate/           # Pre-implementation contract verification
    ├── generate-godot-uids/      # Godot ResourceUID generator (uid://...)
    ├── git-commit-convention/    # Atomic, typed commit workflow ([type][name] format)
    ├── godot-dotnet-build/       # Godot C# project build & verification
    └── obsidian-scratchpad-context/  # Living "doctor's notes" in Obsidian
```

## Skills

| Skill | Description |
|---|---|
| **alignment-gate** | Verify a requested change against existing system contracts and design intent before implementing. Surfaces mismatches early and proposes aligned alternatives. |
| **git-commit-convention** | Standardized atomic commit workflow. Stages intentionally, partitions by concern, and formats messages as `[type][name] details`. |
| **obsidian-scratchpad-context** | Maintains a chronological, exhaustive log in Obsidian scratchpads — decisions, implementation details, commands, and outcomes — to preserve context across sessions. |
| **godot-dotnet-build** | Runs `dotnet build` against a Godot `.csproj` to verify C# compilation after changes. |
| **generate-godot-uids** | CLI tool that generates valid Godot `uid://` strings using a CSPRNG-backed 64-bit value encoded in base36. |

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
| `AGENTS.md` | `~/.codex/AGENTS.md` |
| `AGENTS.md` | `~/.opencode/AGENTS.md` |
| `AGENTS.md` | `~/.claude/CLAUDE.md` |
| `skills/` | `~/.codex/skills` |
| `skills/` | `~/.opencode/skills` |
| `skills/` | `~/.claude/skills` |

## License

MIT
