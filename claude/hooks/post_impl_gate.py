#!/usr/bin/env python3
"""Stop gate: if this turn modified code, block turn-end until
post-implementation-checklist was invoked AND at least 3 code-reviewer subagents
have actually COMPLETED (not just been spawned) after that invocation.
Respects stop_hook_active so we can't loop the main agent."""

import json
import re
import sys
from pathlib import Path


CODE_TOOLS = {"Edit", "Write", "NotebookEdit"}
AGENT_TOOL_NAMES = {"Agent", "Task"}
REQUIRED_SKILL = "post-implementation-checklist"
REQUIRED_REVIEWERS = 3
ASYNC_LAUNCH_MARKER = "Async agent launched successfully"
TASK_NOTIF_TOOL_USE_RE = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")


def is_real_user_turn_start(obj):
    """See pre_impl_gate.is_real_user_turn_start — same semantics."""
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
    for i in range(len(lines) - 1, -1, -1):
        try:
            obj = json.loads(lines[i])
        except json.JSONDecodeError:
            continue
        if is_real_user_turn_start(obj):
            return i
    return 0


def iter_tool_uses(lines, start_idx):
    """Yield (index, tool_use_id, name, input) for every main-session assistant
    tool_use after start_idx. Sidechain (subagent-internal) tool uses are skipped
    so nested Agent/Skill calls can't spoof counts."""
    for i, line in enumerate(lines[start_idx:], start=start_idx):
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
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield (
                    i,
                    block.get("id", ""),
                    block.get("name", ""),
                    block.get("input") or {},
                )


def tool_result_text(block):
    raw = block.get("content", "")
    if isinstance(raw, list):
        return "".join(
            b.get("text", "") for b in raw if isinstance(b, dict)
        )
    return str(raw) if raw is not None else ""


def reviewer_outputs_available(lines, start_idx, tool_use_ids):
    """Return the set of tool_use_ids whose reviewer output is actually readable
    by the parent — either synchronous tool_result (not the async-launch preamble)
    or a task-notification with status=completed for that id."""
    if not tool_use_ids:
        return set()
    available = set()
    for line in lines[start_idx:]:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") != "user":
            continue
        content = obj.get("message", {}).get("content")
        if isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") != "tool_result":
                    continue
                tid = block.get("tool_use_id")
                if tid not in tool_use_ids:
                    continue
                text = tool_result_text(block)
                if ASYNC_LAUNCH_MARKER not in text:
                    available.add(tid)
        elif isinstance(content, str):
            origin = obj.get("origin") or {}
            if not (isinstance(origin, dict) and origin.get("kind") == "task-notification"):
                continue
            if "<status>completed</status>" not in content:
                continue
            m = TASK_NOTIF_TOOL_USE_RE.search(content)
            if not m:
                continue
            tid = m.group(1)
            if tid in tool_use_ids:
                available.add(tid)
    return available


def block(reason):
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


def main():
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        sys.exit(0)

    if payload.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not Path(transcript_path).exists():
        sys.exit(0)

    try:
        lines = Path(transcript_path).read_text().splitlines()
    except OSError:
        sys.exit(0)

    start_idx = find_turn_start(lines)
    tool_uses = list(iter_tool_uses(lines, start_idx))

    had_code_changes = any(name in CODE_TOOLS for _, _, name, _ in tool_uses)
    if not had_code_changes:
        sys.exit(0)

    post_impl_idx = None
    for i, _tid, name, inp in tool_uses:
        if name == "Skill" and inp.get("skill") == REQUIRED_SKILL:
            post_impl_idx = i

    if post_impl_idx is None:
        block(
            "HOLD. You modified code in this turn but did NOT invoke "
            "post-implementation-checklist. This is non-negotiable per CLAUDE.md. "
            "Invoke the skill now, trace the end-to-end path, spawn all 3 parallel "
            "reviewers (Architecture, Functional Completeness, Regression), then finish. "
            "No shortcuts — tests passing is a PROXY metric, not verification that the "
            "feature works."
        )

    reviewer_tool_use_ids = {
        tid
        for i, tid, name, inp in tool_uses
        if i > post_impl_idx
        and name in AGENT_TOOL_NAMES
        and inp.get("subagent_type") == "code-reviewer"
        and tid
    }
    spawned = len(reviewer_tool_use_ids)
    completed_ids = reviewer_outputs_available(
        lines, post_impl_idx, reviewer_tool_use_ids
    )
    reviewer_count = len(completed_ids)

    if reviewer_count < REQUIRED_REVIEWERS:
        if spawned < REQUIRED_REVIEWERS:
            missing = REQUIRED_REVIEWERS - spawned
            block(
                f"HOLD. You invoked post-implementation-checklist but only spawned "
                f"{spawned} code-reviewer subagent(s). Phase 3 requires THREE in "
                f"parallel, each with a DIFFERENT mandate: Architecture, Functional "
                f"Completeness, Regression. You are {missing} short. Spawn the missing "
                f"reviewer(s) in a single message (parallel Agent tool calls), wait for "
                f"them, read their findings, THEN finish. One reviewer checking all three "
                f"dimensions does a shallow job on each — that's exactly the failure mode "
                f"this enforcement exists to prevent."
            )
        else:
            pending = spawned - reviewer_count
            block(
                f"HOLD. You spawned {spawned} code-reviewer subagents but only "
                f"{reviewer_count} have actually returned their findings — {pending} "
                f"are still running (launched async, no task-notification yet). "
                f"Wait for their results before finishing. Spawning 3 reviewers and "
                f"immediately stopping without reading their findings satisfies the "
                f"letter of the mandate but not the purpose."
            )

    sys.exit(0)


if __name__ == "__main__":
    main()
