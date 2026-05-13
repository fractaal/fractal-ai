#!/usr/bin/env bash
# notify-linux.sh — Linux attention-grabber.
#
# ALWAYS uses a blocking modal dialog. The passive notify-send path was
# removed intentionally — banners get dismissed/missed too easily and
# Ben needs something he physically has to click through. The OK button
# means "I have ACKNOWLEDGED this, let's talk." It does NOT mean approval
# of any action — agents must wait for an actual response after dismissal.
#
# Mechanics:
#   - dialog: zenity --info (preferred) or kdialog --warningcontinuecancel (fallback)
#   - sound:  paplay / pw-play / canberra-gtk-play / ffplay
#
# When invoked from an SSH/non-tty subprocess that didn't inherit the
# user's GUI env, we derive WAYLAND_DISPLAY, XDG_RUNTIME_DIR, DISPLAY,
# and DBUS_SESSION_BUS_ADDRESS from /run/user/$UID so the dialog tool
# can reach the live session.
#
# Usage:
#   notify-linux.sh "Your build finished!"
#   notify-linux.sh -m "Done!" -t "CI Result" -s Hero
#   notify-linux.sh -m "URGENT" --repeat 3
#   notify-linux.sh -m "PROD IS DOWN" --loop -s Sosumi
#
# Note: --style notification is accepted for CLI compatibility with the
# macOS leaf but is IGNORED on Linux — a modal is always shown.

set -euo pipefail

MESSAGE=""
TITLE="Agent Ping"
SOUND="Glass"
STYLE="dialog"
REPEAT=1
LOOP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)  MESSAGE="$2"; shift 2 ;;
    -t|--title)    TITLE="$2"; shift 2 ;;
    -s|--sound)    SOUND="$2"; shift 2 ;;
    --style)
      STYLE="$2"
      if [[ "$STYLE" == "notification" ]]; then
        echo "notify-linux.sh: --style notification ignored — modal dialog is always used on Linux." >&2
      fi
      shift 2
      ;;
    --repeat)      REPEAT="$2"; shift 2 ;;
    --loop)        LOOP=true; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: notify-linux.sh -m "message" [-t title] [-s sound] [--repeat N] [--loop]

A blocking modal dialog is ALWAYS shown. --style is accepted for
cross-platform CLI compatibility but ignored on Linux.

Sound names accept either macOS names (mapped to freedesktop sounds)
or a freedesktop sound name (e.g. bell, complete, dialog-error,
dialog-warning, message, message-new-instant, window-attention) or an
absolute path to a sound file.

--loop: sound plays on infinite repeat until the dialog is dismissed.

The OK button means "ACKNOWLEDGED — let's talk." It is NOT consent to
any action being asked about.
EOF
      exit 0
      ;;
    *)
      if [[ -z "$MESSAGE" ]]; then
        MESSAGE="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$MESSAGE" ]]; then
  echo "Error: no message provided. Usage: notify-linux.sh -m \"your message\"" >&2
  exit 1
fi

