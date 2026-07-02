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

## Chrome DevTools MCP

[Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) is
wired for browser automation/debugging across Claude Code, Pi, and Codex.

The important launch flag is **`--isolated`**. Without it, every launched Chrome
instance uses the shared default profile at
`~/.cache/chrome-devtools-mcp/chrome-profile`, so concurrent agents can collide
on cookies, storage, tabs, and Chrome's profile lock. With `--isolated`, each
MCP server process gets a temporary user-data-dir that is cleaned up when Chrome
closes.

This is intentionally process-level isolation, not just page-level
`isolatedContext`. The `new_page(..., isolatedContext=...)` tool is still useful
inside one MCP session, but a shared MCP server process has global state such as
selected page and trace state. The safe multi-agent boundary is one MCP server
process per harness/agent, each launched with `--isolated`.

### Live entries

Claude Code (also feeds Pi):

```bash
claude mcp add --scope user chrome-devtools -- \
  npx -y chrome-devtools-mcp@latest \
  --executablePath=/opt/google/chrome/google-chrome \
  --isolated
```

Codex — `~/.codex/config.toml`:

```toml
[mcp_servers.chrome-devtools]
command = "npx"
args = ["-y", "chrome-devtools-mcp@latest", "--executablePath=/opt/google/chrome/google-chrome", "--isolated"]
```

`deploy/install.sh` (`ensure_chrome_devtools_mcp`) writes both entries
idempotently, preserving any existing MCP environment map, and falls back to
omitting `--executablePath` on machines without `/opt/google/chrome/google-chrome`.

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

**`--add-mode no-memories`** drops Serena's memory layer — Ben wants only the
exploration/semantic tools. The built-in `no-memories` mode excludes
`write_memory`, `read_memory`, `list_memories`, `delete_memory`, `edit_memory`,
`rename_memory`, **and** `onboarding` (the onboarding workflow exists to create
memories), and injects a prompt telling the agent memory/onboarding aren't in
play. The semantic surface (`find_symbol`, `find_referencing_symbols`,
`rename_symbol`, `replace_symbol_body`, `get_symbols_overview`, diagnostics, …)
is untouched.

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
  --context claude-code --project-from-cwd --open-web-dashboard False --add-mode no-memories
```

Codex — `~/.codex/config.toml`:

```toml
[mcp_servers.serena]
startup_timeout_sec = 60
command = "/home/benjude/.local/bin/serena"
args = ["start-mcp-server", "--project-from-cwd", "--context=codex", "--open-web-dashboard", "False", "--add-mode", "no-memories"]
```

`deploy/install.sh` (`ensure_serena_mcp`) installs Serena if missing and writes
both entries idempotently — re-running is safe.

### Verify

```bash
claude mcp get serena          # → Status: ✓ Connected
codex  mcp get serena          # → enabled: true
# Pi (interactive): run /mcp-status — serena should show "● serena  stdio  N tools"
```

### Usage nudge: the `serena-hooks remind` hook (ENABLED, Claude Code only)

Recent Claude Code / Opus builds bias hard toward builtin tools, so Serena's
tools can sit unused. The least-invasive counter is the `remind` hook — a
PreToolUse hook (matcher `""`, so it sees every tool to track state) that nudges
the agent toward Serena's symbolic tools when it makes too many consecutive
`grep`/`read` calls without one. It's wired in `claude/settings.json`:

```json
{ "matcher": "", "hooks": [ { "type": "command",
  "command": "~/.local/bin/serena-hooks remind --client=claude-code", "timeout": 10 } ] }
```

It's non-blocking (exit 0; ~66ms/call) and only emits a reminder past a
threshold. Codex also supports it (`serena-hooks remind --client=codex` in
`~/.codex/hooks.json` + `features.codex_hooks=true`) — not wired here, since
Ben's Codex hooks aren't repo-tracked. Pi has no equivalent.

**Deliberately NOT applied:** Serena's `--system-prompt` override
(`serena prompts print-cc-system-prompt-override`) — it *replaces* Claude Code's
system prompt — and the `activate`/`cleanup`/`auto-approve` hooks. The override
is the nuclear option for tool-use bias; reach for it only if the `remind` hook
proves insufficient. See
<https://oraios.github.io/serena/02-usage/030_clients.html>.

## Private / machine-local MCP servers

Some MCP servers can't be described in this **public** repo — e.g. internal
endpoints, or anything whose URL/auth shouldn't be world-readable. Those are
wired by a **gitignored** local layer, `deploy/install.local.sh`
(`.gitignore: deploy/install.local.sh`), which `install.sh` sources near the end
of its run. It uses the exact same inject-don't-symlink pattern as Serena
(`claude mcp add --scope user …` for Claude/Pi, `codex mcp add …` for Codex) and
should stay idempotent.

Conventions for entries in that local layer:

- **Never put the secret in the entry.** Reference an env var instead — Claude
  Code expands `${VAR}` in an `Authorization` header at connect time, and Codex
  reads a token via `bearer_token_env_var`. The secret itself lives in a
  machine-local file (e.g. a shell `conf.d` export), never in any config Codex or
  Claude writes to disk.
- **Gate on the secret being present.** If the env var is unset, skip wiring
  rather than register an endpoint that can't authenticate — keeps it off
  machines that aren't entitled to it.

The contents of `install.local.sh` are intentionally not documented here; read
the file itself on a machine that has it.

> **Windows note:** `deploy/install.ps1` wires **no** cross-harness MCP server at
> all (not even Serena; only the Pi bridge). The PowerShell installer is behind
> the POSIX one on MCP injection generally; if Windows parity is ever needed,
> port `ensure_serena_mcp` (and any local-layer equivalents) over together.
