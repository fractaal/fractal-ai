#!/bin/bash
#
# response-deferral-phrase-gate.sh
#
# Stop hook -- scans the last assistant message in the transcript for banned
# deferral phrases and exits 2 (blocking) if any are found.
#
# Catches the chat-response failure mode: typing "we can revisit this" or
# "or accept the slight gap" in a reply instead of either fixing the gap or
# loudly surfacing it to Ben.
#
# Install (global): this script lives at ~/.claude/hooks/ and reads its phrase
# lists from ~/.claude/hooks/lib/ -- resolved relative to this script, so the
# session's cwd / project dir does not matter.
#
# Scope:
#   - Scans only the LAST assistant message
#   - Skips lines inside fenced code blocks (so quoting the rule is fine)
#   - Honors a dismiss sentinel: `#deferral-meta` anywhere in the response,
#     for meta-discussion of the rule itself
#
# Adapted from a gist by michael-jennings; openspec/opsx workflow stripped,
# lib paths made script-relative, sentinel changed to #deferral-meta.

set -uo pipefail

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [[ -z "$TRANSCRIPT" ]] || [[ ! -f "$TRANSCRIPT" ]]; then exit 0; fi

# Resolve lib/ relative to this script so cwd / CLAUDE_PROJECT_DIR is irrelevant.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNED_FILE="$SCRIPT_DIR/lib/deferral-banned-phrases.txt"
REGEX_FILE="$SCRIPT_DIR/lib/deferral-pre-existing-regex.txt"

# Missing data files -> fail open (do not block, do not crash).
if [[ ! -f "$BANNED_FILE" ]] || [[ ! -f "$REGEX_FILE" ]]; then exit 0; fi

# Load banned phrases + the "pre-existing" dismissal regex from data files.
declare -a BANNED_PHRASES=()
while IFS= read -r LINE; do
  LINE="${LINE%%#*}"
  LINE="${LINE#"${LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  [[ -z "$LINE" ]] && continue
  BANNED_PHRASES+=("$LINE")
done < "$BANNED_FILE"
PRE_EXISTING_DISMISSAL_REGEX=""
while IFS= read -r LINE; do
  LINE="${LINE%%#*}"
  LINE="${LINE#"${LINE%%[![:space:]]*}"}"
  LINE="${LINE%"${LINE##*[![:space:]]}"}"
  [[ -z "$LINE" ]] && continue
  PRE_EXISTING_DISMISSAL_REGEX="$LINE"
  break
done < "$REGEX_FILE"

if [[ ${#BANNED_PHRASES[@]} -eq 0 ]]; then exit 0; fi

# Find the last assistant message JSONL line in the transcript.
LAST_ASSISTANT_LINE=$(tac "$TRANSCRIPT" 2>/dev/null | while IFS= read -r LINE; do
  ROLE=$(echo "$LINE" | jq -r '(.message.role // .role) // empty' 2>/dev/null || echo "")
  if [[ "$ROLE" == "assistant" ]]; then
    echo "$LINE"
    break
  fi
done)

if [[ -z "$LAST_ASSISTANT_LINE" ]]; then exit 0; fi

# Extract concatenated text content from the message (skip tool_use, thinking, etc).
TEXT=$(echo "$LAST_ASSISTANT_LINE" | jq -r '
  (.message.content // .content // []) as $c
  | if ($c | type) == "array" then
      $c | map(select(type == "object" and .type == "text") | .text) | join("\n")
    elif ($c | type) == "string" then
      $c
    else
      ""
    end
' 2>/dev/null || echo "")

if [[ -z "$TEXT" ]]; then exit 0; fi

# Dismiss sentinel for meta-discussion of the rule itself.
if echo "$TEXT" | grep -qF '#deferral-meta'; then exit 0; fi

# Strip fenced code blocks so quoting the rule in ``` ... ``` doesn't trip.
TEXT_NO_FENCES=$(echo "$TEXT" | awk '
  /^[[:space:]]*```/ { in_block = !in_block; next }
  !in_block { print }
')

# Collect hits as: line:phrase:text
declare -a HITS=()

for PHRASE in "${BANNED_PHRASES[@]}"; do
  while IFS= read -r MATCH; do
    [[ -z "$MATCH" ]] && continue
    HITS+=("L$MATCH :: phrase=\"$PHRASE\"")
  done < <(echo "$TEXT_NO_FENCES" | grep -inF "$PHRASE" 2>/dev/null)
done

# "pre-existing" dismissal pattern
while IFS= read -r MATCH; do
  [[ -z "$MATCH" ]] && continue
  if echo "$MATCH" | grep -iqE "$PRE_EXISTING_DISMISSAL_REGEX"; then
    HITS+=("L$MATCH :: phrase=\"pre-existing (dismissal)\"")
  fi
done < <(echo "$TEXT_NO_FENCES" | grep -inF "pre-existing" 2>/dev/null)

if [[ ${#HITS[@]} -eq 0 ]]; then exit 0; fi

{
  echo "[response-deferral-phrase-gate] BLOCK: banned deferral phrase(s) in your last response."
  echo ""
  echo "Hits (line numbers relative to your last message, code blocks excluded):"
  for HIT in "${HITS[@]}"; do
    echo "  $HIT"
  done
  echo ""
  echo "You deferred something without resolving it. Per Ben's rules there is"
  echo "no silent \"eh\" -- every deferral resolves exactly one of two ways:"
  echo ""
  echo "  (A) IN SCOPE -> fix it now. If it is part of the original task,"
  echo "      finish it this turn. \"Future work\" is just \"work I have not"
  echo "      done yet.\" Do the work."
  echo ""
  echo "  (B) GENUINELY OUT OF SCOPE but obviously wrong or incomplete"
  echo "      (failing tests, pre-existing bugs, broken behavior you noticed)"
  echo "      -> do NOT bury it in prose. Invoke the \`notify\` skill with a"
  echo "      BLOCKING dialog so Ben sees it and makes the call. Surface it"
  echo "      loudly; let him judge."
  echo ""
  echo "Then rewrite the deferral sentence to reflect (A) or (B), or delete it"
  echo "if the concern was not real, and respond again."
  echo ""
  echo "To discuss this rule itself, include the sentinel #deferral-meta in"
  echo "your response. The bar is HIGH -- it disables this gate entirely for"
  echo "that response."
} >&2

exit 2
