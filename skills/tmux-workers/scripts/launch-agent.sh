#!/usr/bin/env bash
# launch-agent.sh --cmd <agent-cmd> [--dir <path>] [--name <window-name>]
#                 [--boot-wait S] [--ready <regex>] [--here]
#
# Open an interactive agent CLI in its own tmux window and return the pane id.
#
# The window is a shared surface: you drive it with send-keys-then-enter.sh,
# and the human can switch to the window and type into it too. That is the
# whole point of running the agent interactively rather than headless.
#
#   --cmd        the agent CLI to launch, e.g. 'pi', 'codex', 'claude'.
#               Required.
#   --dir        working directory for the window. Default: current dir.
#   --name       tmux window name — pick something findable, e.g. 'pi-gw-impl'.
#                Default: 'agent'.
#   --boot-wait  seconds to wait for the CLI to come up before returning.
#                Default 8. Ignored when --ready is given.
#   --ready      extended-regex that, once visible in the pane, means the CLI
#                is up and ready for input. Polled instead of --boot-wait.
#   --here       split the CURRENT window instead of opening a new one. Use
#                when you want the agent visible side-by-side immediately.
#
# Prints ONLY the pane id to stdout, so the caller can capture it:
#     PANE=$(launch-agent.sh --cmd pi --dir ~/repo --name pi-impl)
# All diagnostics go to stderr.
#
# Exit: 0 ok · 1 not inside tmux · 2 bad args.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CMD=""; DIR="$PWD"; NAME="agent"; BOOT_WAIT=8; READY=""; HERE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cmd)       CMD="$2"; shift 2 ;;
    --dir)       DIR="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    --boot-wait) BOOT_WAIT="$2"; shift 2 ;;
    --ready)     READY="$2"; shift 2 ;;
    --here)      HERE=1; shift ;;
    *) echo "launch-agent: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CMD" ]]; then
  echo "usage: launch-agent.sh --cmd <agent-cmd> [--dir <path>] [--name <window-name>] [--boot-wait S] [--ready <regex>] [--here]" >&2
  exit 2
fi
if [[ -z "${TMUX:-}" ]]; then
  echo "launch-agent: not inside a tmux session" >&2
  exit 1
fi

if [[ "$HERE" = 1 ]]; then
  PANE=$(tmux split-window -h -d -P -F '#{pane_id}' -c "$DIR")
else
  PANE=$(tmux new-window -d -P -F '#{pane_id}' -c "$DIR" -n "$NAME")
fi
echo "launch-agent: window '$NAME' pane $PANE (dir: $DIR)" >&2

# Launch the agent CLI in the pane.
tmux send-keys -t "$PANE" -l "$CMD"
tmux send-keys -t "$PANE" Enter

# Wait for it to come up.
if [[ -n "$READY" ]]; then
  if "$SCRIPT_DIR/wait-for-text.sh" "$PANE" "$READY" --timeout 60 --quiet; then
    echo "launch-agent: '$CMD' is ready" >&2
  else
    echo "launch-agent: WARNING — '$READY' not seen within 60s; pane may still be starting" >&2
  fi
else
  sleep "$BOOT_WAIT"
  echo "launch-agent: waited ${BOOT_WAIT}s for '$CMD' to boot" >&2
fi

# stdout: just the pane id.
echo "$PANE"
