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

# Warn if ~/.claude/settings.local.json still contains keys that are now owned
# by the canonical (user-global) settings.json. The previous layout rendered
# `hooks` and `statusLine` into settings.local.json, but that file is cwd-
# ancestry-scoped (only loads when cwd is under $HOME), so those entries
# silently failed for sessions outside $HOME. Both keys now live in the
# canonical settings.json. Stale copies in settings.local.json cause hook
# duplication (Claude Code merges arrays across precedence scopes; the
# string-difference between `~/...` and `$HOME-substituted/...` defeats
# dedup), so leaving them risks every Stop/Edit firing the gates twice.
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

# ── Shared sources (portable across all AI tools) ─────────────────────
deployed_instructions_source="$FRACTAL_AI_HOME/DEPLOYED-INSTRUCTIONS.md"
skills_source="$FRACTAL_AI_HOME/skills"

# ── Claude-specific sources ───────────────────────────────────────────
claude_settings_source="$FRACTAL_AI_HOME/claude/settings.json"
claude_hooks_source="$FRACTAL_AI_HOME/claude/hooks"
claude_statusline_source="$FRACTAL_AI_HOME/claude/statusline-command.sh"

# ── Pi-specific sources ───────────────────────────────────────────────
pi_extensions_source="$FRACTAL_AI_HOME/pi/extensions"

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

# ── Pi-only: extensions ───────────────────────────────────────────────
if [[ -d "$pi_extensions_source" ]]; then
  link_item "$pi_extensions_source" "$HOME/.pi/agent/extensions"
fi

warn_stale_settings_local
