#!/usr/bin/env bash
# sync-agents.sh — Populate ~/.claude/agents/ from skills that should
# also be available as Claude Code agents.
#
# Mappings are inline below. Add a new entry to AGENTS array to bridge
# another skill. No external manifest needed.
#
# Idempotent — safe to run repeatedly. Only overwrites files it manages
# (marked with a sentinel in the frontmatter).

set -euo pipefail

SKILLS_DIR="$HOME/.fractal-ai/skills"
SKILLS_DIR_ALT="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"

# ── Agent definitions ────────────────────────────────────────────────
# Format: "skill|model|tools|description"
AGENTS=(
  "code-reviewer|opus|Read, Grep, Glob, Bash|Skeptical code review that catches architectural smells, layering violations, and obviously-wrong code. Runs pissed off — surfaces every borderline smell."
)
# ─────────────────────────────────────────────────────────────────────

mkdir -p "$AGENTS_DIR"

for entry in "${AGENTS[@]}"; do
  IFS='|' read -r skill model tools description <<< "$entry"

  skill_file="$SKILLS_DIR/$skill/SKILL.md"
  if [[ ! -f "$skill_file" ]]; then
    skill_file="$SKILLS_DIR_ALT/$skill/SKILL.md"
    if [[ ! -f "$skill_file" ]]; then
      echo "WARN: skill '$skill' not found, skipping"
      continue
    fi
  fi

  agent_file="$AGENTS_DIR/$skill.md"

  # Strip the skill's own YAML frontmatter (lines 1-N between --- delimiters)
  # to avoid double-frontmatter in the output.
  skill_body=$(awk '
    BEGIN { in_fm=0; fm_done=0 }
    /^---$/ && !fm_done { in_fm = !in_fm; if (!in_fm) { fm_done=1 }; next }
    fm_done { print }
  ' "$skill_file")

  cat > "$agent_file" <<AGENT_EOF
---
name: $skill
model: $model
managed_by: fractal-ai/sync-agents
description: >-
  $description
tools: $tools
---

$skill_body
AGENT_EOF

  echo "Synced: $skill -> $agent_file"
done

echo "Agent sync complete."
