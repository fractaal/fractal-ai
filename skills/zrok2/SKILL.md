---
name: zrok2
description: >-
  Manage zrok2 tunnels and public URLs. Use when the user asks to expose a local
  port, spin up a public URL, create a named tunnel, share a service, tear down
  a share, check tunnel status, or anything involving zrok/zrok2. Keyword
  triggers: "zrok", "tunnel", "expose", "share publicly", "public URL",
  "spin up a URL", "tear down", "zrok status".
---

# zrok2 -- Tunnel & Share Management

Manage the full lifecycle of zrok2 shares: create named URLs, expose local services,
list active tunnels, and tear down resources.

**Binary location**: `~/.local/bin/zrok2` (user install) or `/usr/local/bin/zrok2` (system install).
Probe both if in doubt.

**URL domain**: public zrok2 shares resolve under `https://<name>.shares.zrok.io` — **plural `shares`**, not `share`. v1 used singular `share.zrok.io`; v2 changed this. When rewriting old configs, look for `.share.zrok.io` and replace with `.shares.zrok.io`.

## Prerequisites

The environment must be enabled before any share operations work. Check with:

```bash
zrok2 status
```

If not enabled, the user needs their account token from [myzrok.io](https://myzrok.io):

```bash
zrok2 enable <accountToken> --headless
```

**Always verify environment status before attempting share operations.**

## Core Workflows

### 1. Spin Up a Named Public URL

This is the most common request. The user says something like "expose port 3000 as myapp"
or "spin up a zrok URL called blingblong".

**Steps:**

1. Check if the name already exists:
   ```bash
   zrok2 list names 2>/dev/null | grep -i "<name>"
   ```

2. Create the name if it doesn't exist:
   ```bash
   zrok2 create name <name>
   ```

3. Start the share:
   ```bash
   zrok2 share public <target> -n public:<name> --headless
   ```
   - Default target is `localhost:PORT`. Ask the user what port if not specified.
   - Use `--headless` always (TUI doesn't work in non-interactive contexts).
   - The resulting URL will be `https://<name>.shares.zrok.io`.

4. Report the URL back: `https://<name>.shares.zrok.io`

**Two runtime modes for the share command** (this is the single most important thing to understand):

- **Local mode (no agent running)**: `zrok2 share public` is the *tunnel carrier*. It runs in the foreground and blocks as long as the tunnel is alive. Killing the process drops the tunnel. Run it with `run_in_background: true` on the Bash tool call, and warn the user that closing the terminal kills the tunnel.
- **Agent mode (zrok2 agent daemon is running)**: `zrok2 share public` *registers* the share with the agent and **exits in under 1 second**. The agent becomes the tunnel carrier. The share process is gone but the tunnel is alive. This is the right pattern for persistent shares — see Workflow 6.

Detect which mode applies with `zrok2 agent status` — if it returns share info, the agent is running and any new `share public` call will hand off to it.

### 2. Quick Ephemeral Share (No Name)

When the user just wants a throwaway URL without a persistent name:

```bash
zrok2 share public localhost:<port> --headless
```

The URL will be random. Parse it from the output and report it. Same local-vs-agent
runtime modes as Workflow 1 apply.

### 3. Tear Down a Share

The user says "tear down", "stop the tunnel", "kill the zrok share", etc.

**If the share is agent-managed** (most likely if it's been persistent or the user uses
agent mode), use the agent release command — this is the *only* command that cleanly
removes the share from the agent's in-memory registry:

```bash
zrok2 agent release share <shareToken>
```

Do NOT use `zrok2 delete share <token>` for agent-managed shares. `delete share` removes
the backend record but the agent's local view becomes stale ("3 active" when the backend
has zero), and subsequent operations will see contradictory state.

**If the share is local-mode** (no agent involved), use delete share and kill the process:

```bash
zrok2 list shares
zrok2 delete share <shareToken>
pkill -f "zrok2 share.*<name>"   # if process still running
```

**Optionally delete the reserved name too** (ask — they may want to reuse it):

```bash
zrok2 delete name <name>
```

Note: `delete name` fails if the name is still attached to an active share. Release/delete
the share first, then delete the name.

### 4. Check Status / List Everything

```bash
# Environment status (is the current env enabled?)
zrok2 status

# All shares visible to this env (across all local users on this account)
zrok2 list shares

# All reserved names (account-wide)
zrok2 list names

# Shares currently being held open by the local agent daemon (if running)
zrok2 agent status
```

`list shares` and `agent status` can show *different* sets when state has drifted. The
reconciliation command is `agent release share <token>` for anything the agent holds
that shouldn't be held.

### 5. Private Shares (TCP/UDP Tunnels, Internal Services)

For sharing services only accessible to other zrok users (not public web):

```bash
# Share privately with a persistent token
zrok2 share private localhost:<port> --share-token <name> --headless

# TCP tunnel (e.g., database)
zrok2 share private localhost:5432 -b tcpTunnel --share-token my-db --headless

# Consumer side (whoever needs to access it)
zrok2 access private <shareToken> -b 127.0.0.1:<localPort>
```

### 6. Agent Mode (Persistent Shares That Survive Restarts)

**This is the canonical approach for any share that needs to outlive the process
that created it** — always-on tunnels, systemd-managed services, anything where a
service restart shouldn't drop the public URL. It's also the v2 equivalent of v1's
`zrok reserve public` + `zrok share reserved` reconnection semantics.

**How the agent actually works** (reverse-engineered; confirmed via
[`cmd/zrok2/util.go`](https://github.com/openziti/zrok/blob/main/cmd/zrok2/util.go)
`detectAndRouteToAgent` and the
[agent concept doc](https://github.com/openziti/zrok/blob/main/website/docs/concepts/agent.md)):

1. The `zrok2 agent start` daemon listens on a unix socket at `~/.zrok2/agent.socket`.
2. When you run `zrok2 share public ... -n public:NAME --headless` and the agent is
   running, the share command calls `shareAgent` (RPC to the daemon) instead of
   `shareLocal`. It sends the share parameters, gets back the share token, **and
   exits** — typical runtime under 1 second.
3. The agent then holds the tunnel open. The CLI was purely a registrar; the agent
   is the tunnel carrier.
4. **Named shares are automatically restarted by the agent itself** if the agent
   restarts (per the agent concept doc). Ephemeral shares are not — they die with
   the agent session.
5. Re-running `zrok2 share public -n public:SAMENAME` after the agent has adopted
   the name returns a **409 Conflict on stderr but exits 0** (not 1). Treat this as
   idempotent registration. Do not retry-loop on it.

**Setup pattern (systemd, Linux/WSL):**

```ini
# /etc/systemd/system/zrok2-agent.service
[Unit]
Description=zrok2 agent daemon (persists shares across client restarts)
After=network.target

[Service]
Type=simple
Environment=HOME=/root
ExecStart=/usr/local/bin/zrok2 agent start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

**Critical: `Environment=HOME=/root` is required** when running the agent under
systemd without a `User=` directive. Without it, zrok2 errors
`neither $XDG_CONFIG_HOME nor $HOME are defined` and can't find its config at
`~/.zrok2/`. Same caveat applies to any systemd unit that spawns `zrok2 share public`.

**Share registration patterns once the agent is up:**

Option A — `Type=oneshot` systemd unit per share (cleanest, no tmux needed):

```ini
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=HOME=/root
ExecStart=/usr/local/bin/zrok2 share public localhost:8080 -n public:myapp --headless --force-agent
# Note: --force-agent makes this fail loudly if the agent daemon is down,
# instead of silently falling through to local mode (which would be a
# non-persistent tunnel — not what you want in a systemd unit).
```

The unit runs `share public` once, which exits 0 after handing off to the agent. With
`RemainAfterExit=yes`, systemd considers the unit active afterward. On a reboot, the
agent's own auto-restart logic brings the share back; re-running this unit is harmless
(409 + exit 0).

Option B — tmux pane with `sleep infinity` (for operational dashboards where you
want a visible "registered" pane next to your service's log pane):

```bash
# Inside a tmux pane command
zrok2 share public localhost:8080 -n public:myapp --headless --force-agent 2>&1
echo "handoff complete; agent manages the share. Idling..."
sleep infinity
```

The `sleep infinity` has zero functional role — the tunnel is already the agent's
responsibility at that point. It exists only to keep the tmux pane alive for
visibility. If you don't need the pane, use Option A.

**What NOT to do in agent mode:**

- ❌ Do NOT wrap `zrok2 share public` in a `while true; do ...; done` retry loop.
  After the first successful run, the share is adopted; every subsequent iteration
  hits 409 and becomes pointless noise. If the first run fails for a real reason
  (agent dead, network error), you want that visible — not hidden in a hot loop.
- ❌ Do NOT use `--subordinate`. It looks like it enables agent mode but it's
  actually the internal IPC protocol the *agent* uses when it forks a child
  `zrok2 share public` process. It emits newline-delimited JSON status on stdout
  for the parent to ingest. Not for human/script use.
- ❌ Do NOT edit `~/.zrok2/agent-registry.json` by hand. It's an internal cache,
  not a user-authored config. There is no documented `zrok2 agent import` / `add share`
  command — the canonical "register a share" primitive is `zrok2 share public`
  against a running agent.
- ❌ Do NOT use `zrok2 delete share <token>` on shares the agent is holding. It
  removes the backend record but leaves the agent's local view stale. Use
  `zrok2 agent release share <token>` instead.

**Check agent state:**

```bash
zrok2 agent status                 # what's being held open right now
systemctl status zrok2-agent       # is the daemon healthy?
journalctl -u zrok2-agent -n 50    # recent agent log lines
ls ~/.zrok2/                       # agent.socket, agent-registry.json
```

**When state drifts (you see contradictions between `list shares` and `agent status`):**

1. `zrok2 agent release share <token>` for each stale token in `agent status`
2. `zrok2 delete share <token>` for each orphaned backend record in `list shares`
3. If the agent is truly wedged: `systemctl stop zrok2-agent`, `rm ~/.zrok2/agent-registry.json`, `systemctl start zrok2-agent`, then re-run the share registration commands

## Backend Modes

| Mode | Flag | Use Case |
|------|------|----------|
| `proxy` | `-b proxy` (default) | Reverse proxy to a local HTTP server |
| `web` | `-b web` | Serve static files from a directory |
| `caddy` | `-b caddy` | Use a Caddyfile for config |
| `drive` | `-b drive` | WebDAV file sharing |
| `tcpTunnel` | `-b tcpTunnel` | Raw TCP (databases, SSH, etc.) |
| `udpTunnel` | `-b udpTunnel` | Raw UDP |
| `socks` | `-b socks` | SOCKS5 proxy (private only) |

## Auth Options

```bash
# Basic auth
zrok2 share public localhost:8080 -n public:myapp --basic-auth "user:pass" --headless

# OAuth (e.g., Google, restrict to domain)
zrok2 share public localhost:8080 -n public:myapp \
  --oauth-provider google --oauth-email-domain "mycompany.com" --headless
```

## Key Differences from zrok v1

| v1 | v2 |
|----|-----|
| `zrok reserve public -n NAME` | `zrok2 create name <name>` then `zrok2 share public <target> -n public:<name>` |
| `zrok share reserved NAME` | `zrok2 share public <target> -n public:<name>` (re-running is idempotent — 409 + exit 0 if already bound) |
| `zrok release <token>` | `zrok2 delete name <name>` (after releasing/deleting any attached share) |
| `zrok release NAME` (one-shot name+share teardown) | Two steps: `agent release share <token>` (or `delete share`) → `delete name <name>` |
| Reservation persists across client restarts inherently | Use `zrok2 agent start` daemon for equivalent behavior |
| `https://<name>.share.zrok.io` | `https://<name>.shares.zrok.io` (plural) |
| `~/.zrok/` | `~/.zrok2/` |
| `ZROK_*` env vars | `ZROK2_*` env vars |
| Binary: `zrok` | Binary: `zrok2` (the v2.x tarball contains a binary literally named `zrok2`, not `zrok` — watch out when scripting installs) |

**Migration rule of thumb:** If you're porting a v1 setup that relied on `zrok reserve public` + `zrok share reserved` for persistence across client restarts, the v2 equivalent is (a) `zrok2 create name` once, (b) run a `zrok2 agent` daemon, (c) register the share against the agent. Don't try to reproduce v1's behavior without the agent — you'll fight 409s on every restart.

## Command-Line Gotchas Worth Remembering

- `zrok2 create name` takes the name as a positional argument. `zrok2 create name <name>` works; `zrok2 create name -n public <name>` (with `-n` for namespace) also works. Shell for-loops where `$name` doesn't expand due to nested quoting will silently pass no arg and error `accepts 1 arg(s), received 0` — always test variable expansion in nested SSH commands.
- `--force-agent` and `--force-local` on `zrok2 share public` skip the auto-detection and force the mode. **Use `--force-agent` in systemd units** so a dead agent produces a loud failure instead of silently starting a non-persistent local tunnel.
- `zrok2 share public` exit codes aren't perfectly aligned with success/failure in agent mode — both "adopted by agent" and "409 name already taken" can exit 0. Don't rely on exit codes to distinguish; inspect stdout/stderr or check `agent status` after running.
- `zrok2 list shares` shows share tokens in whatever column order the binary feels like; don't parse with awk column math. Use `--json` if you need to script against it, or grep for a fixed substring (URL, env ID).
- When the source tarball filename looks like `zrok_X.Y.Z_linux_amd64.tar.gz`, the binary inside is named **`zrok2`** (since v2.0.0). `tar -xzf ... zrok` will fail with "not found in archive". Extract `zrok2` instead.

## Decision Guide

- User wants a **named, reusable URL** → Workflow 1 (create name + share public)
- User wants a **quick throwaway tunnel** → Workflow 2 (ephemeral share)
- User wants to **stop/clean up** → Workflow 3 (tear down — use `agent release share` if agent-managed)
- User wants **always-on / reboot-surviving / systemd-managed tunnels** → Workflow 6 (agent mode with `Type=oneshot RemainAfterExit=yes` unit pattern)
- User wants to **share a DB or non-HTTP service** → Workflow 5 (private + tcpTunnel)
- User is **migrating from v1** and hitting 409 conflicts on restart → they need the agent (Workflow 6), not a retry loop
