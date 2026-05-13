#!/usr/bin/env bash
# Apply a rename / status flip / confirm to a Claude Code session.
#
# Three modes, dispatched by the third argument:
#
#   1. Full rename — pass the new name verbatim. Replaces the persisted
#      title:
#        apply-session-rename.sh <reg> <tx> '[Complete] Aria dream rename'
#
#   2. Confirm — current name still fits, just reset the cumulative-turn
#      counter so the auto-rename hook doesn't ask again for another N
#      turns. Skips the JSONL append (no transcript noise from no-op acks):
#        apply-session-rename.sh <reg> <tx> --confirm
#
#   3. Status flip — replace just the `[In Progress|Blocked|Complete]`
#      bracket prefix on the existing bare name. `none` strips an existing
#      prefix:
#        apply-session-rename.sh <reg> <tx> --status Complete
#        apply-session-rename.sh <reg> <tx> --status none
#
# All three persist via the same `custom-title` / `agent-name` JSONL
# records that the built-in `/rename` slash command writes (full rename +
# status flip do; --confirm only resets state), and all three reset the
# auto-rename hook's cumulative-turn counter via the shared state file.
#
# Designed to be invoked by an agent after the auto-rename Stop hook
# fires. Lives in its own script (rather than inlined in the hook's
# instruction) so Ben can allowlist it once via settings.json's
# permissions and the agent doesn't have to re-confirm every rename.

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage:
  $(basename "$0") <registry-file> <transcript-path> '<new-name>'
  $(basename "$0") <registry-file> <transcript-path> --confirm
  $(basename "$0") <registry-file> <transcript-path> --status <In Progress|Blocked|Complete|none>
  $(basename "$0") --help
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 3 ]]; then
  usage
  exit 2
fi

registry_file="$1"
transcript_path="$2"
shift 2

# ---- Mode dispatch ----------------------------------------------------------
# Default mode is "rename" with the new name in $1. `--confirm` and
# `--status` are explicit flags; anything else becomes the new name.
mode="rename"
new_name=""
new_status=""

if [[ "${1:-}" == "--confirm" ]]; then
  if [[ $# -ne 1 ]]; then
    echo "error: --confirm takes no additional arguments" >&2
    usage
    exit 2
  fi
  mode="confirm"
elif [[ "${1:-}" == "--status" ]]; then
  if [[ $# -ne 2 ]]; then
    echo "error: --status requires exactly one value (one of: 'In Progress', 'Blocked', 'Complete', 'none')" >&2
    usage
    exit 2
  fi
  mode="status"
  new_status="$2"
else
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi
  new_name="$1"
fi

# ---- Transcript / sessionId discovery (shared across all modes) -------------
if [[ ! -f "$transcript_path" ]]; then
  echo "error: transcript not found: $transcript_path" >&2
  exit 1
fi

# Note the `|| true` on the pipe: jq writes one match then head exits,
# which sends SIGPIPE back to jq → exit 141 → set -o pipefail would abort.
# We absorb the SIGPIPE because the captured value is already complete.
session_id=$(jq -r 'select(.sessionId != null) | .sessionId' "$transcript_path" 2>/dev/null | head -n1 || true)
if [[ -z "$session_id" ]]; then
  echo "error: could not extract sessionId from transcript $transcript_path" >&2
  exit 1
fi

# Read prior name from the JSONL (last custom-title record). Used for the
# log line in all modes, AND as the source-of-truth for `--confirm` and
# `--status` (both compose against the existing persisted name, not the
# registry's transient runtime cache).
prior_name=$(jq -r 'select(.type == "custom-title") | .customTitle' "$transcript_path" 2>/dev/null | tail -1)

# ---- Helpers for --confirm / --status ---------------------------------------

# Mirrors the hook's `is_bare_name` so we can reject `--confirm` /
# `--status` when the current persisted name still looks like a UUID,
# numeric ID, or sessionId fragment. Otherwise those flags would silently
# "succeed" while leaving the session with a meaningless title, and the
# next stop would just re-fire the bare-id branch — a confusing loop.
is_bare_name_local() {
  local name="$1"
  local sid="$2"
  [[ -z "$name" ]] && return 0
  [[ "$name" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && return 0
  [[ "$name" =~ ^[0-9a-f]{6,32}$ ]] && return 0
  [[ "$name" =~ ^[0-9]{4,}$ ]] && return 0
  [[ "${sid:0:8}" == "$name" ]] && return 0
  [[ "$sid" == "$name" ]] && return 0
  return 1
}

# Strip a known `[In Progress] / [Blocked] / [Complete] ` prefix. Used by
# --status so flipping the prefix doesn't accumulate (avoids
# `[Blocked] [Complete] foo`). Case-sensitive on the rendered form to
# match the prompt convention; unknown bracketed prefixes (like
# `[Discussion]`) pass through as part of the bare name.
strip_known_prefix() {
  local name="$1"
  if [[ "$name" =~ ^\[(In\ Progress|Blocked|Complete)\][[:space:]]+(.+)$ ]]; then
    echo "${BASH_REMATCH[2]}"
  else
    echo "$name"
  fi
}

# ---- Mode-specific composition ----------------------------------------------
case "$mode" in
  confirm)
    if is_bare_name_local "$prior_name" "$session_id"; then
      echo "error: --confirm rejected — current name '${prior_name:-(empty)}' looks like a bare ID. Pick a real name first." >&2
      exit 1
    fi
    new_name="$prior_name"
    ;;
  status)
    if is_bare_name_local "$prior_name" "$session_id"; then
      echo "error: --status rejected — current name '${prior_name:-(empty)}' looks like a bare ID. Pick a real name first." >&2
      exit 1
    fi
    bare="$(strip_known_prefix "$prior_name")"
    case "$new_status" in
      "In Progress") new_name="[In Progress] $bare" ;;
      "Blocked")     new_name="[Blocked] $bare" ;;
      "Complete")    new_name="[Complete] $bare" ;;
      "none")        new_name="$bare" ;;
      *)
        echo "error: --status value must be one of: 'In Progress', 'Blocked', 'Complete', 'none' (got '$new_status')" >&2
        exit 1
        ;;
    esac
    ;;
  rename)
    : # new_name already set from $1
    ;;
