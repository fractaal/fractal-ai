#!/usr/bin/env bash
# poll_pane_done.sh <pane_id> [--timeout <seconds>] [--interval <seconds>] [--prompt <pattern>]
#
# Polls a tmux pane until the shell prompt reappears (indicating the foreground
# process has exited). Exits 0 on success, 1 on timeout.
#
# Usage:
#   poll_pane_done.sh %12
#   poll_pane_done.sh %12 --timeout 120 --interval 2
#   poll_pane_done.sh %12 --prompt "\\$"

set -euo pipefail

PANE=""
TIMEOUT=120
INTERVAL=2
# Match common prompt endings: $, %, ❯, ➜ — at or near end of a line
PROMPT_PATTERN='(\$|%|❯|➜)\s*$'

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --prompt)   PROMPT_PATTERN="$2"; shift 2 ;;
    *)
      if [[ -z "$PANE" ]]; then
        PANE="$1"; shift
      else
        echo "Unknown argument: $1" >&2; exit 2
      fi
      ;;
  esac
done

if [[ -z "$PANE" ]]; then
  echo "Usage: $0 <pane_id> [--timeout N] [--interval N] [--prompt PATTERN]" >&2
  exit 2
fi

deadline=$(( $(date +%s) + TIMEOUT ))

# Wait briefly for the command to actually start (avoid seeing the prompt from
# before the command was sent)
sleep "$INTERVAL"

while true; do
  now=$(date +%s)
  if (( now >= deadline )); then
    echo "poll_pane_done: TIMEOUT after ${TIMEOUT}s waiting for pane $PANE" >&2
    exit 1
  fi

  # Capture the last 5 lines of the pane (visible buffer tail)
  output=$(tmux capture-pane -p -t "$PANE" 2>/dev/null | tail -5)

  if echo "$output" | grep -qE "$PROMPT_PATTERN"; then
    exit 0
  fi

  sleep "$INTERVAL"
done
