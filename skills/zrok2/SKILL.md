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
list active tunnels, and tear down resources. Binary lives at `~/.local/bin/zrok2`.

## Prerequisites

The environment must be enabled before any share operations work. Check with:

```bash
~/.local/bin/zrok2 status
```

If not enabled, the user needs their account token from [myzrok.io](https://myzrok.io):

```bash
~/.local/bin/zrok2 enable <accountToken> --headless
```

**Always verify environment status before attempting share operations.**

## Core Workflows

### 1. Spin Up a Named Public URL

This is the most common request. The user says something like "expose port 3000 as myapp"
or "spin up a zrok URL called blingblong".

**Steps:**

1. Check if the name already exists:
   ```bash
   ~/.local/bin/zrok2 list names --json 2>/dev/null | grep -i "<name>"
   ```

2. Create the name if it doesn't exist:
   ```bash
   ~/.local/bin/zrok2 create name <name>
   ```

3. Start the share (run in background so it doesn't block the conversation):
   ```bash
   ~/.local/bin/zrok2 share public <target> -n public:<name> --headless
   ```
   - Default target is `localhost:PORT`. Ask the user what port if not specified.
   - Use `--headless` always (TUI doesn't work in this context).
   - The resulting URL will be `https://<name>.share.zrok.io`.

4. Report the URL back: `https://<name>.share.zrok.io`

**Important:** The share command is long-running (it holds the tunnel open). Run it in
the background using `run_in_background: true` on the Bash tool call. Warn the user
that closing the terminal or killing the process will drop the tunnel.

### 2. Quick Ephemeral Share (No Name)

When the user just wants a throwaway URL without a persistent name:

```bash
~/.local/bin/zrok2 share public localhost:<port> --headless
```

The URL will be random. Parse it from the output and report it.

### 3. Tear Down a Share

The user says "tear down", "stop the tunnel", "kill the zrok share", etc.

**Steps:**

1. List active shares to find the right one:
   ```bash
   ~/.local/bin/zrok2 list shares --json
   ```

2. Delete the share:
   ```bash
   ~/.local/bin/zrok2 delete share <shareToken>
   ```

3. Optionally delete the reserved name too (ask the user -- they may want to reuse it):
   ```bash
   ~/.local/bin/zrok2 delete name <name>
   ```

4. If the share process is still running in the background, kill it:
   ```bash
   pkill -f "zrok2 share.*<name>"
   ```

### 4. Check Status / List Everything

```bash
# Environment status
~/.local/bin/zrok2 status

# All shares
~/.local/bin/zrok2 list shares

# All reserved names
~/.local/bin/zrok2 list names

# Full overview
~/.local/bin/zrok2 overview
```

### 5. Private Shares (TCP/UDP Tunnels, Internal Services)

For sharing services only accessible to other zrok users (not public web):

```bash
# Share privately with a persistent token
~/.local/bin/zrok2 share private localhost:<port> --share-token <name> --headless

# TCP tunnel (e.g., database)
~/.local/bin/zrok2 share private localhost:5432 -b tcpTunnel --share-token my-db --headless

# Consumer side (whoever needs to access it)
~/.local/bin/zrok2 access private <shareToken> -b 127.0.0.1:<localPort>
```

### 6. Agent Mode (Persistent Background Daemon)

For shares that should survive across sessions and auto-restart on failure:

```bash
# Start the agent daemon
~/.local/bin/zrok2 agent start

# Shares auto-detect the agent and run in managed mode
~/.local/bin/zrok2 share public localhost:8080 -n public:myapp --headless

# Check agent-managed shares
~/.local/bin/zrok2 agent status

# Release a share from the agent
~/.local/bin/zrok2 agent release share <token>
```

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
~/.local/bin/zrok2 share public localhost:8080 -n public:myapp --basic-auth "user:pass" --headless

# OAuth (e.g., Google, restrict to domain)
~/.local/bin/zrok2 share public localhost:8080 -n public:myapp \
  --oauth-provider google --oauth-email-domain "mycompany.com" --headless
```

## Key Differences from zrok v1

| v1 | v2 |
|----|-----|
| `zrok reserve public` | `zrok2 create name <name>` |
| `zrok share reserved <token>` | `zrok2 share public <target> -n public:<name>` |
| `zrok release <token>` | `zrok2 delete name <name>` |
| `~/.zrok/` | `~/.zrok2/` |
| `ZROK_*` env vars | `ZROK2_*` env vars |

## Decision Guide

- User wants a **named, reusable URL** -> Workflow 1 (create name + share public)
- User wants a **quick throwaway tunnel** -> Workflow 2 (ephemeral share)
- User wants to **stop/clean up** -> Workflow 3 (tear down)
- User wants **always-on background tunnel** -> Workflow 6 (agent mode)
- User wants to **share a DB or non-HTTP service** -> Workflow 5 (private + tcpTunnel)
