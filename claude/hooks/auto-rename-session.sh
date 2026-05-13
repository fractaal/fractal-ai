#!/usr/bin/env bash
# Stop hook: re-engages the agent to give the session a meaningful name —
# optionally prefixed with `[In Progress] / [Blocked] / [Complete]` to flag
# the work's current state — and re-renames as the session evolves.
#
# Triggers:
#   1. IMMEDIATE — session name is "bare" (empty, UUID, sessionId prefix, or
#      pure hex/numeric ID). Fire on the very first stop, even with 0 turns.
#   2. CUMULATIVE — name is meaningful but the session has accumulated
#      $MIN_TURNS_BETWEEN_RENAMES (default 50) user turns since the last
#      observed rename. Fire so the name can track topic drift.
#
# Mechanism: returns `{"decision":"block","reason":"..."}` per Claude Code's
# Stop hook protocol, which injects the reason as a system reminder and
# re-runs the agent loop. The agent (full context, not a side LLM) picks a
# name and runs the bash command we hand back to persist it.
#
# State lives at ~/.claude/state/auto-rename.json, keyed by sessionId:
#   {"<sid>": {"lastSeenName": "...", "lastSeenNameAtTurn": N}}
# Lives outside ~/.claude/hooks/ so it is not nested inside the symlinked
# fractal-ai source tree (machine-local runtime data, not source-of-truth).
# We auto-detect renames by comparing current name to lastSeenName, so the
# agent does NOT have to update state manually — keeps the rename-instruction
# minimal.

set -euo pipefail

STATE_FILE="$HOME/.claude/state/auto-rename.json"
MIN_TURNS_BETWEEN_RENAMES="${AUTO_RENAME_MIN_TURNS:-50}"
mkdir -p "$(dirname "$STATE_FILE")"
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

# ---- Read hook input from stdin ---------------------------------------------
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

if [[ -z "$session_id" || -z "$transcript_path" ]]; then
  exit 0
fi

# ---- Locate the session registry file by sessionId --------------------------
registry_file=""
for f in ~/.claude/sessions/*.json; do
  [[ -f "$f" ]] || continue
  if jq -e --arg sid "$session_id" '.sessionId == $sid' "$f" >/dev/null 2>&1; then
    registry_file="$f"
    break
  fi
done

if [[ -z "$registry_file" ]]; then
  exit 0
fi

# The PERSISTENT name lives in the session JSONL as `custom-title` records
# (the built-in /rename slash command writes them; we mirror that). The
# registry file's `name` is just a transient runtime cache that may be empty
# on resume even when the session was previously renamed. Prefer the JSONL
# as the source of truth; fall back to the registry only when no
# custom-title record exists.
persistent_name=$(jq -r 'select(.type == "custom-title") | .customTitle' "$transcript_path" 2>/dev/null | tail -1)
registry_name=$(jq -r '.name // ""' "$registry_file")
current_name="${persistent_name:-$registry_name}"

user_turns=$(grep -c '"type":"user"' "$transcript_path" 2>/dev/null || echo 0)

# ---- Detect "bare ID" name patterns -----------------------------------------
is_bare_name() {
  local name="$1"
  local sid="$2"
  [[ -z "$name" ]] && return 0                                          # empty
  [[ "$name" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && return 0  # full UUID
  [[ "$name" =~ ^[0-9a-f]{6,32}$ ]] && return 0                         # bare hex run
  [[ "$name" =~ ^[0-9]{4,}$ ]] && return 0                              # bare numeric
  [[ "${sid:0:8}" == "$name" ]] && return 0                             # sessionId prefix
  [[ "$sid" == "$name" ]] && return 0                                   # full sessionId
  return 1
}

# ---- State: detect rename since last fire, then decide trigger --------------
prev_seen_name=$(jq -r --arg sid "$session_id" '.[$sid].lastSeenName // empty' "$STATE_FILE")
prev_seen_at_turn=$(jq -r --arg sid "$session_id" '.[$sid].lastSeenNameAtTurn // 0' "$STATE_FILE")

# If name has changed since we last saw it (someone renamed — auto or manual),
# refresh the state so the cumulative-turn counter starts from this rename.
if [[ "$current_name" != "$prev_seen_name" ]]; then
  jq --arg sid "$session_id" --arg n "$current_name" --argjson t "$user_turns" \
     '.[$sid] = {lastSeenName: $n, lastSeenNameAtTurn: $t}' \
     "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  prev_seen_at_turn="$user_turns"
fi

# ---- Trigger decision -------------------------------------------------------
trigger_reason=""
if is_bare_name "$current_name" "$session_id"; then
  trigger_reason="bare-id"
elif (( user_turns - prev_seen_at_turn >= MIN_TURNS_BETWEEN_RENAMES )); then
  trigger_reason="cumulative-turns"
fi

if [[ -z "$trigger_reason" ]]; then
  exit 0
fi

# ---- Build instruction and emit block ---------------------------------------
case "$trigger_reason" in
  bare-id)
    framing="This session still has a bare/ID-like name (\"$current_name\"). Give it a real one before stopping."
    ;;
  cumulative-turns)
    framing="This session has grown by $((user_turns - prev_seen_at_turn)) user turns since its name was set (currently \"$current_name\"). Re-name it if the focus has shifted, or confirm by writing the same name back."
    ;;
esac

instruction=$(cat <<EOF
Auto-rename hook ($trigger_reason): $framing

Pick a 3-7 word title for this session that reflects its actual focus and outcome — not a generic descriptor. Should still make sense to Ben in 6 weeks when he's scrolling the session list. Lean specific over broad.

Optionally prefix the title with one of these status brackets to flag where the work stands (skip the prefix if no status clearly applies — e.g. session is still in early exploration):

  [In Progress]  — active, mid-thread, loose ends still hanging
  [Blocked]      — waiting on a decision, an external dep, or an open outage
  [Complete]     — the work is done, no follow-up pending

Examples:
  Vertex proxy POSTHOG_KEY wiring
  [In Progress] Hyprland rice overlay bootstrap
  [Complete] Symphony agency UI image-upload retry loop

Persist your decision with ONE of the following — pick whichever fits, no need to retype the existing name if you don't have to:

  # Full rename (use this when the title needs to change).
  bash ~/.claude/hooks/scripts/apply-session-rename.sh '$registry_file' '$transcript_path' 'YOUR-NAME-HERE'

  # Name still fits — just confirm. No-op rename, resets the cumulative-turn counter.
  bash ~/.claude/hooks/scripts/apply-session-rename.sh '$registry_file' '$transcript_path' --confirm

  # Title is fine, only the status changed — flip just the [Bracket] prefix.
  # Valid values: 'In Progress', 'Blocked', 'Complete', or 'none' to drop an existing prefix.
  bash ~/.claude/hooks/scripts/apply-session-rename.sh '$registry_file' '$transcript_path' --status 'Complete'

After it succeeds, stop normally — do not chain additional work. The hook tracks state in $STATE_FILE; the script resets the cumulative-turn counter for you, so you don't need to touch the state file directly.
EOF
)

jq -n --arg reason "$instruction" '{"decision":"block","reason":$reason}'
