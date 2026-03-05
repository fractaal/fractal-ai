#!/usr/bin/env bash
# spawn_agent.sh --prompt <text> --out <file> [--timeout <seconds>] [--split <h|v>]
#
# Full lifecycle for a single Claude subagent worker in a tmux pane:
#   spawn pane -> send claude command -> poll until done -> exit 0
#
# Output is written to --out by the agent itself (prompted to do so).
# Caller reads --out after this script exits.
#
# Usage:
#   spawn_agent.sh --prompt "Summarize foo.txt" --out /tmp/summary.txt
#   spawn_agent.sh --prompt "..." --out /tmp/r.txt --timeout 300 --split v

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROMPT=""
OUTFILE=""
TIMEOUT=180
SPLIT="h"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)  PROMPT="$2"; shift 2 ;;
    --out)     OUTFILE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --split)   SPLIT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROMPT" || -z "$OUTFILE" ]]; then
  echo "Usage: $0 --prompt <text> --out <file> [--timeout N] [--split h|v]" >&2
  exit 2
fi

if [[ -z "${TMUX:-}" ]]; then
  echo "spawn_agent.sh: not inside a tmux session" >&2
  exit 1
fi

# Augment prompt: instruct agent to write result to the output file
FULL_PROMPT="${PROMPT}

Write your complete final answer to: ${OUTFILE}
Do not write anything to that file until you have your complete answer.
Do not write anything after writing to that file."

# Spawn pane (detached — don't steal focus)
PANE=$(tmux split-window "-${SPLIT}" -d -P -F "#{pane_id}")

# Escape single quotes in prompt for shell embedding
ESCAPED=$(printf '%s' "$FULL_PROMPT" | sed "s/'/'\\\\''/g")

# Launch claude in the pane; redirect stderr to stdout so all output goes to file
tmux send-keys -t "$PANE" "claude -p '${ESCAPED}' > '${OUTFILE}' 2>&1" Enter

# Poll until done, then clean up pane
"${SCRIPT_DIR}/poll_pane_done.sh" "$PANE" --timeout "$TIMEOUT"
STATUS=$?

tmux kill-pane -t "$PANE" 2>/dev/null || true

exit $STATUS
