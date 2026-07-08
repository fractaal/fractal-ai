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
| Pi | *no native MCP* | The pinned `fractaal/pi-extension` claude-mcp-bridge scans config files and unconditionally reads **`~/.claude.json`** (the surface our wiring relies on) — so the Claude Code entry above **also serves Pi**, no separate Pi config. Caveat: it scans `~/.mcp.json` *first*, then `~/.claude.json`, deduping by name with **first-match-wins**, so a stray duplicate server key in `~/.mcp.json` would silently shadow the Claude entry. We don't create `~/.mcp.json`. |
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

## Private / machine-local MCP servers

Some MCP servers can't be described in this **public** repo — e.g. internal
endpoints, or anything whose URL/auth shouldn't be world-readable. Those are
wired by a **gitignored** local layer, `deploy/install.local.sh`
(`.gitignore: deploy/install.local.sh`), which `install.sh` sources near the end
of its run. It uses the exact same inject-don't-symlink pattern as the Chrome
DevTools wiring (`claude mcp add --scope user …` for Claude/Pi, `codex mcp add …`
for Codex) and should stay idempotent.

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
> all (not even Chrome DevTools; only the Pi bridge). The PowerShell installer is
> behind the POSIX one on MCP injection generally; if Windows parity is ever
> needed, port `ensure_chrome_devtools_mcp` (and any local-layer equivalents)
> over together.
