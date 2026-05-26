#!/usr/bin/env bash
# wait-for-text.sh <pane> <pattern> [--gone] [--stable N] [--timeout S] [--interval S] [--quiet]
#
# Block until an extended-regex PATTERN appears in (or, with --gone, disappears
# from) a tmux pane's visible content.
#
# This is how you wait on an interactive agent CLI. The agent shows a "busy"
# marker while it works, so:
#     wait-for-text.sh %51 'Working\.\.\.' --gone
# blocks until that marker is gone — i.e. until the agent finishes its turn.
# (For the agent case, prefer the wait-for.sh wrapper, which knows the busy
# marker for each CLI — it reads as "wait-for pi", "wait-for codex", etc.)
#
#   --gone        invert: wait for PATTERN to be ABSENT, not present.
#   --stable N    require the condition to hold for N consecutive polls before
#                 returning — debounce against a redraw/scroll blip flipping
#                 the result for a single tick. Default 2.
#   --timeout S   give up after S seconds. Default 600.
#   --interval S  seconds between polls. Default 3.
#   --quiet       no status output; just the exit code.
#
# Exit: 0 condition met (stably) · 1 timeout · 2 pane gone or bad args.
#
# Run this asynchronously so the blocking wait does not burn your context:
# under Claude Code's Monitor tool, or Pi's async monitor tooling. On an agent
# with neither (Codex, Gemini), run it as a blocking background job and check
# the exit code.

set -uo pipefail

PANE=""; PATTERN=""; GONE=0; STABLE=2; TIMEOUT=600; INTERVAL=3; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gone)     GONE=1; shift ;;
    --stable)   STABLE="$2"; shift 2 ;;
    --timeout)  TIMEOUT="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --quiet)    QUIET=1; shift ;;
    -*)         echo "wait-for-text: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$PANE" ]]; then PANE="$1"
      elif [[ -z "$PATTERN" ]]; then PATTERN="$1"
      else echo "wait-for-text: unexpected arg: $1" >&2; exit 2; fi
      shift ;;
  esac
done

if [[ -z "$PANE" || -z "$PATTERN" ]]; then
  echo "usage: wait-for-text.sh <pane> <pattern> [--gone] [--stable N] [--timeout S] [--interval S] [--quiet]" >&2
  exit 2
fi

say() { [[ "$QUIET" = 1 ]] || echo "$@"; }

want=$([[ "$GONE" = 1 ]] && echo absent || echo present)
deadline=$(( $(date +%s) + TIMEOUT ))
hits=0

say "wait-for-text: pane $PANE — waiting for /$PATTERN/ to be $want (stable x$STABLE, timeout ${TIMEOUT}s)"

while true; do
  if (( $(date +%s) >= deadline )); then
    say "wait-for-text: TIMEOUT after ${TIMEOUT}s — /$PATTERN/ never became $want"
    exit 1
  fi

  cap=$(tmux capture-pane -p -t "$PANE" 2>/dev/null) || { say "wait-for-text: pane $PANE is GONE"; exit 2; }

  if grep -qE "$PATTERN" <<<"$cap"; then present=1; else present=0; fi

  if { [[ "$GONE" = 1 && "$present" = 0 ]] || [[ "$GONE" = 0 && "$present" = 1 ]]; }; then
    hits=$(( hits + 1 ))
    if (( hits >= STABLE )); then
      say "wait-for-text: /$PATTERN/ is $want (held ${hits}x) — done"
      exit 0
    fi
  else
    hits=0
  fi

  sleep "$INTERVAL"
done
