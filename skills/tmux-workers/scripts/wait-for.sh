#!/usr/bin/env bash
# wait-for.sh <pi|codex|claude|any> <pane> [--stable N] [--timeout S] [--interval S] [--quiet]
#
# Block until an interactive agent CLI in <pane> goes IDLE — its "busy" marker
# gone. The invocation reads as what it does: "wait-for pi <pane>",
# "wait-for codex <pane>", "wait-for claude <pane>".
#
# The first argument is an agent PRESET — it selects that CLI's busy-marker
# regex, and the script then waits for the marker to disappear (a thin wrapper
# over wait-for-text.sh --gone).
#
# Busy-marker presets — distinctive where the CLI allows; verified by live probe:
#   pi      "Working..."
#   codex   "esc to interrupt" (its turn marker — Codex shows it as
#           "Working (1s • esc to interrupt)"), plus "Waiting for background
#           terminal" while a sub-command runs
#   claude  NO stable keyword. Claude Code's spinner is an animated glyph + a
#           RANDOM gerund + a live timer, e.g. "✻ Schlepping… (13s · ↑ 374
#           tokens)". Matched heuristically: a gerund-ellipsis "…" then a
#           parenthesised elapsed time. Its idle line "✻ Cogitated for Xs" has
#           no "… (", so the states separate cleanly.
#   any     union of all the above, plus "Auto-compacting" — safe when you are
#           not certain which CLI is in the pane, or run a mix.
#
# NOTE: Gemini's busy marker is NOT verified. To wait on a Gemini pane,
# capture-pane it once mid-turn, read its busy text, and pass that pattern to
# wait-for-text.sh --gone directly.
#
# --stable / --timeout / --interval / --quiet pass straight through to
# wait-for-text.sh.
#
# Run this asynchronously — under Claude Code's Monitor tool, or Pi's async
# monitor tooling. On an agent with neither (Codex, Gemini), it blocks.
#
# Exit: 0 agent idle · 1 timeout · 2 pane gone or bad args.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENT=""; PANE=""; PASS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stable|--timeout|--interval) PASS+=("$1" "$2"); shift 2 ;;
    --quiet)                       PASS+=("$1"); shift ;;
    -*) echo "wait-for: unknown flag: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$AGENT" ]]; then AGENT="$1"
      elif [[ -z "$PANE" ]]; then PANE="$1"
      else echo "wait-for: unexpected arg: $1" >&2; exit 2; fi
      shift ;;
  esac
done

if [[ -z "$AGENT" || -z "$PANE" ]]; then
  echo "usage: wait-for.sh <pi|codex|claude|any> <pane> [--timeout S] [--stable N] [--interval S] [--quiet]" >&2
  exit 2
fi

case "$AGENT" in
  pi)     BUSY='Working\.\.\.' ;;
  codex)  BUSY='esc to interrupt|Waiting for background terminal' ;;
  claude) BUSY='…\s*\([^)]*[0-9]+s' ;;
  any)    BUSY='Working\.\.\.|esc to interrupt|Waiting for background terminal|Auto-compacting|…\s*\([^)]*[0-9]+s' ;;
  *) echo "wait-for: unknown agent '$AGENT' (use pi|codex|claude|any)" >&2; exit 2 ;;
esac

exec "$SCRIPT_DIR/wait-for-text.sh" "$PANE" "$BUSY" --gone "${PASS[@]}"
