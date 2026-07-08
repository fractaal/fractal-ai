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

apply_pi_runtime_patches() {
  local patch_script="$FRACTAL_AI_HOME/pi/patches/apply-pi-runtime-patches.mjs"
  [[ -f "$patch_script" ]] || return 0

  if ! command -v node >/dev/null 2>&1; then
    echo "  WARN: node not found; cannot apply Pi runtime patches" >&2
    return 0
  fi
  if ! command -v pi >/dev/null 2>&1; then
    echo "  WARN: pi not found; cannot apply Pi runtime patches" >&2
    return 0
  fi

  if ! node "$patch_script"; then
    echo "  ERROR: Pi runtime patch application failed; inspect $patch_script" >&2
    return 1
  fi
}

ensure_chrome_devtools_mcp() {
  # Chrome DevTools MCP — browser automation/debugging MCP server, wired into
  # Claude Code / Pi (via ~/.claude.json) and Codex. `--isolated` is deliberate:
  # every MCP server process gets a temporary Chrome profile instead of sharing
  # ~/.cache/chrome-devtools-mcp/chrome-profile, so concurrent agents do not
  # clobber one another's cookies, storage, tabs, or profile lock.
  local chrome_args_json
  local chrome_executable="/opt/google/chrome/google-chrome"
  if [[ -x "$chrome_executable" ]]; then
    chrome_args_json='["-y", "chrome-devtools-mcp@latest", "--executablePath=/opt/google/chrome/google-chrome", "--isolated"]'
  else
    chrome_args_json='["-y", "chrome-devtools-mcp@latest", "--isolated"]'
  fi

  if ! command -v npx >/dev/null 2>&1; then
    echo "  WARN: npx not found; skipping Chrome DevTools MCP wiring" >&2
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  WARN: python3 not found; skipping Chrome DevTools MCP wiring" >&2
    return 0
  fi

  # Claude Code (also feeds Pi via the claude-mcp-bridge reading ~/.claude.json).
  local claude_json="$HOME/.claude.json"
  if [[ -f "$claude_json" ]]; then
    local claude_tmp
    claude_tmp=$(mktemp)
    if CHROME_DEVTOOLS_MCP_ARGS="$chrome_args_json" python3 - "$claude_json" >"$claude_tmp" <<'PY'
import json
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
servers = data.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
    data["mcpServers"] = servers

entry = servers.get("chrome-devtools")
if not isinstance(entry, dict):
    entry = {}

env = entry.get("env")
if not isinstance(env, dict):
    env = {}

entry.update({
    "type": "stdio",
    "command": "npx",
    "args": json.loads(os.environ["CHROME_DEVTOOLS_MCP_ARGS"]),
    "env": env,
})
servers["chrome-devtools"] = entry
sys.stdout.write(json.dumps(data, indent=2) + "\n")
PY
    then
      if ! cmp -s "$claude_json" "$claude_tmp"; then
        echo "  Registering Chrome DevTools MCP for Claude Code / Pi (isolated profile)" >&2
        cp -a "$claude_json" "$claude_json.bak-$(date +%Y%m%d-%H%M%S)"
        mv "$claude_tmp" "$claude_json"
      else
        rm "$claude_tmp"
      fi
    else
      rm -f "$claude_tmp"
      echo "  WARN: failed to update Chrome DevTools MCP in $claude_json" >&2
    fi
  elif command -v claude >/dev/null 2>&1; then
    echo "  Registering Chrome DevTools MCP for Claude Code / Pi (isolated profile)" >&2
    if [[ -x "$chrome_executable" ]]; then
      claude mcp add --scope user chrome-devtools -- \
        npx -y chrome-devtools-mcp@latest --executablePath="$chrome_executable" --isolated >/dev/null 2>&1 \
        || echo "  WARN: 'claude mcp add chrome-devtools' failed" >&2
    else
      claude mcp add --scope user chrome-devtools -- \
        npx -y chrome-devtools-mcp@latest --isolated >/dev/null 2>&1 \
        || echo "  WARN: 'claude mcp add chrome-devtools' failed" >&2
    fi
  else
    echo "  NOTE: ~/.claude.json absent and claude CLI not found; Chrome DevTools MCP not wired for Claude Code / Pi" >&2
  fi

  # Codex.
  local codex_cfg="$HOME/.codex/config.toml"
  if [[ -f "$codex_cfg" ]]; then
    if command -v uv >/dev/null 2>&1; then
      local codex_tmp
      codex_tmp=$(mktemp)
      if CHROME_DEVTOOLS_MCP_ARGS="$chrome_args_json" uv run --quiet --with tomlkit python3 - "$codex_cfg" >"$codex_tmp" <<'PY'
import json
import os
import sys
import tomlkit

path = sys.argv[1]
doc = tomlkit.parse(open(path).read())
servers = doc.get("mcp_servers")
if servers is None:
    servers = tomlkit.table()
    doc["mcp_servers"] = servers

args = tomlkit.array()
args.multiline(False)
for arg in json.loads(os.environ["CHROME_DEVTOOLS_MCP_ARGS"]):
    args.append(arg)

entry = servers.get("chrome-devtools")
if not (hasattr(entry, "items") and not isinstance(entry, str)):
    entry = tomlkit.table()
    servers["chrome-devtools"] = entry

entry["command"] = "npx"
entry["args"] = args
sys.stdout.write(tomlkit.dumps(doc))
PY
      then
        if ! cmp -s "$codex_cfg" "$codex_tmp"; then
          echo "  Registering Chrome DevTools MCP for Codex (isolated profile)" >&2
          cp -a "$codex_cfg" "$codex_cfg.bak-$(date +%Y%m%d-%H%M%S)"
          mv "$codex_tmp" "$codex_cfg"
        else
          rm "$codex_tmp"
        fi
      else
        rm -f "$codex_tmp"
        echo "  WARN: failed to update Chrome DevTools MCP in $codex_cfg" >&2
      fi
    else
      echo "  WARN: uv not found; cannot update Codex Chrome DevTools MCP config (needs tomlkit). Skipping." >&2
    fi
  else
    echo "  NOTE: ~/.codex/config.toml absent; run Codex once, then re-run install to wire Chrome DevTools MCP" >&2
  fi
}

