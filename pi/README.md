# Pi

Pi-specific configuration and extensions for `~/.fractal-ai`.

Deployed by `deploy/install.sh` / `install.ps1`:

| Source | Target |
|---|---|
| `pi/settings.json` | `~/.pi/agent/settings.json` |
| `DEPLOYED-INSTRUCTIONS.md` | `~/.pi/agent/AGENTS.md` |
| `skills/` | `~/.agents/skills` (shared by Codex Desktop and Pi) |
| `pi/extensions/` | `~/.pi/agent/extensions` |
| `pi/bin/` | `~/.local/bin` |

`auth.json`, sessions, npm/git package caches, and other mutable runtime state stay under
`~/.pi/agent/` and are not tracked here. Shared skills intentionally do not live under
`~/.pi/agent/skills` anymore because Pi also scans `~/.agents/skills`; keeping both paths
produces duplicate skill entries.

## Auto rename

`pi/extensions/auto-rename.ts` keeps Pi sessions and terminal/window titles named:

- Sets the terminal title to `π <session-name-or-cwd>` on session start.
- Auto-generates a 3-7 word session name after the first agent turn when the session is still unnamed/ID-like.
- Prefixes session names with `[subagent]` when Pi starts with `PI_IS_SUBAGENT=1`, `PI_SUBAGENT=1`, `PI_SESSION_ROLE=subagent`, or `PI_SESSION_KIND=subagent`.
- Generates names from an ephemeral fork of the active branch context: Pi replays the full active branch message context with the current system prompt and active tool schema, appends a hidden "name this branch" request, reads the title, and discards that alternate timeline.
- Reconsiders the name after 50 more user turns by default (`PI_AUTO_RENAME_MIN_TURNS` overrides).
- Provides `/rename <name>` for explicit renames.
- Provides `/rename` with no args to generate an intelligent name on demand using the same ephemeral-fork path.

## Subagent launcher

`pi/bin/pi-subagent` is a tiny wrapper around `pi` that exports the subagent env
vars above before execing Pi. Use it for direct child-agent launches:

```bash
pi-subagent --name "ALR reviewer"
```

The `tmux-workers` `launch-agent.sh --cmd pi ...` helper also tags Pi children
automatically, so existing worker-launch snippets do not need to remember the env
var. Use `--no-subagent-label` only when intentionally launching a primary Pi pane
through that worker helper.

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
