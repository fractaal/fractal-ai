#!/usr/bin/env bash
# fanout.sh --tasks <file> --outdir <dir> [--timeout <seconds>] [--max-parallel <n>]
#
# Parallel fan-out: reads tasks from a file (one task per line), spawns one
# Claude subagent pane per task (up to --max-parallel at once), waits for all,
# and writes results to <outdir>/result-N.txt.
#
# Tasks file format: one plain-text prompt per line.
#
# Usage:
#   fanout.sh --tasks tasks.txt --outdir /tmp/fanout-results
#   fanout.sh --tasks tasks.txt --outdir /tmp/r --timeout 240 --max-parallel 4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TASKS_FILE=""
OUTDIR=""
TIMEOUT=180
MAX_PARALLEL=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks)        TASKS_FILE="$2"; shift 2 ;;
    --outdir)       OUTDIR="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --max-parallel) MAX_PARALLEL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TASKS_FILE" || -z "$OUTDIR" ]]; then
  echo "Usage: $0 --tasks <file> --outdir <dir> [--timeout N] [--max-parallel N]" >&2
  exit 2
fi

if [[ -z "${TMUX:-}" ]]; then
  echo "fanout.sh: not inside a tmux session" >&2
  exit 1
fi

mkdir -p "$OUTDIR"

mapfile -t TASKS < "$TASKS_FILE"
TOTAL=${#TASKS[@]}

if [[ $TOTAL -eq 0 ]]; then
  echo "fanout.sh: tasks file is empty" >&2
  exit 1
fi

echo "fanout.sh: spawning $TOTAL tasks (max $MAX_PARALLEL parallel)"

declare -a PANES=()
declare -a OUTFILES=()
ACTIVE=0

cleanup_panes() {
  for P in "${PANES[@]:-}"; do
    tmux kill-pane -t "$P" 2>/dev/null || true
  done
}
trap cleanup_panes EXIT

for i in "${!TASKS[@]}"; do
  PROMPT="${TASKS[$i]}"
  OUTFILE="${OUTDIR}/result-${i}.txt"
  OUTFILES+=("$OUTFILE")

  # Wait if at capacity
  while (( ACTIVE >= MAX_PARALLEL )); do
    sleep 2
    NEW_ACTIVE=0
    STILL_RUNNING=()
    for P in "${PANES[@]}"; do
      # Check if pane still exists
      if tmux list-panes -F "#{pane_id}" | grep -qF "$P"; then
        NEW_ACTIVE=$(( NEW_ACTIVE + 1 ))
        STILL_RUNNING+=("$P")
      fi
    done
    PANES=("${STILL_RUNNING[@]:-}")
    ACTIVE=$NEW_ACTIVE
  done

  FULL_PROMPT="${PROMPT}

Write your complete final answer to: ${OUTFILE}
Do not write anything to that file until you have your complete answer."

  ESCAPED=$(printf '%s' "$FULL_PROMPT" | sed "s/'/'\\\\''/g")
  PANE=$(tmux split-window -h -d -P -F "#{pane_id}")
  tmux send-keys -t "$PANE" "claude -p '${ESCAPED}' > '${OUTFILE}' 2>&1" Enter

  PANES+=("$PANE")
  ACTIVE=$(( ACTIVE + 1 ))
  echo "  spawned task $i -> pane $PANE -> $OUTFILE"
done

# Wait for remaining panes
echo "fanout.sh: waiting for remaining ${#PANES[@]} panes..."
for P in "${PANES[@]:-}"; do
  "${SCRIPT_DIR}/poll_pane_done.sh" "$P" --timeout "$TIMEOUT" || true
  tmux kill-pane -t "$P" 2>/dev/null || true
done

echo "fanout.sh: all tasks complete. Results:"
for i in "${!OUTFILES[@]}"; do
  F="${OUTFILES[$i]}"
  if [[ -f "$F" ]]; then
    echo "  [$i] $F ($(wc -c < "$F") bytes)"
  else
    echo "  [$i] $F MISSING"
  fi
done