esac

# ---- Shared validation on the resolved new_name -----------------------------
# Light validation:
#   - 1-100 chars (matches Discord thread name cap; comfortable for the
#     session-list display)
#   - no control characters (newlines/tabs/etc would break the JSONL and
#     the registry display)
#   - no leading/trailing whitespace (cosmetic — Discord normalizes these
#     anyway, but we don't want them in the JSONL either)
# Title-case names with brackets and spaces are allowed (e.g.
# `[Complete] Aria dream-thread-rename`) per the new convention; the old
# strict kebab regex was a historical artifact from when names had to be
# grep-safe identifiers.
if (( ${#new_name} < 1 || ${#new_name} > 100 )); then
  echo "error: name length must be 1-100 chars (got ${#new_name})" >&2
  exit 1
fi
if [[ "$new_name" =~ [[:cntrl:]] ]]; then
  echo "error: name must not contain control characters (newlines, tabs, etc)" >&2
  exit 1
fi
if [[ "$new_name" =~ ^[[:space:]] || "$new_name" =~ [[:space:]]$ ]]; then
  echo "error: name must not have leading or trailing whitespace" >&2
  exit 1
fi

prior_display="${prior_name:-(unset)}"

# ---- Persist (skipped for --confirm) ----------------------------------------
if [[ "$mode" == "confirm" ]]; then
  # No JSONL append, no registry write — the name didn't change. Just the
  # state-file reset below.
  echo "confirmed: '$prior_display' (no rename; cumulative-turn counter reset)"
else
  # Append the two records to the session JSONL — this is the persistent
  # store that survives `claude --resume`.
  {
    jq -nc --arg n "$new_name" --arg sid "$session_id" \
      '{type:"custom-title", customTitle:$n, sessionId:$sid}'
    jq -nc --arg n "$new_name" --arg sid "$session_id" \
      '{type:"agent-name", agentName:$n, sessionId:$sid}'
  } >> "$transcript_path"

  # Update the runtime registry too (best-effort — file may be absent if
  # claude is no longer running this PID). When present, this updates the
  # live CLI's statusline display without waiting for a reload.
  if [[ -f "$registry_file" ]] && jq -e '.sessionId and .pid' "$registry_file" >/dev/null 2>&1; then
    jq --arg n "$new_name" '.name = $n' "$registry_file" > "$registry_file.tmp" \
      && mv "$registry_file.tmp" "$registry_file"
    echo "renamed: '$prior_display' -> '$new_name' (transcript + registry)"
  else
    echo "renamed: '$prior_display' -> '$new_name' (transcript only — registry not present)"
  fi
fi

# ---- State reset (all modes) ------------------------------------------------
# Reset auto-rename hook state regardless of mode — confirm needs this
# even without a JSONL write, otherwise the hook's "name didn't change →
# no state refresh" branch would leave the cumulative counter unchanged
# and the confirm-loop bug returns.
state_file="$HOME/.claude/state/auto-rename.json"
mkdir -p "$(dirname "$state_file")"
[[ -f "$state_file" ]] || echo '{}' > "$state_file"
user_turns=$(grep -c '"type":"user"' "$transcript_path" 2>/dev/null || echo 0)
jq --arg sid "$session_id" --arg n "$new_name" --argjson t "$user_turns" \
   '.[$sid] = {lastSeenName: $n, lastSeenNameAtTurn: $t}' \
   "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
