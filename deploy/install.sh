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

# Render claude/settings.local.json.template -> ~/.claude/settings.local.json,
# substituting $HOME (literal parameter expansion, no regex hazards) and
# deep-merging onto any existing file. Template wins on overlapping keys
# (hooks, statusLine); user-managed keys outside the template (permissions,
# enabledPlugins, etc.) are preserved. NOTE: jq object-merge replaces arrays
# wholesale — custom entries inside template-managed sections (e.g. user-added
# hooks) are overwritten. Add such entries to the template instead.
# Idempotent: no-op if merged result equals current canonical form.
# Robust: malformed existing JSON is moved to .bak-malformed-* and re-rendered
# fresh rather than aborting the installer.
render_settings_local() {
  local template="$1"
  local target="$2"

  [[ -f "$template" ]] || return 0

  if ! command -v jq >/dev/null 2>&1; then
    echo "  WARN: jq not found; skipping $target render" >&2
    return 0
  fi

  local raw
  raw=$(< "$template")
  local rendered="${raw//\$HOME/$HOME}"

  local rendered_canon
  rendered_canon=$(printf '%s' "$rendered" | jq .)

  local desired
  if [[ -f "$target" ]]; then
    if ! jq empty "$target" 2>/dev/null; then
      local backup="${target}.bak-malformed-$(date +%Y%m%d-%H%M%S)"
      mv "$target" "$backup"
      echo "  WARN: $target was malformed JSON; moved to $backup, re-rendering fresh" >&2
      desired="$rendered_canon"
    else
      local current
      current=$(jq . "$target")
      desired=$(jq -n \
        --argjson e "$current" \
        --argjson r "$rendered_canon" \
        '$e * $r')
      if [[ "$current" == "$desired" ]]; then
        return 0
      fi
      local backup="${target}.bak-$(date +%Y%m%d-%H%M%S)"
      cp "$target" "$backup"
      echo "  re-rendered: merged $template -> $target (backup: $backup)" >&2
    fi
  else
    desired="$rendered_canon"
    mkdir -p "$(dirname "$target")"
    echo "  rendered: $template -> $target" >&2
  fi

  printf '%s\n' "$desired" > "$target"
}

# ── Shared sources (portable across all AI tools) ─────────────────────
deployed_instructions_source="$FRACTAL_AI_HOME/DEPLOYED-INSTRUCTIONS.md"
skills_source="$FRACTAL_AI_HOME/skills"

# ── Claude-specific sources ───────────────────────────────────────────
claude_settings_source="$FRACTAL_AI_HOME/claude/settings.json"
claude_settings_local_template="$FRACTAL_AI_HOME/claude/settings.local.json.template"
claude_hooks_source="$FRACTAL_AI_HOME/claude/hooks"
claude_statusline_source="$FRACTAL_AI_HOME/claude/statusline-command.sh"

# ── Shared: deploy DEPLOYED-INSTRUCTIONS.md as AGENTS.md / CLAUDE.md ──
if [[ -f "$deployed_instructions_source" ]]; then
  link_item "$deployed_instructions_source" "$HOME/.codex/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.opencode/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.claude/CLAUDE.md"
  link_item "$deployed_instructions_source" "$HOME/.gemini/AGENTS.md"
  link_item "$deployed_instructions_source" "$HOME/.gemini/CLAUDE.md"
  link_item "$deployed_instructions_source" "$HOME/.augment/AGENTS.md"
fi

# ── Shared: deploy skills/ to every supported tool ────────────────────
if [[ -d "$skills_source" ]]; then
  link_item "$skills_source" "$HOME/.codex/skills"
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

# ── Claude-only: render settings.local.json from template ─────────────
render_settings_local "$claude_settings_local_template" "$HOME/.claude/settings.local.json"
