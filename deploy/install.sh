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
    mv "$target" "$backup"
  fi

  mkdir -p "$(dirname "$target")"
  ln -s "$source" "$target"
}

agents_source="$FRACTAL_AI_HOME/AGENTS.md"
skills_source="$FRACTAL_AI_HOME/skills"

if [[ -f "$agents_source" ]]; then
  link_item "$agents_source" "$HOME/.codex/AGENTS.md"
  link_item "$agents_source" "$HOME/.opencode/AGENTS.md"
fi

if [[ -d "$skills_source" ]]; then
  link_item "$skills_source" "$HOME/.codex/skills"
  link_item "$skills_source" "$HOME/.opencode/skills"
fi
