# MCP servers

Cross-harness Model Context Protocol (MCP) server wiring for Ben's agents.

Unlike the rest of this repo, MCP servers are **not** deployed by symlink. Each
harness keeps its MCP config inside its own runtime state file (which also holds
auth, caches, and per-machine state we don't track here), so `deploy/install.sh`
**injects** the entries idempotently instead of linking a file.

## How each harness discovers MCP servers

| Harness | Config surface | Notes |
|---|---|---|
| Claude Code | `~/.claude.json` → top-level `mcpServers` | Written via the official `claude mcp add --scope user`. |
| Pi | *no native MCP* | The pinned `fractaal/pi-extension` claude-mcp-bridge scans config files and unconditionally reads **`~/.claude.json`** (the surface our wiring relies on) — so the Claude Code entry above **also serves Pi**, no separate Pi config. Caveat: it scans `~/.mcp.json` *first*, then `~/.claude.json`, deduping by name with **first-match-wins**, so a stray `serena` key in `~/.mcp.json` would silently shadow the Claude entry. We don't create `~/.mcp.json`. |
| Codex | `~/.codex/config.toml` → `[mcp_servers.<name>]` | TOML, global (not per-project). |

Because Pi piggybacks on `~/.claude.json`, a server only needs to be written in
**two** places (Claude's JSON + Codex's TOML) to reach all three harnesses.

## Serena

[Serena](https://github.com/oraios/serena) is a semantic code-retrieval/editing
MCP server (LSP-backed): `find_symbol`, `find_referencing_symbols`,
`rename_symbol`, `replace_symbol_body`, etc. — symbol-level tools instead of
line/grep surgery.

**Install** (uv-managed; puts `serena` on `PATH`, updatable with `uv tool upgrade serena-agent`):

```bash
uv tool install -p 3.13 serena-agent
```

**Per-harness launch context.** Serena ships client-specific "contexts" that
trim tools overlapping the host's own builtins. We use:

- `--context claude-code` for the Claude/Pi entry (Pi also has its own
  read/edit/grep tools, so the claude-code trim is appropriate there too).
- `--context codex` for Codex.

`--project-from-cwd` auto-activates whatever project the session is rooted in.

**`--open-web-dashboard False`** is the important one: by default Serena opens a
browser tab to its management dashboard on **every** MCP start, which is
intolerable across N sessions. This flag suppresses the auto-open while leaving
the dashboard reachable on demand at <http://localhost:24282/dashboard/> (the
dashboard is also how you kill stuck Serena instances). The same behaviour is
set globally in `~/.serena/serena_config.yml` (`web_dashboard_open_on_launch:
false`), but that file is regenerated on a fresh machine, so the per-launch flag
is the durable guarantee. To disable the dashboard server entirely, add
`--enable-web-dashboard False` (or set `web_dashboard: false` in the config).

### Live entries

Claude Code (also feeds Pi):

```bash
claude mcp add --scope user serena -- \
  "$(command -v serena)" start-mcp-server \
  --context claude-code --project-from-cwd --open-web-dashboard False
```

Codex — `~/.codex/config.toml`:

```toml
[mcp_servers.serena]
startup_timeout_sec = 60
command = "/home/benjude/.local/bin/serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex", "--open-web-dashboard", "False"]
```

`deploy/install.sh` (`ensure_serena_mcp`) installs Serena if missing and writes
both entries idempotently — re-running is safe.

### Verify

```bash
claude mcp get serena          # → Status: ✓ Connected
codex  mcp get serena          # → enabled: true
# Pi (interactive): run /mcp-status — serena should show "● serena  stdio  N tools"
```

### Optional: Serena's Claude Code hooks + system-prompt override (NOT enabled here)

Serena's docs note that recent Claude Code / Opus builds bias hard toward
builtin tools, and recommend (a) launching with
`claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"`
and (b) `serena-hooks` reminder/activate/auto-approve hooks.

These are **deliberately not applied** in this repo: the system-prompt override
*replaces* Claude Code's system prompt, and the hooks would inject into the
carefully-ordered hook stack in `claude/settings.json`. They're alpha, opinionated,
and would entangle Serena with our own harness config. If Serena tools end up
underused in practice, revisit — start with the `serena-hooks remind` PreToolUse
hook (least invasive) before touching the system prompt. See
<https://oraios.github.io/serena/02-usage/030_clients.html>.
