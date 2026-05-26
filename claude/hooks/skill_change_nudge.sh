#!/usr/bin/env bash
# skill_change_nudge.sh — PostToolUse hook for Edit/Write
# Detects when a skill file was modified and reminds the agent to
# read ~/.fractal-ai conventions (commit+push after every change).

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.toolResult.file_path // .tool_input.file_path // ""')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

case "$FILE_PATH" in
  */skills/*/SKILL.md|*/skills/*/search.sh|*/skills/*/scripts/*)
    cat <<'HOOK'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "notification": "You just modified a skill file. Skills are sourced from ~/.fractal-ai — read that repo's CLAUDE.md (which re-exports AGENTS.md) NOW if you haven't already this session. Key convention: push frequently after every coherent skill change. Stage, commit atomically, and `git push` from ~/.fractal-ai promptly. Do not let skill changes sit uncommitted."
  }
}
HOOK
    ;;
esac
