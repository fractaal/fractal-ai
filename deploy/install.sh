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
BLENDER_MCP_SERVER_VERSION="1.6.4"
BLENDER_MCP_ADDON_COMMIT="6641189231caf3752302ae20591bc87fda85fc4e"
BLENDER_MCP_ADDON_SHA256="bba60831f5f89a74deda0294b131668a086cf46eb35a6a01abbd0d21d9e92630"

file_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    return 1
  fi
}

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

ensure_claude_pi_stdio_mcp() {
  local server_name="$1"
  local display_name="$2"
  local server_command="$3"
  shift 3
  local -a server_args=("$@")
  local claude_json="$HOME/.claude.json"

  if [[ -f "$claude_json" ]]; then
    if ! command -v node >/dev/null 2>&1; then
      echo "  WARN: node not found; cannot update $display_name in $claude_json" >&2
      return 0
    fi

    local claude_tmp
    claude_tmp=$(mktemp "${claude_json}.tmp.XXXXXX")
    if node - "$claude_json" "$server_name" "$server_command" "${server_args[@]}" >"$claude_tmp" <<'JS'
const fs = require("node:fs");

const [configPath, serverName, command, ...args] = process.argv.slice(2);
const raw = fs.readFileSync(configPath, "utf8");
const data = JSON.parse(raw);
if (!data || Array.isArray(data) || typeof data !== "object") {
  throw new Error(`${configPath} must contain a JSON object`);
}

const serversAreValid = data.mcpServers && !Array.isArray(data.mcpServers) && typeof data.mcpServers === "object";
const current = serversAreValid ? data.mcpServers[serverName] : undefined;
const currentIsValid = current && !Array.isArray(current) && typeof current === "object";
const envIsValid = currentIsValid && current.env && !Array.isArray(current.env) && typeof current.env === "object";
const alreadyConfigured =
  currentIsValid &&
  envIsValid &&
  current.type === "stdio" &&
  current.command === command &&
  JSON.stringify(current.args) === JSON.stringify(args) &&
  !("url" in current) &&
  !("headers" in current);

if (alreadyConfigured) {
  process.stdout.write(raw);
  process.exit(0);
}

if (!serversAreValid) data.mcpServers = {};
const entry = currentIsValid ? { ...current } : {};
const env = envIsValid ? entry.env : {};

// Remove fields from remote transports while preserving unrelated client metadata.
delete entry.url;
delete entry.headers;
Object.assign(entry, { type: "stdio", command, args, env });
data.mcpServers[serverName] = entry;
process.stdout.write(`${JSON.stringify(data, null, 2)}\n`);
JS
    then
      if ! cmp -s "$claude_json" "$claude_tmp"; then
        echo "  Registering $display_name for Claude Code / Pi" >&2
        cp -a "$claude_json" "$claude_json.bak-${server_name}-$(date +%Y%m%d-%H%M%S)"
        mv "$claude_tmp" "$claude_json"
      else
        rm "$claude_tmp"
      fi
    else
      rm -f "$claude_tmp"
      echo "  WARN: failed to update $display_name in $claude_json" >&2
    fi
  elif command -v claude >/dev/null 2>&1; then
    echo "  Registering $display_name for Claude Code / Pi" >&2
    claude mcp add --scope user "$server_name" -- \
      "$server_command" "${server_args[@]}" >/dev/null 2>&1 \
      || echo "  WARN: 'claude mcp add $server_name' failed" >&2
  else
    echo "  NOTE: ~/.claude.json absent and claude CLI not found; $display_name not wired for Claude Code / Pi" >&2
  fi
}

