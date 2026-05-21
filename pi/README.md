# Pi

Pi-specific configuration and extensions for `~/.fractal-ai`.

Deployed by `deploy/install.sh` / `install.ps1`:

| Source | Target |
|---|---|
| `pi/settings.json` | `~/.pi/agent/settings.json` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.pi/agent/AGENTS.md` |
| `skills/` | `~/.pi/agent/skills` |
| `pi/extensions/` | `~/.pi/agent/extensions` |

`auth.json`, sessions, npm/git package caches, and other mutable runtime state stay under
`~/.pi/agent/` and are not tracked here.

## Auto rename

`pi/extensions/auto-rename.ts` keeps Pi sessions and terminal/window titles named:

- Sets the terminal title to `π <session-name-or-cwd>` on session start.
- Auto-generates a 3-7 word session name after the first agent turn when the session is still unnamed/ID-like.
- Generates names from an ephemeral fork of the active branch context: Pi replays the full active branch message context with the current system prompt and active tool schema, appends a hidden "name this branch" request, reads the title, and discards that alternate timeline.
- Reconsiders the name after 50 more user turns by default (`PI_AUTO_RENAME_MIN_TURNS` overrides).
- Provides `/rename <name>` for explicit renames.
- Provides `/rename` with no args to generate an intelligent name on demand using the same ephemeral-fork path.

## MCP status

Pi 0.75.1 does not include built-in MCP support, so MCP is provided by Ben's
forked Pi package in `pi/settings.json`:

```json
"packages": ["git:github.com/fractaal/pi-extension@879cf3d9dd51f5315e98958a7d0ea55e1314da4a"]
```

This bridge scans project/global MCP config files and registers MCP tools directly as Pi
tools named `mcp__<server>__<tool>`. It also provides `/mcp-status`.

Known scan paths include project `.mcp.json` files, `.pi/mcp.json`, and global MCP config
files such as `~/.mcp.json` / `~/.claude.json`. Keep MCP secrets in environment variables
or auth storage, not in this repo.

Claude.ai account-level connectors are not automatically exported by this repo; they must
exist as normal MCP server config for the bridge to see them.