# --- Inject GUI env when running from a headless subprocess (e.g. SSH'd
# Claude Bash tool). Pattern matches ~/CLAUDE.md guidance. ---
uid=$(id -u)
runtime_dir="/run/user/$uid"
if [[ -d "$runtime_dir" ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$runtime_dir}"

  if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    sock=$(ls "$runtime_dir"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 || true)
    if [[ -n "$sock" ]]; then
      export WAYLAND_DISPLAY="$(basename "$sock")"
    fi
  fi

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "$runtime_dir/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    export DISPLAY=":0"
  fi
fi

# --- Sound resolution -------------------------------------------------
# Map macOS sound names → freedesktop sounds. Unknown name falls back to
# bell. Absolute paths are used as-is.
resolve_sound_file() {
  local name="$1"
  if [[ "$name" == /* && -f "$name" ]]; then
    printf '%s' "$name"
    return
  fi

  local fd_name
  case "$name" in
    Glass|Purr|Submarine|Tink|Bottle)  fd_name="bell" ;;
    Basso|Sosumi)                      fd_name="dialog-error" ;;
    Funk|Morse)                        fd_name="dialog-warning" ;;
    Hero)                              fd_name="complete" ;;
    Ping|Pop)                          fd_name="message" ;;
    Frog|Blow)                         fd_name="window-attention" ;;
    *)                                 fd_name="$name" ;;  # pass-through
  esac

  local candidate="/usr/share/sounds/freedesktop/stereo/${fd_name}.oga"
  if [[ -f "$candidate" ]]; then
    printf '%s' "$candidate"
    return
  fi

  # Final fallback
  if [[ -f "/usr/share/sounds/freedesktop/stereo/bell.oga" ]]; then
    printf '%s' "/usr/share/sounds/freedesktop/stereo/bell.oga"
  fi
}

play_sound_once() {
  local file="$1"
  [[ -z "$file" || ! -f "$file" ]] && return 0

  if command -v paplay >/dev/null 2>&1; then
    paplay "$file" >/dev/null 2>&1
  elif command -v pw-play >/dev/null 2>&1; then
    pw-play "$file" >/dev/null 2>&1
  elif command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -f "$file" >/dev/null 2>&1
  elif command -v ffplay >/dev/null 2>&1; then
    ffplay -nodisp -autoexit -loglevel quiet "$file" >/dev/null 2>&1
  fi
}

SOUND_FILE="$(resolve_sound_file "$SOUND" || true)"

# --- Dialog tools -----------------------------------------------------
# After spawning a dialog under Hyprland, nudge it so it grabs attention:
# focus, pin (sticky across workspaces), center. zenity/kdialog auto-
# focus on spawn so we operate on the active window — simpler and more
# reliable than parsing addresses out of `hyprctl clients`.
polish_hypr_window() {
  local class_re="$1"
  [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && return 0
  command -v hyprctl >/dev/null 2>&1 || return 0

  # Give the toolkit + compositor time to map the window and auto-focus.
  sleep 0.5

  hyprctl dispatch focuswindow "class:^(${class_re})$" >/dev/null 2>&1 || true
  hyprctl dispatch pin >/dev/null 2>&1 || true
  hyprctl dispatch centerwindow >/dev/null 2>&1 || true
  return 0
}

# OK button label conveys the semantics: pressing it = "I see this, let's
# discuss". It is NOT consent to whatever the agent was about to do.
ACK_LABEL="Acknowledged — let's talk"

show_dialog_blocking() {
  local title="$1" body="$2"
  local pid

  # zenity preferred: --width/--height work properly and --ok-label lets
  # us rename the button so the user can't misread it as approval.
  if command -v zenity >/dev/null 2>&1; then
    zenity --info \
      --title="$title" \
      --text="$body" \
      --width=600 --height=200 --no-wrap \
      --ok-label="$ACK_LABEL" \
      >/dev/null 2>&1 &
    pid=$!
    polish_hypr_window "zenity"
    wait "$pid" || true
    return 0
  fi

  # kdialog --msgbox can't relabel its OK button, so use --warningcontinuecancel
  # and hide the Cancel by mapping continue→ack. The --continue-label sets the
  # visible button label. (Exit 0 = Continue, 1 = Cancel; we only treat the
  # dialog as "dismissed" either way — both mean the user saw it.)
  if command -v kdialog >/dev/null 2>&1; then
    kdialog \
      --title "$title" \
      --warningcontinuecancel "$body" \
      --continue-label "$ACK_LABEL" \
      --cancel-label "Dismiss" \
      >/dev/null 2>&1 &
    pid=$!
    polish_hypr_window "org\\.kde\\.kdialog"
    wait "$pid" || true
    return 0
  fi

  echo "notify-linux.sh: no dialog tool found (need zenity or kdialog)" >&2
  echo "[$title] $body" >&2
  return 1
}

# --- Main flow --------------------------------------------------------
# Always blocking modal — no passive-notification escape hatch.
if [[ "$LOOP" == true && -n "$SOUND_FILE" ]]; then
  (
    while true; do
      play_sound_once "$SOUND_FILE"
    done
  ) &
  LOOP_PID=$!

  show_dialog_blocking "$TITLE" "$MESSAGE" || true

  kill "$LOOP_PID" 2>/dev/null || true
  wait "$LOOP_PID" 2>/dev/null || true
  pkill -P $$ paplay pw-play canberra-gtk-play ffplay 2>/dev/null || true
else
  if [[ -n "$SOUND_FILE" ]]; then
    for ((i = 0; i < REPEAT; i++)); do
      play_sound_once "$SOUND_FILE" &
      if (( i < REPEAT - 1 )); then
        sleep 0.4
      fi
    done
  fi

  show_dialog_blocking "$TITLE" "$MESSAGE"
fi
