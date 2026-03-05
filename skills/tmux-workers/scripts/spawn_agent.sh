#!/usr/bin/env bash
# spawn_agent.sh --prompt <text> [--out <file>] [--agent-cmd <cmd>] [--timeout <seconds>] [--split <h|v>]
#
# Full lifecycle for a single AI subagent worker in a tmux pane:
#   spawn pane -> send agent command -> poll until done -> exit 0
#
# Output is written to --out by the agent itself (prompted to do so).
# Prints the outfile path to stdout so callers can capture it when --out is
# auto-generated via mktemp.
#
# --agent-cmd: command prefix used to invoke the agent. The prompt is passed as
#   the last argument. Defaults to "claude -p". Examples:
#     --agent-cmd "claude -p"   (default)
#     --agent-cmd "codex"
#     --agent-cmd "sgpt"
#
# Usage:
#   spawn_agent.sh --prompt "Summarize foo.txt"
#   OUTFILE=$(spawn_agent.sh --prompt "..." --agent-cmd codex)
#   spawn_agent.sh --prompt "..." --out /tmp/my-result.txt --timeout 300 --split v

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROMPT=""
OUTFILE=""
AGENT_CMD="claude -p"
TIMEOUT=180
SPLIT="h"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)    PROMPT="$2"; shift 2 ;;
    --out)       OUTFILE="$2"; shift 2 ;;
    --agent-cmd) AGENT_CMD="$2"; shift 2 ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    --split)     SPLIT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PROMPT" ]]; then
  echo "Usage: $0 --prompt <text> [--out <file>] [--agent-cmd <cmd>] [--timeout N] [--split h|v]" >&2
  exit 2
fi

if [[ -z "${TMUX:-}" ]]; then
  echo "spawn_agent.sh: not inside a tmux session" >&2
  exit 1
fi

# Auto-generate a unique output file if not provided
if [[ -z "$OUTFILE" ]]; then
  OUTFILE=$(mktemp /tmp/agent-result-XXXXXX.txt)
fi

# Augment prompt: instruct agent to write result to the output file
FULL_PROMPT="${PROMPT}

Write your complete final answer to: ${OUTFILE}
Do not write anything to that file until you have your complete answer.
Do not write anything after writing to that file."

# Write prompt to a temp file — avoids shell-quoting issues with arbitrary text
PROMPT_FILE=$(mktemp /tmp/agent-prompt-XXXXXX.txt)
printf '%s' "$FULL_PROMPT" > "$PROMPT_FILE"

# Spawn pane (detached — don't steal focus)
PANE=$(tmux split-window "-${SPLIT}" -d -P -F "#{pane_id}")

# Feed prompt via file to sidestep escaping entirely.
# Agent reads the prompt via command substitution; cleanup prompt file when done.
tmux send-keys -t "$PANE" \
  "${AGENT_CMD} \"\$(cat '${PROMPT_FILE}')\" > '${OUTFILE}' 2>&1; rm -f '${PROMPT_FILE}'" \
  Enter

# Poll until done, then clean up pane
"${SCRIPT_DIR}/poll_pane_done.sh" "$PANE" --timeout "$TIMEOUT"
STATUS=$?

tmux kill-pane -t "$PANE" 2>/dev/null || true
rm -f "$PROMPT_FILE" 2>/dev/null || true

# Print the output file path so callers can capture it
echo "$OUTFILE"

exit $STATUS
