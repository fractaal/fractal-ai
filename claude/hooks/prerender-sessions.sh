#!/usr/bin/env bash
# Stop hook: refresh prerendered session Markdown files in the Obsidian vault
# so /read-agent-sessions search stays current without manual re-runs.
#
# Runs `read-agent-sessions prerender` in the background and returns
# immediately so Claude's Stop event isn't delayed. A non-blocking flock
# guards against concurrent runs from clobbering the prerender manifest:
# if another run is already in flight, this invocation simply drops — the
# next Stop will catch up.
#
# Output is appended to ~/.claude/state/prerender-sessions.log for debug.

set -euo pipefail

STATE_DIR="$HOME/.claude/state"
LOG_FILE="$STATE_DIR/prerender-sessions.log"
LOCK_FILE="$STATE_DIR/prerender-sessions.lock"
RAS="$HOME/.fractal-ai/skills/read-agent-sessions/scripts/read-agent-sessions"

mkdir -p "$STATE_DIR"

# Drain stdin so the harness doesn't sit on a half-read pipe.
cat >/dev/null 2>&1 || true

[[ -x "$RAS" ]] || exit 0

(
  flock -n 9 || exit 0
  {
    echo "── $(date -Iseconds) Claude Stop hook prerender ──"
    "$RAS" prerender 2>&1 || true
  } >> "$LOG_FILE"
) 9>"$LOCK_FILE" &
disown

exit 0