ensure_codex_config() {
  # Codex's ~/.codex/config.toml co-mingles portable prefs (model, approval/sandbox
  # posture, features) with per-machine runtime state: [projects.*] trust paths,
  # [marketplaces.*], [plugins.*], [hooks.state.*], Codex-Desktop's node_repl,
  # [tui.*]. So we cannot symlink it — that would leak the trust-path tree into
  # this public repo and be clobbered by Codex on every run. Instead we MERGE the
  # portable subset from codex/config.toml into the base file with a TOML-correct
  # overlay (tomlkit via uv): managed keys update in place, tables merge, and the
  # doc is rebuilt so root scalars always precede tables (else TOML reparents a new
  # root scalar under the preceding table and corrupts the file). Everything not in
  # codex/config.toml is left exactly as Codex/Desktop wrote it. Idempotent.
  local src="$FRACTAL_AI_HOME/codex/config.toml"
  local dst="$HOME/.codex/config.toml"
  [[ -f "$src" ]] || return 0
  if ! command -v codex >/dev/null 2>&1; then
    echo "  NOTE: codex CLI not found; skipping Codex config management" >&2
    return 0
  fi
  if [[ ! -f "$dst" ]]; then
    echo "  NOTE: ~/.codex/config.toml absent; run Codex once, then re-run install to manage it" >&2
    return 0
  fi
  if ! command -v uv >/dev/null 2>&1; then
    echo "  WARN: uv not found; cannot merge Codex config (needs tomlkit). Skipping." >&2
    return 0
  fi
  echo "  Merging portable Codex config into ~/.codex/config.toml" >&2
  cp -a "$dst" "$dst.bak-$(date +%Y%m%d-%H%M%S)"
  if ! uv run --quiet --with tomlkit python3 - "$dst" "$src" <<'PY'
import sys, tomlkit
dst_path, src_path = sys.argv[1], sys.argv[2]
dst = tomlkit.parse(open(dst_path).read())
src = tomlkit.parse(open(src_path).read())

def is_tbl(x):
    return hasattr(x, "items") and not isinstance(x, str)

def overlay(d, s):
    for k, v in s.items():
        if is_tbl(v) and k in d and is_tbl(d[k]):
            overlay(d[k], v)
        else:
            d[k] = v

overlay(dst, src)

# Rebuild root scalars-before-tables so a newly added root scalar can never be
# reparented under a preceding table (the TOML footgun that corrupts the file).
out = tomlkit.document()
for k, item in list(dst.items()):
    if not is_tbl(item):
        out[k] = item
for k, item in list(dst.items()):
    if is_tbl(item):
        out[k] = item

open(dst_path, "w").write(tomlkit.dumps(out))
PY
  then
    echo "  WARN: Codex config merge failed; original is preserved at the .bak above" >&2
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
pi_bin_source="$FRACTAL_AI_HOME/pi/bin"

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

if [[ -d "$pi_bin_source" ]]; then
  link_directory_children "$pi_bin_source" "$HOME/.local/bin"
fi

# ── Cross-harness MCP servers (Claude Code / Pi / Codex) ──────────────
ensure_chrome_devtools_mcp

# ── Codex portable config (merged into ~/.codex/config.toml, not symlinked) ──
ensure_codex_config

apply_pi_runtime_patches

# ── Machine-local / private wiring (gitignored). Sourced last so it can use the
#    helpers/env above; holds anything whose details must not be in this public
#    repo (e.g. internal MCP endpoints). Absent on most machines. ──
if [[ -f "$FRACTAL_AI_HOME/deploy/install.local.sh" ]]; then
  # shellcheck source=/dev/null
  source "$FRACTAL_AI_HOME/deploy/install.local.sh"
fi

warn_stale_settings_local
