#!/usr/bin/env bash
# Apply a new name to a Claude Code session.
#
# Usage:
#   apply-session-rename.sh <registry-file> <transcript-path> <new-name>
#
# Persists the rename across `claude --resume` by mirroring the records that
# the built-in `/rename` slash command appends to the session JSONL:
#
#   {"type":"custom-title","customTitle":"<name>","sessionId":"<sid>"}
#   {"type":"agent-name","agentName":"<name>","sessionId":"<sid>"}
#
# The session registry file (~/.claude/sessions/<pid>.json) is transient —
# Claude Code recreates it on each session launch and reads the persistent
# name from those JSONL records. We update both: registry for the running
# CLI's live display, JSONL for persistence on resume.
#
# Designed to be invoked by an agent after the auto-rename Stop hook fires.
# Lives in its own script (rather than inlined in the hook's instruction) so
# Ben can allowlist it once via settings.json's permissions and the agent
# doesn't have to re-confirm every rename.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $(basename "$0") <registry-file> <transcript-path> <new-name>" >&2
  exit 2
fi

registry_file="$1"
transcript_path="$2"
new_name="$3"

# Light validation on the new name — kebab-case-ish, 1-80 chars.
if ! [[ "$new_name" =~ ^[a-z0-9][a-z0-9-]{0,78}[a-z0-9]$ || "$new_name" =~ ^[a-z0-9]$ ]]; then
  echo "error: name '$new_name' must be kebab-case (lowercase letters, digits, hyphens; cannot start/end with hyphen; 1-80 chars)" >&2
  exit 1
fi

if [[ ! -f "$transcript_path" ]]; then
  echo "error: transcript not found: $transcript_path" >&2
  exit 1
fi

# Discover the sessionId from the transcript itself — first line usually has
# it. Note the `|| true` on the pipe: jq writes one match then head exits,
# which sends SIGPIPE back to jq → exit 141 → set -o pipefail would abort.
# We absorb the SIGPIPE because the captured value is already complete.
session_id=$(jq -r 'select(.sessionId != null) | .sessionId' "$transcript_path" 2>/dev/null | head -n1 || true)
if [[ -z "$session_id" ]]; then
  echo "error: could not extract sessionId from transcript $transcript_path" >&2
  exit 1
fi

# Read prior name from the JSONL (last custom-title record) for logging
prior_name=$(jq -r 'select(.type == "custom-title") | .customTitle' "$transcript_path" 2>/dev/null | tail -1)
prior_name="${prior_name:-(unset)}"

# Append the two records to the session JSONL — this is the persistent store.
{
  jq -nc --arg n "$new_name" --arg sid "$session_id" \
    '{type:"custom-title", customTitle:$n, sessionId:$sid}'
  jq -nc --arg n "$new_name" --arg sid "$session_id" \
    '{type:"agent-name", agentName:$n, sessionId:$sid}'
} >> "$transcript_path"

# Update the runtime registry too (best-effort — file may be absent if claude
# is no longer running this PID). When present, this updates the live CLI's
# statusline display without waiting for a reload.
if [[ -f "$registry_file" ]] && jq -e '.sessionId and .pid' "$registry_file" >/dev/null 2>&1; then
  jq --arg n "$new_name" '.name = $n' "$registry_file" > "$registry_file.tmp" \
    && mv "$registry_file.tmp" "$registry_file"
  echo "renamed: '$prior_name' -> '$new_name' (transcript + registry)"
else
  echo "renamed: '$prior_name' -> '$new_name' (transcript only — registry not present)"
fi