ensure_blender_mcp_addon() {
  # BlenderMCP publishes its MCP server through PyPI, but distributes the
  # Blender-side add-on as one raw addon.py rather than a versioned Blender
  # Extension. Keep the immutable upstream revision here and install the fetched
  # source under fractal-ai's generated runtime layer; Blender receives a symlink.
  local blender_bin=""
  if command -v blender >/dev/null 2>&1; then
    blender_bin=$(command -v blender)
  elif [[ -x "/Applications/Blender.app/Contents/MacOS/Blender" ]]; then
    blender_bin="/Applications/Blender.app/Contents/MacOS/Blender"
  else
    echo "  NOTE: Blender not found; skipping BlenderMCP add-on installation" >&2
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1 || ! file_sha256 /dev/null >/dev/null 2>&1; then
    echo "  WARN: curl and a SHA-256 tool are required to install the pinned BlenderMCP add-on" >&2
    return 1
  fi

  local install_dir="$FRACTAL_AI_HOME/.installed/blender-mcp/$BLENDER_MCP_ADDON_COMMIT"
  local addon_source="$install_dir/blender_mcp.py"
  local addon_url="https://raw.githubusercontent.com/ahujasid/blender-mcp/$BLENDER_MCP_ADDON_COMMIT/addon.py"
  local actual_sha=""
  if [[ -f "$addon_source" ]]; then
    actual_sha=$(file_sha256 "$addon_source")
  fi
  if [[ "$actual_sha" != "$BLENDER_MCP_ADDON_SHA256" ]]; then
    echo "  Installing pinned BlenderMCP add-on $BLENDER_MCP_ADDON_COMMIT" >&2
    mkdir -p "$install_dir"
    local addon_tmp="$addon_source.tmp.$$"
    if ! curl -fsSL "$addon_url" -o "$addon_tmp"; then
      rm -f "$addon_tmp"
      echo "  WARN: failed to download BlenderMCP add-on" >&2
      return 1
    fi
    actual_sha=$(file_sha256 "$addon_tmp")
    if [[ "$actual_sha" != "$BLENDER_MCP_ADDON_SHA256" ]]; then
      rm -f "$addon_tmp"
      echo "  WARN: BlenderMCP add-on checksum mismatch; refusing to install" >&2
      return 1
    fi
    mv "$addon_tmp" "$addon_source"
  fi

  local addon_dir
  addon_dir=$(
    "$blender_bin" --background --python-exit-code 1 --python-expr \
      "import bpy; print('FRACTAL_BLENDER_ADDONS=' + bpy.utils.user_resource('SCRIPTS', path='addons', create=True))" \
      2>/dev/null \
      | sed -n 's/^FRACTAL_BLENDER_ADDONS=//p' \
      | tail -1
  )
  if [[ -z "$addon_dir" ]]; then
    echo "  WARN: Blender did not report its add-on directory" >&2
    return 1
  fi

  link_item "$addon_source" "$addon_dir/blender_mcp.py"

  # Enable globally for future GUI launches. Background Blender intentionally
  # refuses to start the live socket, but can safely persist the enabled add-on
  # and disable its preference-level telemetry before the next GUI launch.
  if ! "$blender_bin" --background --python-exit-code 1 --python-expr '
import bpy
changed = False
if "blender_mcp" not in bpy.context.preferences.addons:
    bpy.ops.preferences.addon_enable(module="blender_mcp")
    changed = True
addon = bpy.context.preferences.addons.get("blender_mcp")
if addon and addon.preferences.telemetry_consent:
    addon.preferences.telemetry_consent = False
    changed = True
if changed:
    bpy.ops.wm.save_userpref()
assert "blender_mcp" in bpy.context.preferences.addons
' >/dev/null; then
    echo "  WARN: BlenderMCP add-on was installed but could not be enabled" >&2
    return 1
  fi
  return 0
}

