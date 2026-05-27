#!/usr/bin/env bash
# Project Stop hook (fractal-ai): enforce AGENTS.md's "push frequently, clean
# working tree + in-sync origin/main is the default posture" rule
# deterministically — Claude can't ignore a hook the way it can ignore a
# CLAUDE.md instruction.
#
# Blocks Stop when:
#   - the working tree has modified, staged, or untracked files; OR
#   - HEAD is ahead of its upstream by >=1 commit.
#
# Bypass: include "#wip", "#hold-commit", or "#nocommit" in the MOST RECENT
# user message and the next Stop passes through (one-shot — the token must
# be reaffirmed in the next user turn to hold longer).
#
# Reads the standard Claude Code Stop-hook JSON on stdin, emits
# {"decision":"block","reason":"..."} when blocking, else exits 0.

set -uo pipefail

input=$(cat 2>/dev/null || true)
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi
cd "$REPO_ROOT"

# ── Bypass: check most recent user message for the sentinel token ────────────
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  last_user=$(jq -r '
    select(.type == "user")
    | select((.isMeta // false) | not)
    | select((.isSidechain // false) | not)
    | (.message.content // "")
    | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end
  ' "$transcript_path" 2>/dev/null | awk 'NF' | tail -1)

  if printf '%s' "$last_user" | grep -qiE '#(wip|hold-commit|nocommit)([[:space:]]|$)'; then
    exit 0
  fi
fi

# ── Detect dirt ──────────────────────────────────────────────────────────────
dirty_parts=()
git diff --quiet 2>/dev/null || dirty_parts+=("modified")
git diff --cached --quiet 2>/dev/null || dirty_parts+=("staged")
if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
  dirty_parts+=("untracked")
fi

ahead=0
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [[ -n "$upstream" ]]; then
  ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
fi

if [[ ${#dirty_parts[@]} -eq 0 && "$ahead" -eq 0 ]]; then
  exit 0
fi

# ── Build the report ─────────────────────────────────────────────────────────
status_block=$(git status --short 2>/dev/null | head -30 || true)
ahead_line=""
if [[ "$ahead" -gt 0 && -n "$upstream" ]]; then
  ahead_line=$'\n'"$ahead unpushed commit(s) ahead of $upstream:"$'\n'"$(git log --oneline "@{u}..HEAD" 2>/dev/null | head -10)"
fi

summary_parts=()
[[ ${#dirty_parts[@]} -gt 0 ]] && summary_parts+=("dirty working tree (${dirty_parts[*]})")
[[ "$ahead" -gt 0 ]] && summary_parts+=("$ahead unpushed commit(s)")
IFS=' + '; summary="${summary_parts[*]}"; IFS=$' \t\n'

reason=$(cat <<EOF
fractal-ai standing rule (AGENTS.md): "Push frequently — ideally after every coherent change. […] The default posture is a clean working tree and an in-sync origin/main."

This Stop is blocked because: $summary.

  git status --short:
$status_block
$ahead_line

Resolve before stopping:

  1. If the changes are a coherent unit → commit atomically (use the git-commit-convention skill for staging discipline + message format) and \`git push\`. Multiple coherent units → multiple commits. Do not bundle unrelated changes.

  2. If part of the dirt is pre-existing and not yours to clean up in this session → say so to Ben explicitly and ask whether he wants you to address it, leave it, or bypass.

  3. If the work is genuinely WIP that must stay loose → tell Ben, and have him include "#wip" (or #hold-commit / #nocommit) in his next prompt. The next Stop will then pass through.

Do not chain unrelated new work after committing — once the tree is clean and pushed, stop normally.
EOF
)

jq -n --arg reason "$reason" '{"decision":"block","reason":$reason}'
