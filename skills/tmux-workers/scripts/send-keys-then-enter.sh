#!/usr/bin/env bash
# send-keys-then-enter.sh <pane> <text> [--settle S] [--no-verify] [--quiet]
#
# Type TEXT into an interactive agent's pane and submit it.
#
# Does the two-step properly — literal text first (tmux send-keys -l, so no
# word is interpreted as a key name), then a separate Enter — and then handles
# the submit quirk: a TUI input box sometimes keeps the text unsent after the
# first Enter, so this captures the pane and sends a second bare Enter if the
# agent did not start working.
#
#   --settle S    seconds between the text and the Enter, so the input box
#                 registers the text first. Default 1.
#   --no-verify   skip the did-it-submit check (just literal text + Enter).
#   --quiet       no status output.
#
# Do NOT pass a multi-line brief here — embedded newlines submit the message
# early. Write the brief to a file and pass a one-liner: "Read /tmp/brief.md in
# full and ...". The CALLER is responsible for shell-quoting TEXT.
#
# Exit: 0 sent (and, unless --no-verify, confirmed submitted) · 2 pane gone or
# bad args. A WARNING (not a failure) is printed if it still cannot confirm.

set -uo pipefail

# Busy markers = "the agent started working" = "the message submitted".
# Union across pi / codex / claude. Pi and Codex have stable keywords; Claude
# Code has none, so its spinner is matched heuristically (gerund-ellipsis "…"
# then a parenthesised live timer). Bare "Working" is avoided — false-matches
# prose. See wait-for.sh for the per-CLI breakdown.
BUSY='Working\.\.\.|esc to interrupt|Waiting for background terminal|Auto-compacting|…\s*\([^)]*[0-9]+s'

PANE=""; TEXT=""; SETTLE=1; VERIFY=1; QUIET=0; TEXT_SET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --settle)    SETTLE="$2"; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    --quiet)     QUIET=1; shift ;;
    -*)          echo "send-keys-then-enter: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$PANE" ]]; then PANE="$1"
      elif [[ "$TEXT_SET" = 0 ]]; then TEXT="$1"; TEXT_SET=1
      else echo "send-keys-then-enter: unexpected arg: $1" >&2; exit 2; fi
      shift ;;
  esac
done

if [[ -z "$PANE" || "$TEXT_SET" = 0 ]]; then
  echo "usage: send-keys-then-enter.sh <pane> <text> [--settle S] [--no-verify] [--quiet]" >&2
  exit 2
fi

say() { [[ "$QUIET" = 1 ]] || echo "$@"; }

tmux capture-pane -p -t "$PANE" >/dev/null 2>&1 || { say "send-keys-then-enter: pane $PANE is GONE"; exit 2; }

# 1. literal text   2. settle   3. Enter
tmux send-keys -t "$PANE" -l "$TEXT"
sleep "$SETTLE"
tmux send-keys -t "$PANE" Enter

if [[ "$VERIFY" = 0 ]]; then
  say "send-keys-then-enter: sent to $PANE (unverified)"
  exit 0
fi

# Submit quirk: give the agent a moment, then check it actually started.
sleep 3
cap=$(tmux capture-pane -p -t "$PANE" 2>/dev/null) || { say "send-keys-then-enter: pane $PANE is GONE"; exit 2; }
if grep -qE "$BUSY" <<<"$cap"; then
  say "send-keys-then-enter: sent to $PANE — agent is working"
  exit 0
fi

# Text likely still sitting in the input box — nudge it with a bare Enter.
say "send-keys-then-enter: no work marker yet — sending a bare Enter to submit"
tmux send-keys -t "$PANE" Enter
sleep 3
cap=$(tmux capture-pane -p -t "$PANE" 2>/dev/null) || { say "send-keys-then-enter: pane $PANE is GONE"; exit 2; }
if grep -qE "$BUSY" <<<"$cap"; then
  say "send-keys-then-enter: submitted on the second Enter"
else
  say "send-keys-then-enter: WARNING — pane $PANE shows no work marker; the agent may have"
  say "                       answered instantly, or the message is stuck. Capture the pane"
  say "                       and check before assuming it ran."
fi
exit 0
