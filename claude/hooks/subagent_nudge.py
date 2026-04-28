#!/usr/bin/env python3
"""PostToolUse hook (matcher=Agent): inject a 'subagent summary is a hypothesis,
not a report' reminder into the parent model's context after every Agent call."""

import json
import sys


REMINDER = (
    "A subagent just finished and returned a summary. THAT SUMMARY IS A HYPOTHESIS, "
    "NOT A REPORT. Before you accept it or relay it to the user:\n"
    "1. Read the actual diff of every file the subagent modified — the code, not the summary.\n"
    "2. Grep for every new function/export it created and verify at least one live code path calls it.\n"
    "3. If it claimed tests pass, run them yourself. AND remember: tests passing != the feature "
    "working. Whether the code is actually functional end-to-end is a SEPARATE problem you "
    "also need to verify.\n"
    "Subagent summaries describe intent, not outcome. Verify firsthand."
)


TARGET_SUBAGENT_TYPES = {"code-reviewer"}


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)

    tool_input = payload.get("tool_input") or {}
    if tool_input.get("subagent_type") not in TARGET_SUBAGENT_TYPES:
        sys.exit(0)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": REMINDER,
        }
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
