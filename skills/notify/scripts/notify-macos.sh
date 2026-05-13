#!/usr/bin/env bash
# notify.sh — macOS attention-grabber via osascript
#
# Usage:
#   notify.sh "Your build finished!"
#   notify.sh -m "Done!" -t "CI Result" -s Hero
#   notify.sh -m "Check this" --style notification
#   notify.sh -m "URGENT" --repeat 3
#   notify.sh -m "PROD IS DOWN" --loop -s Basso   # blares until acknowledged
#
# Defaults:
#   --title   "Agent Ping"
#   --sound   Glass
#   --style   dialog  (blocking modal; use "notification" for non-blocking)
#   --repeat  1       (number of times to play the sound)
#   --loop    off     (loop sound infinitely until dialog is dismissed)

set -euo pipefail

MESSAGE=""
TITLE="Agent Ping"
SOUND="Glass"
STYLE="dialog"
REPEAT=1
LOOP=false

# --- parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)  MESSAGE="$2"; shift 2 ;;
    -t|--title)    TITLE="$2"; shift 2 ;;
    -s|--sound)    SOUND="$2"; shift 2 ;;
    --style)       STYLE="$2"; shift 2 ;;
    --repeat)      REPEAT="$2"; shift 2 ;;
    --loop)        LOOP=true; shift ;;
    -h|--help)
      echo "Usage: notify.sh -m \"message\" [-t title] [-s sound] [--style dialog|notification] [--repeat N] [--loop]"
      echo ""
      echo "Sounds: Basso Blow Bottle Frog Funk Glass Hero Morse Ping Pop Purr Sosumi Submarine Tink"
      echo ""
      echo "--loop: sound plays on infinite repeat until the dialog is dismissed"
      exit 0
      ;;
    *)
      # positional: treat as message if message is empty
      if [[ -z "$MESSAGE" ]]; then
        MESSAGE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$MESSAGE" ]]; then
  echo "Error: no message provided. Usage: notify.sh -m \"your message\"" >&2
  exit 1
fi

SOUND_FILE="/System/Library/Sounds/${SOUND}.aiff"

if [[ "$LOOP" == true && -f "$SOUND_FILE" ]]; then
  # --- looping sound: blares until dialog is dismissed ---
  (
    while true; do
      afplay "$SOUND_FILE"
    done
  ) &
  LOOP_PID=$!

  # show blocking dialog, then kill the sound loop
  osascript -e "display dialog \"$MESSAGE\" with title \"$TITLE\" buttons {\"OK\"} default button \"OK\" with icon stop"

  kill "$LOOP_PID" 2>/dev/null
  wait "$LOOP_PID" 2>/dev/null || true
  # kill any lingering afplay child process
  pkill -P $$ afplay 2>/dev/null || true
else
  # --- finite sound ---
  if [[ -f "$SOUND_FILE" ]]; then
    for ((i = 0; i < REPEAT; i++)); do
      afplay "$SOUND_FILE" &
      # small gap between repeats so they don't stack into one sound
      if (( i < REPEAT - 1 )); then
        sleep 0.4
      fi
    done
  fi

  # --- show dialog or notification ---
  if [[ "$STYLE" == "notification" ]]; then
    osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"$SOUND\""
  else
    osascript -e "display dialog \"$MESSAGE\" with title \"$TITLE\" buttons {\"OK\"} default button \"OK\" with icon note"
  fi
fi
