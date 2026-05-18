#!/usr/bin/env python3
"""Stop gate: detect a filler-spin loop and tell the agent to block instead.

A /goal (or any Stop-blocking gate) re-continues the agent until its
condition is met. When the agent is genuinely WAITING -- on a background
task, or on a Ben decision -- that condition cannot be met by the model
alone, so the gate re-fires every turn and the agent emits short filler
("In-flight.", "Awaiting Ben.") turn after turn. This hook detects that
spin and tells the agent to hold the turn open (block) instead of ending
it with filler.

DETECTION IS STRUCTURAL, NOT TEXTUAL. The loop's fingerprint is a run of
consecutive assistant turns that are short and did no real work. That
pattern only occurs under force-continuation -- in normal conversation a
real user turn sits between assistant turns. So it needs no similarity
check: it catches VARIED filler ("waiting." vs "In-flight (74k lines)")
for free, because it never compares the turns' wording. Raw fuzzy
matching would be worse -- it would miss exactly the varied case.

KEY TRANSCRIPT DETAIL: inside the loop the harness injects, between every
filler turn, a `user` record flagged `isMeta` carrying the goal/gate
feedback. A detector that stopped its run at any `user` record would see
a run of length 1 and never fire. So isMeta (and isSidechain) records are
SKIPPED, not treated as run-breakers; only a real user turn or a
tool_result (a non-meta `user` record) or real tool work ends the run.

KNOWN + ACCEPTED LIMITATION: the fix this hook points the agent toward --
foreground-blocking -- cannot be infinite. The Bash tool auto-backgrounds
any command at its timeout (10 min max). So a long wait still produces a
Stop roughly every 10 minutes; this hook converts a ~12-second filler
spiral into a ~10-minute clean heartbeat. It does NOT eliminate the loop:
the /goal evaluator is built into Claude Code and unreachable from the
hook layer. That ceiling is understood and accepted -- a ~50x reduction
with every beat clean is the best achievable here.
"""

import json
import sys
from pathlib import Path

# Consecutive filler turns before the hook fires. 3 = a pattern is
# established while only ~2 turns have been wasted.
RUN_THRESHOLD = 3
# An assistant turn whose text is under this is "short" -- filler-sized.
# Real filler in practice is well under 120 chars; 250 is a safe ceiling
# that still excludes substantive turns.
SHORT_TEXT_CHARS = 250


def assistant_text(obj):
    """Concatenated text of an assistant record, or None if the record
    contains a tool_use block (i.e. the turn did real work -- not filler)."""
    content = obj.get("message", {}).get("content", [])
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    texts = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_use":
            return None  # did work this turn -> ends the filler run
        if block.get("type") == "text":
            texts.append(block.get("text", ""))
    return "\n".join(texts)


def trailing_filler_run(lines):
    """Walk the transcript backward and return the list of short, tool-less
    assistant texts forming the trailing run.

    The run ends at the first of: a real (non-meta) user turn or tool_result,
    an assistant turn that did tool work, or an assistant turn that was not
    short. isMeta / isSidechain records are skipped (the goal-feedback record
    injected between filler turns is a user+isMeta record)."""
    run = []
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("isMeta") or obj.get("isSidechain"):
            continue
        rtype = obj.get("type")
        if rtype == "user":
            break  # real user input or a tool_result -> run ends
        if rtype != "assistant":
            continue  # attachment / system / title / etc. -- ignore
        text = assistant_text(obj)
        if text is None:
            break  # tool_use this turn -> real work, run ends
        if len(text.strip()) > SHORT_TEXT_CHARS:
            break  # a substantive turn -> not filler
        run.append(text)
    return run


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not Path(transcript_path).exists():
        sys.exit(0)

    try:
        lines = Path(transcript_path).read_text().splitlines()
    except OSError:
        sys.exit(0)

    run = trailing_filler_run(lines)
    if len(run) < RUN_THRESHOLD:
        sys.exit(0)

    block(
        f"LOOP DETECTED -- your last {len(run)} turns were short, did no "
        "real work, and were force-continued with no input from Ben. You "
        "are filler-spinning while a goal or gate holds the turn open. "
        "This burns turns and Ben's wall-clock for nothing.\n\n"
        "You are WAITING on something. Stop ending turns with filler. Do "
        "ONE of these now -- both hold THIS turn open so no Stop fires and "
        "the spin cannot continue:\n\n"
        "  - Waiting on a background task? Foreground-block on it:\n"
        "      tail --pid=<PID> -f /dev/null\n"
        "    The turn stays open until the task exits, then you continue.\n\n"
        "  - Blocked on a decision only Ben can make? Fire a BLOCKING "
        "/notify (notify skill, blocking dialog). It holds the turn open "
        "until he answers and pulls him in, instead of leaving him to "
        "discover this later.\n\n"
        "Do NOT emit another status one-liner. Block, or notify-block. "
        "Pick one."
    )


if __name__ == "__main__":
    main()
