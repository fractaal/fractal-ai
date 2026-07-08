#!/usr/bin/env bash
# launch-agent.sh --cmd <agent-cmd> [--dir <path>] [--name <window-name>]
#                 [--boot-wait S] [--ready <regex>] [--here]
#                 [--no-subagent-label]
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
#   --no-subagent-label
#                do not add PI_IS_SUBAGENT=1 for Pi commands. By default,
#                launching `pi` through this worker helper tags the child Pi
#                session so Pi's auto-renamer prefixes its session name with
#                [subagent].
#
# Prints ONLY the pane id to stdout, so the caller can capture it:
#     PANE=$(launch-agent.sh --cmd pi --dir ~/repo --name pi-impl)
# All diagnostics go to stderr.
#
# Exit: 0 ok · 1 not inside tmux · 2 bad args.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CMD=""; DIR="$PWD"; NAME="agent"; BOOT_WAIT=8; READY=""; HERE=0; NO_SUBAGENT_LABEL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cmd)       CMD="$2"; shift 2 ;;
    --dir)       DIR="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    --boot-wait) BOOT_WAIT="$2"; shift 2 ;;
    --ready)     READY="$2"; shift 2 ;;
    --here)      HERE=1; shift ;;
    --no-subagent-label) NO_SUBAGENT_LABEL=1; shift ;;
    *) echo "launch-agent: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CMD" ]]; then
  echo "usage: launch-agent.sh --cmd <agent-cmd> [--dir <path>] [--name <window-name>] [--boot-wait S] [--ready <regex>] [--here] [--no-subagent-label]" >&2
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

should_tag_pi_child() {
  local rest="$CMD" word base
  while [[ "$rest" =~ ^[[:space:]]*([^[:space:]]+)([[:space:]]+(.*)|$) ]]; do
    word="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[3]:-}"
    case "$word" in
      env|command|exec|*=*) continue ;;
    esac
    base="${word##*/}"
    [[ "$base" == "pi" || "$base" == "pi-subagent" ]]
    return
  done
  return 1
}

# Launch the agent CLI in the pane. `launch-agent.sh` is specifically a
# worker/subagent launcher, so Pi children are tagged automatically for Pi's
# session-name annotator. Use --no-subagent-label for the rare intentional
# primary Pi pane.
LAUNCH_CMD="$CMD"
if [[ "$NO_SUBAGENT_LABEL" = 0 ]] && should_tag_pi_child; then
  LAUNCH_CMD="PI_IS_SUBAGENT=1 PI_SESSION_ROLE=subagent PI_SESSION_KIND=subagent $CMD"
  echo "launch-agent: tagging Pi child session as [subagent]" >&2
fi

tmux send-keys -t "$PANE" -l "$LAUNCH_CMD"
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