ensure_blender_mcp() {
  # BlenderMCP — live scene inspection/manipulation in the open Blender GUI.
  # The stdio server lazily connects to the add-on's localhost-only socket.
  # Telemetry is disabled completely at the server boundary; the Blender add-on
  # preference is also disabled by ensure_blender_mcp_addon above.
  if ! command -v uvx >/dev/null 2>&1; then
    echo "  WARN: uvx not found; skipping Blender MCP wiring" >&2
    return 0
  fi
  local uvx_bin
  uvx_bin=$(command -v uvx)

  if ! ensure_blender_mcp_addon; then
    echo "  WARN: Blender MCP server wiring skipped because the Blender add-on is unavailable" >&2
    return 0
  fi
  ensure_claude_pi_stdio_mcp \
    "blender" "Blender MCP (live GUI scene)" "env" \
    DISABLE_TELEMETRY=true \
    BLENDER_HOST=localhost \
    BLENDER_PORT=9876 \
    UV_PYTHON_PREFERENCE=only-managed \
    "$uvx_bin" --python 3.11 "blender-mcp==$BLENDER_MCP_SERVER_VERSION"
}

ensure_rovo_mcp() {
  # Atlassian Rovo MCP — Jira/Confluence/Compass tools for Claude Code and Pi.
  # Claude Code can authenticate to the remote HTTP endpoint directly, but Pi's
  # claude-mcp-bridge has no OAuth provider. Atlassian's documented mcp-remote
  # proxy gives both harnesses one shared stdio entry in ~/.claude.json.
  local rovo_url="https://mcp.atlassian.com/v1/mcp/authv2"

  if ! command -v npx >/dev/null 2>&1; then
    echo "  WARN: npx not found; skipping Atlassian Rovo MCP wiring" >&2
    return 0
  fi

  ensure_claude_pi_stdio_mcp \
    "rovo" "Atlassian Rovo MCP" "npx" \
    -y mcp-remote@latest "$rovo_url"
}

ensure_chrome_devtools_mcp() {
  # Chrome DevTools MCP — browser automation/debugging MCP server, wired into
  # Claude Code / Pi (via ~/.claude.json) and Codex. `--isolated` is deliberate:
  # every MCP server process gets a temporary Chrome profile instead of sharing
  # ~/.cache/chrome-devtools-mcp/chrome-profile, so concurrent agents do not
  # clobber one another's cookies, storage, tabs, or profile lock.
  local chrome_executable="/opt/google/chrome/google-chrome"
  local -a chrome_args
  if [[ -x "$chrome_executable" ]]; then
    chrome_args=(-y chrome-devtools-mcp@latest "--executablePath=$chrome_executable" --isolated)
  else
    chrome_args=(-y chrome-devtools-mcp@latest --isolated)
  fi

  if ! command -v npx >/dev/null 2>&1; then
    echo "  WARN: npx not found; skipping Chrome DevTools MCP wiring" >&2
    return 0
  fi

  ensure_claude_pi_stdio_mcp \
    "chrome-devtools" "Chrome DevTools MCP (isolated profile)" "npx" \
    "${chrome_args[@]}"

  # Codex.
  local codex_cfg="$HOME/.codex/config.toml"
  if [[ -f "$codex_cfg" ]]; then
    if command -v uv >/dev/null 2>&1; then
      local codex_tmp
      codex_tmp=$(mktemp)
      if uv run --quiet --with tomlkit python3 - "$codex_cfg" "${chrome_args[@]}" >"$codex_tmp" <<'PY'
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
for arg in sys.argv[2:]:
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

# ── Cross-harness MCP servers ─────────────────────────────────────────
ensure_chrome_devtools_mcp
ensure_rovo_mcp
ensure_blender_mcp

# ── Codex portable config (merged into ~/.codex/config.toml, not symlinked) ──
ensure_codex_config

# ── Machine-local / private wiring (gitignored). Sourced last so it can use the
#    helpers/env above; holds anything whose details must not be in this public
#    repo (e.g. internal MCP endpoints). Absent on most machines. ──
if [[ -f "$FRACTAL_AI_HOME/deploy/install.local.sh" ]]; then
  # shellcheck source=/dev/null
  source "$FRACTAL_AI_HOME/deploy/install.local.sh"
fi

warn_stale_settings_local
