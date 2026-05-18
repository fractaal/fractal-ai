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

## MCP status

Pi 0.75.1 does not include built-in MCP support, so MCP is provided by Ben's
forked Pi package in `pi/settings.json`:

```json
"packages": ["git:github.com/fractaal/pi-extension@async-mcp-startup"]
```

This bridge scans project/global MCP config files and registers MCP tools directly as Pi
tools named `mcp__<server>__<tool>`. It also provides `/mcp-status`.

Known scan paths include project `.mcp.json` files, `.pi/mcp.json`, and global MCP config
files such as `~/.mcp.json` / `~/.claude.json`. Keep MCP secrets in environment variables
or auth storage, not in this repo.

Claude.ai account-level connectors are not automatically exported by this repo; they must
exist as normal MCP server config for the bridge to see them.
