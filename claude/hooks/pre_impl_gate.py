#!/usr/bin/env python3
"""PreToolUse gate: block Edit/Write/NotebookEdit unless pre-implementation-checklist
was invoked at least once in the current turn. Fails open on parse errors so a
broken transcript never wedges the editor.

OPT-IN: enforcement is OFF by default (too noisy in one-off threads). Type
#checklist:enable in a prompt to turn it on; it stays on for the rest of the
session until #checklist:disable."""

import json
import sys
from pathlib import Path


TARGET_TOOLS = {"Edit", "Write", "NotebookEdit"}
REQUIRED_SKILL = "pre-implementation-checklist"
DISABLE_TOKEN = "#checklist:disable"
ENABLE_TOKEN = "#checklist:enable"


def is_real_user_turn_start(obj):
    """A transcript line qualifies as a user-submitted turn boundary only if:
    - type=user, role=user, content is a string (excludes tool_results with array content)
    - promptId present (excludes slash-command meta: <command-name>, <local-command-stdout>, etc.)
    - isSidechain != True (excludes subagent transcript lines threaded into main JSONL)
    - isMeta != True (excludes hook-rewake messages like 'Stop hook feedback: ...')
    - origin.kind != 'task-notification' (excludes async subagent completion notifications)
    """
    if obj.get("type") != "user":
        return False
    if obj.get("isSidechain") is True:
        return False
    if obj.get("isMeta") is True:
        return False
    origin = obj.get("origin") or {}
    if isinstance(origin, dict) and origin.get("kind") == "task-notification":
        return False
    if obj.get("promptId") is None:
        return False
    msg = obj.get("message") or {}
    if msg.get("role") != "user":
        return False
    if not isinstance(msg.get("content"), str):
        return False
    return True


def find_turn_start(lines):
    """Index of the most recent real user-submitted prompt line, or 0."""
    for i in range(len(lines) - 1, -1, -1):
        try:
            obj = json.loads(lines[i])
        except json.JSONDecodeError:
            continue
        if is_real_user_turn_start(obj):
            return i
    return 0


def hooks_enabled_by_user(lines):
    """Walk user-submitted prompts newest→oldest. The first one containing either
    token decides: True (enforce) iff #checklist:enable appears AFTER
    #checklist:disable within that message (rfind positions). No token in any user
    prompt → disabled. These gates are opt-in — too noisy in one-off threads, so
    enforcement stays off until the user explicitly types #checklist:enable."""
    for i in range(len(lines) - 1, -1, -1):
        try:
            obj = json.loads(lines[i])
        except json.JSONDecodeError:
            continue
        if not is_real_user_turn_start(obj):
            continue
        text = obj.get("message", {}).get("content", "")
        d = text.rfind(DISABLE_TOKEN)
        e = text.rfind(ENABLE_TOKEN)
        if d == -1 and e == -1:
            continue
        return e > d
    return False


def skill_invoked(lines, start_idx, skill_name):
    for line in lines[start_idx:]:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("isSidechain") is True:
            continue
        if obj.get("type") != "assistant":
            continue
        content = obj.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if (
                isinstance(block, dict)
                and block.get("type") == "tool_use"
                and block.get("name") == "Skill"
                and (block.get("input") or {}).get("skill") == skill_name
            ):
                return True
    return False


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)

    if payload.get("tool_name") not in TARGET_TOOLS:
        sys.exit(0)

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not Path(transcript_path).exists():
        sys.exit(0)

    try:
        lines = Path(transcript_path).read_text().splitlines()
    except OSError:
        sys.exit(0)

    if not hooks_enabled_by_user(lines):
        sys.exit(0)

    start_idx = find_turn_start(lines)
    if skill_invoked(lines, start_idx, REQUIRED_SKILL):
        sys.exit(0)

    reason = (
        "STOP. You are about to modify code without invoking pre-implementation-checklist "
        "first. This is non-negotiable per CLAUDE.md. Invoke the skill now "
        "(/pre-implementation-checklist via the Skill tool), complete its steps — research, "
        "verify dependencies, check what exists, confirm design alignment — THEN retry the "
        "edit. Catch wrong assumptions BEFORE they become wrong code."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    sys.exit(0)


if __name__ == "__main__":
    main()
