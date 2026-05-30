#!/usr/bin/env bash
set -euo pipefail

FRACTAL_AI_HOME="${FRACTAL_AI_HOME:-$HOME/.fractal-ai}"

link_item() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" ]]; then
    local current
    current=$(readlink "$target")
    if [[ "$current" == "$source" ]]; then
      return 0
    fi
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup
    backup="${target}.bak-$(date +%Y%m%d-%H%M%S)"
    if [[ -L "$target" ]]; then
      echo "  backup: replacing stale symlink $target -> $backup" >&2
    else
      echo "  BACKUP: displacing real file/dir $target -> $backup (review before deleting)" >&2
    fi
    mv "$target" "$backup"
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
}

ensure_directory_target() {
  local target="$1"

  if [[ -L "$target" ]]; then
    echo "  cleanup: replacing directory symlink $target with a real directory" >&2
    rm "$target"
  elif [[ -e "$target" && ! -d "$target" ]]; then
    local backup
    backup="${target}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "  BACKUP: displacing non-directory $target -> $backup (review before deleting)" >&2
    mv "$target" "$backup"
  fi

  mkdir -p "$target"
}

link_directory_children() {
  local source="$1"
  local target="$2"
  local child

  ensure_directory_target "$target"
  for child in "$source"/*; do
    [[ -e "$child" ]] || continue
    link_item "$child" "$target/$(basename "$child")"
  done
}

restore_agents_system_skills() {
  local target="$1"
  local backup
  local latest=""

  [[ -e "$target/.system" ]] && return 0
  for backup in "$target".bak-*; do
    [[ -d "$backup/.system" ]] || continue
    latest="$backup"
  done
  [[ -n "$latest" ]] || return 0

  echo "  restore: copying Codex-managed system skills from $latest/.system" >&2
  cp -a "$latest/.system" "$target/.system"
}

remove_legacy_skill_link() {
  local target="$1"
  local source="$2"
  local shared_target="$HOME/.agents/skills"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi

  if [[ -L "$target" ]]; then
    local current
    current=$(readlink "$target")
    if [[ "$current" == "$source" || "$current" == "$shared_target" ]]; then
      echo "  cleanup: removing legacy skill symlink $target" >&2
      rm "$target"
      return 0
    fi
    echo "  WARN: leaving non-fractal legacy skill symlink $target -> $current" >&2
    return 0
  fi

  echo "  WARN: leaving real legacy skill directory $target; move it aside manually if it causes duplicates" >&2
}

# Warn if ~/.claude/settings.local.json still contains keys that are now owned
# by the canonical (user-global) settings.json. The previous layout rendered
# `hooks` and `statusLine` into settings.local.json, but that file is cwd-
# ancestry-scoped (only loads when cwd is under $HOME), so those entries
# silently failed for sessions outside $HOME. Both keys now live in the
# canonical settings.json. Stale copies in settings.local.json cause hook
# duplication (Claude Code merges arrays across precedence scopes; the
# string-difference between `~/...` and `$HOME-substituted/...` defeats
# dedup), so leaving them risks every Stop/Edit firing the gates twice.
PI_MCP_BRIDGE_COMMIT="879cf3d9dd51f5315e98958a7d0ea55e1314da4a"

warn_stale_settings_local() {
  local target="$HOME/.claude/settings.local.json"
  [[ -f "$target" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq empty "$target" 2>/dev/null || return 0

  local stale
  stale=$(jq -r '[keys[] | select(. == "hooks" or . == "statusLine")] | join(", ")' "$target")
  if [[ -n "$stale" ]]; then
    echo "" >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    echo "  WARN: $target still contains stale top-level keys: $stale" >&2
    echo "        These keys are now owned by the canonical settings.json (user-global)." >&2
    echo "        Leaving them here causes duplicate hook firing on every Stop/Edit." >&2
    echo "" >&2
    echo "        Run this to clean them up (preserves all your other local keys):" >&2
    echo "          tmp=\$(mktemp) && jq 'del(.hooks, .statusLine)' \"$target\" > \"\$tmp\" && mv \"\$tmp\" \"$target\"" >&2
    echo "  ────────────────────────────────────────────────────────────" >&2
    echo "" >&2
  fi
}

ensure_pi_mcp_bridge_cache() {
  local cache="$HOME/.pi/agent/git/github.com/fractaal/pi-extension"

  if ! command -v git >/dev/null 2>&1; then
    echo "  WARN: git not found; cannot install or verify cached Pi MCP bridge package" >&2
    return 0
  fi

  if [[ ! -d "$cache/.git" ]]; then
    if [[ -e "$cache" ]]; then
      echo "  WARN: $cache exists but is not a git checkout; cannot install Pi MCP bridge package cache" >&2
      return 0
    fi
    echo "  Installing cached Pi MCP bridge package at $cache" >&2
    mkdir -p "$(dirname "$cache")"
    if ! git clone https://github.com/fractaal/pi-extension.git "$cache"; then
      echo "  WARN: failed to clone Pi MCP bridge package; Pi may install it on first startup" >&2
      return 0
    fi
  fi

  local current
  current=$(git -C "$cache" rev-parse HEAD 2>/dev/null || true)
  [[ "$current" == "$PI_MCP_BRIDGE_COMMIT" ]] && return 0

  echo "  Updating cached Pi MCP bridge package to $PI_MCP_BRIDGE_COMMIT" >&2
  if ! git -C "$cache" fetch origin async-mcp-startup; then
    echo "  WARN: failed to fetch Pi MCP bridge package; Pi may keep using cached commit $current" >&2
    return 0
  fi
  if ! git -C "$cache" checkout --detach "$PI_MCP_BRIDGE_COMMIT"; then
    echo "  WARN: failed to checkout Pi MCP bridge package commit $PI_MCP_BRIDGE_COMMIT" >&2
    return 0
  fi

  if [[ -f "$cache/package.json" ]]; then
    if command -v npm >/dev/null 2>&1; then
      if ! (cd "$cache" && npm install --omit=dev); then
        echo "  WARN: failed to install Pi MCP bridge package dependencies" >&2
      fi
    else
      echo "  WARN: npm not found; Pi MCP bridge package dependencies may install on first Pi startup" >&2
    fi
  fi
}

ensure_serena_mcp() {
  # Serena (https://github.com/oraios/serena) — semantic-code MCP server, wired
  # into every harness Ben uses. See mcp/README.md for the architecture.
  #   * Claude Code: user-scope entry in ~/.claude.json (via `claude mcp add`)
  #   * Pi:          its claude-mcp-bridge reads ~/.claude.json, so the Claude
  #                  entry above also serves Pi — no separate Pi config needed
  #   * Codex:       [mcp_servers.serena] appended to ~/.codex/config.toml
  # `--open-web-dashboard False` stops Serena auto-opening a browser tab on every
  # MCP start. Idempotent: only writes what is missing.
  local serena_bin
  serena_bin="$(command -v serena 2>/dev/null || true)"

  if [[ -z "$serena_bin" ]]; then
    if command -v uv >/dev/null 2>&1; then
      echo "  Installing Serena (uv tool install serena-agent)" >&2
      if uv tool install -p 3.13 serena-agent >/dev/null 2>&1; then
        serena_bin="$(command -v serena 2>/dev/null || echo "$HOME/.local/bin/serena")"
      else
        echo "  WARN: failed to install serena-agent; skipping Serena MCP wiring" >&2
        return 0
      fi
    else
      echo "  WARN: serena not found and uv unavailable; skipping Serena MCP wiring" >&2
      return 0
    fi
  fi

  # Best-effort: stop the dashboard browser tab for all Serena usage on this box.
  local serena_cfg="$HOME/.serena/serena_config.yml"
  if [[ -f "$serena_cfg" ]]; then
    sed -i 's/^web_dashboard_open_on_launch: true/web_dashboard_open_on_launch: false/' "$serena_cfg" 2>/dev/null || true
  fi

  # Claude Code (also feeds Pi via the claude-mcp-bridge reading ~/.claude.json).
  if command -v claude >/dev/null 2>&1; then
    if ! claude mcp get serena >/dev/null 2>&1; then
      echo "  Registering Serena MCP for Claude Code (user scope)" >&2
      claude mcp add --scope user serena -- \
        "$serena_bin" start-mcp-server --context claude-code \
        --project-from-cwd --open-web-dashboard False >/dev/null 2>&1 \
        || echo "  WARN: 'claude mcp add serena' failed" >&2
    fi
  else
    echo "  WARN: claude CLI not found; Serena not wired for Claude Code / Pi" >&2
  fi

  # Codex.
  local codex_cfg="$HOME/.codex/config.toml"
  if [[ -f "$codex_cfg" ]]; then
    if ! grep -q '^\[mcp_servers\.serena\]' "$codex_cfg"; then
      echo "  Registering Serena MCP for Codex (~/.codex/config.toml)" >&2
      cp -a "$codex_cfg" "$codex_cfg.bak-$(date +%Y%m%d-%H%M%S)"
      {
        printf '\n[mcp_servers.serena]\n'
        printf 'startup_timeout_sec = 60\n'
        printf 'command = "%s"\n' "$serena_bin"
        printf 'args = ["start-mcp-server", "--project-from-cwd", "--context=codex", "--open-web-dashboard", "False"]\n'
      } >> "$codex_cfg"
    fi
  else
    echo "  NOTE: ~/.codex/config.toml absent; create it (run Codex once) and re-run install to wire Serena" >&2
  fi
}

# ── Shared sources (portable across all AI tools) ─────────────────────
deployed_instructions_source="$FRACTAL_AI_HOME/DEPLOYED-INSTRUCTIONS.md"
skills_source="$FRACTAL_AI_HOME/skills"

# ── Claude-specific sources ───────────────────────────────────────────
claude_settings_source="$FRACTAL_AI_HOME/claude/settings.json"
claude_hooks_source="$FRACTAL_AI_HOME/claude/hooks"
claude_statusline_source="$FRACTAL_AI_HOME/claude/statusline-command.sh"

# ── Pi-specific sources ───────────────────────────────────────────────
pi_settings_source="$FRACTAL_AI_HOME/pi/settings.json"
pi_extensions_source="$FRACTAL_AI_HOME/pi/extensions"

# ── Shared: deploy DEPLOYED-INSTRUCTIONS.md as AGENTS.md / CLAUDE.md ──
if [[ -f "$deployed_instructions_source" ]]; then
  link_item "$deployed_instructions_source" "$HOME/.codex/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.opencode/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.claude/CLAUDE.md"
  link_item "$deployed_instructions_source" "$HOME/.pi/agent/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.gemini/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.gemini/CLAUDE.md"
  link_item "$deployed_instructions_source" "$HOME/.augment/AGENTS.md"
fi

# ── Shared: deploy skills/ to supported skill roots ───────────────────
if [[ -d "$skills_source" ]]; then
  # Codex Desktop and Pi both scan ~/.agents/skills. Keep that shared root as a
  # real directory because Codex also places managed .system skills there; install
  # fractal-ai skills as per-skill symlinks instead of owning the whole root.
  link_directory_children "$skills_source" "$HOME/.agents/skills"
  restore_agents_system_skills "$HOME/.agents/skills"
  remove_legacy_skill_link "$HOME/.codex/skills" "$skills_source"
  remove_legacy_skill_link "$HOME/.pi/agent/skills" "$skills_source"

  link_item "$skills_source" "$HOME/.opencode/skills"
  link_item "$skills_source" "$HOME/.claude/skills"
  link_item "$skills_source" "$HOME/.gemini/skills"
  link_item "$skills_source" "$HOME/.augment/skills"
fi

# ── Claude-only: settings.json, hooks/, statusline-command.sh ─────────
if [[ -f "$claude_settings_source" ]]; then
  link_item "$claude_settings_source" "$HOME/.claude/settings.json"
fi

if [[ -d "$claude_hooks_source" ]]; then
  link_item "$claude_hooks_source" "$HOME/.claude/hooks"
fi

if [[ -f "$claude_statusline_source" ]]; then
  link_item "$claude_statusline_source" "$HOME/.claude/statusline-command.sh"
fi

# ── Pi-only: settings.json, extensions ────────────────────────────────
if [[ -f "$pi_settings_source" ]]; then
  link_item "$pi_settings_source" "$HOME/.pi/agent/settings.json"
  ensure_pi_mcp_bridge_cache
fi

if [[ -d "$pi_extensions_source" ]]; then
  link_item "$pi_extensions_source" "$HOME/.pi/agent/extensions"
fi

# ── Cross-harness MCP servers (Claude Code / Pi / Codex) ──────────────
ensure_serena_mcp

warn_stale_settings_local
