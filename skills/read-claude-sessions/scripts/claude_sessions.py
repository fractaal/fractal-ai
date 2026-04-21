#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_ROOT = Path.home() / ".claude" / "projects"


@dataclass
class SessionSummary:
    path: Path
    session_id: str
    bucket: str
    started_at: str
    ended_at: str
    cwd: str
    git_branch: str
    slug: str
    user_count: int
    assistant_count: int
    tool_use_count: int
    first_user: str
    last_assistant: str


def iter_session_files(root: Path) -> Iterable[Path]:
    if not root.exists():
        return []

    files: list[Path] = []
    for path in root.rglob("*.jsonl"):
        if "subagents" in path.parts:
            continue
        if path.name.startswith("agent-"):
            continue
        files.append(path)
    return sorted(files)


def load_events(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                events.append(obj)
    return events


def normalize_whitespace(text: str) -> str:
    return " ".join(text.split())


def clip(text: str, max_chars: int) -> str:
    text = normalize_whitespace(text)
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


def is_local_command_noise(text: str) -> bool:
    stripped = text.strip()
    return stripped.startswith(
        (
            "<local-command-caveat>",
            "<command-name>",
            "<local-command-stdout>",
            "<local-command-stderr>",
        )
    )


def extract_message_content(event: dict[str, Any], *, include_meta: bool = False) -> list[str]:
    message = event.get("message")
    if isinstance(message, dict):
        content = message.get("content")
    else:
        content = event.get("content")

    if isinstance(content, str):
        if not include_meta and is_local_command_noise(content):
            return []
        return [content]

    if not isinstance(content, list):
        return []

    parts: list[str] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        item_type = item.get("type")
        if item_type == "text":
            text = item.get("text")
            if isinstance(text, str) and text.strip():
                if not include_meta and is_local_command_noise(text):
                    continue
                parts.append(text)
        elif item_type == "tool_use":
            name = str(item.get("name") or "unknown-tool")
            tool_input = item.get("input")
            if include_meta:
                parts.append(f"[tool_use] {name} {clip(json.dumps(tool_input, ensure_ascii=False), 180)}")
            else:
                parts.append(f"[tool_use] {name}")
        elif item_type == "tool_result":
            content_value = item.get("content")
            rendered = render_tool_result_content(content_value)
            if rendered:
                parts.append(f"[tool_result] {rendered}")
        elif include_meta and item_type == "thinking":
            thinking = item.get("thinking")
            if isinstance(thinking, str) and thinking.strip():
                parts.append(f"[thinking] {clip(thinking, 180)}")
    return parts


def render_tool_result_content(content: Any) -> str:
    if isinstance(content, str):
        return clip(content, 220)
    if isinstance(content, list):
        text_parts: list[str] = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text" and isinstance(item.get("text"), str):
                    text_parts.append(item["text"])
                else:
                    text_parts.append(clip(json.dumps(item, ensure_ascii=False), 120))
            else:
                text_parts.append(str(item))
        return clip(" ".join(text_parts), 220)
    if content is None:
        return ""
    return clip(str(content), 220)


def summarize_session(path: Path) -> SessionSummary:
    events = load_events(path)
    session_id = path.stem
    bucket = path.parent.name
    started_at = ""
    ended_at = ""
    cwd = ""
    git_branch = ""
    slug = ""
    user_count = 0
    assistant_count = 0
    tool_use_count = 0
    first_user = ""
    last_assistant = ""

    for event in events:
        timestamp = event.get("timestamp")
        if isinstance(timestamp, str):
            if not started_at:
                started_at = timestamp
            ended_at = timestamp

        if not cwd:
            cwd_value = event.get("cwd")
            if isinstance(cwd_value, str):
                cwd = cwd_value

        if not git_branch:
            branch = event.get("gitBranch")
            if isinstance(branch, str):
                git_branch = branch

        if not slug:
            slug_value = event.get("slug")
            if isinstance(slug_value, str):
                slug = slug_value

        if not session_id:
            sid = event.get("sessionId")
            if isinstance(sid, str):
                session_id = sid

        event_type = event.get("type")
        parts = extract_message_content(event)
        joined = normalize_whitespace(" ".join(parts))

        if event_type == "user":
            user_count += 1
            if not first_user and joined:
                first_user = clip(joined, 200)
        elif event_type == "assistant":
            assistant_count += 1
            if joined:
                last_assistant = clip(joined, 200)

        message = event.get("message")
        if isinstance(message, dict):
            content = message.get("content")
            if isinstance(content, list):
                tool_use_count += sum(
                    1
                    for item in content
                    if isinstance(item, dict) and item.get("type") == "tool_use"
                )

    return SessionSummary(
        path=path,
        session_id=session_id,
        bucket=bucket,
        started_at=started_at,
        ended_at=ended_at,
        cwd=cwd,
        git_branch=git_branch,
        slug=slug,
        user_count=user_count,
        assistant_count=assistant_count,
        tool_use_count=tool_use_count,
        first_user=first_user,
        last_assistant=last_assistant,
    )


def resolve_target(root: Path, target: str) -> Path:
    candidate = Path(target).expanduser()
    if candidate.exists():
        return candidate

    target_lower = target.lower()
    matches = [
        path
        for path in iter_session_files(root)
        if path.stem.lower().startswith(target_lower) or target_lower in str(path).lower()
    ]

    if not matches:
        print(f"No session matched '{target}'.", file=sys.stderr)
        raise SystemExit(1)

    if len(matches) > 1:
        print(f"Multiple sessions matched '{target}':", file=sys.stderr)
        for path in matches[:20]:
            print(f"  {path}", file=sys.stderr)
        if len(matches) > 20:
            print(f"  ... and {len(matches) - 20} more", file=sys.stderr)
        raise SystemExit(2)

    return matches[0]


def passes_project_filter(summary: SessionSummary, project_filter: str | None) -> bool:
    if not project_filter:
        return True
    needle = project_filter.lower()
    haystacks = [summary.bucket, summary.cwd, str(summary.path)]
    return any(needle in value.lower() for value in haystacks if value)


def cmd_recent(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser()
    summaries = [
        summarize_session(path)
        for path in iter_session_files(root)
    ]
    summaries = [s for s in summaries if passes_project_filter(s, args.project)]
    summaries.sort(key=lambda s: s.ended_at or s.started_at or "", reverse=True)

    for summary in summaries[: args.limit]:
        print(
            f"{summary.ended_at or summary.started_at}\t"
            f"{summary.session_id[:8]}\t"
            f"{summary.bucket}\t"
            f"{summary.git_branch or '-'}\t"
            f"{clip(summary.first_user or summary.last_assistant or '-', 100)}"
        )
    return 0


def cmd_find(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser()
    query = args.query.lower()
    matches: list[SessionSummary] = []

    for path in iter_session_files(root):
        summary = summarize_session(path)
        if not passes_project_filter(summary, args.project):
            continue
        haystacks = [
            summary.session_id,
            summary.bucket,
            summary.cwd,
            summary.git_branch,
            summary.slug,
            summary.first_user,
            summary.last_assistant,
            str(summary.path),
        ]
        if any(query in value.lower() for value in haystacks if value):
            matches.append(summary)

    matches.sort(key=lambda s: s.ended_at or s.started_at or "", reverse=True)
    for summary in matches[: args.limit]:
        print(
            f"{summary.session_id}\n"
            f"  path: {summary.path}\n"
            f"  ended: {summary.ended_at or summary.started_at}\n"
            f"  cwd: {summary.cwd or '-'}\n"
            f"  branch: {summary.git_branch or '-'}  slug: {summary.slug or '-'}\n"
            f"  first_user: {summary.first_user or '-'}\n"
        )

    if not matches:
        print(f"No sessions matched '{args.query}'.", file=sys.stderr)
        return 1
    return 0


def cmd_grep(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser()
    needle = args.query.lower() if args.ignore_case else args.query
    hit_count = 0

    for path in iter_session_files(root):
        if args.project and args.project.lower() not in str(path).lower():
            continue
        with path.open("r", encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, start=1):
                haystack = line.lower() if args.ignore_case else line
                if needle in haystack:
                    print(f"{path}:{lineno}: {clip(line.strip(), 220)}")
                    hit_count += 1
                    if hit_count >= args.limit:
                        return 0

    if hit_count == 0:
        print(f"No transcript lines matched '{args.query}'.", file=sys.stderr)
        return 1
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser()
    path = resolve_target(root, args.target)
    summary = summarize_session(path)

    print(f"path: {summary.path}")
    print(f"session_id: {summary.session_id}")
    print(f"project_bucket: {summary.bucket}")
    print(f"started_at: {summary.started_at or '-'}")
    print(f"ended_at: {summary.ended_at or '-'}")
    print(f"cwd: {summary.cwd or '-'}")
    print(f"git_branch: {summary.git_branch or '-'}")
    print(f"slug: {summary.slug or '-'}")
    print(f"user_messages: {summary.user_count}")
    print(f"assistant_messages: {summary.assistant_count}")
    print(f"tool_uses: {summary.tool_use_count}")
    print(f"first_user: {summary.first_user or '-'}")
    print(f"last_assistant: {summary.last_assistant or '-'}")
    return 0


def render_event(event: dict[str, Any], *, include_meta: bool, max_chars: int) -> str | None:
    event_type = str(event.get("type") or "unknown")
    if not include_meta and event.get("isMeta"):
        return None

    if event_type not in {"user", "assistant", "system"} and not include_meta:
        return None

    timestamp = str(event.get("timestamp") or "-")
    subtype = event.get("subtype")
    label = event_type if not subtype else f"{event_type}/{subtype}"
    body_parts = extract_message_content(event, include_meta=include_meta)
    if not body_parts and isinstance(event.get("content"), str):
        body_parts = [str(event["content"])]

    body = "\n".join(clip(part, max_chars) for part in body_parts if part.strip())
    if not body:
        if include_meta:
            body = clip(json.dumps(event, ensure_ascii=False), max_chars)
        else:
            return None

    return f"[{timestamp}] {label}\n{body}\n"


def cmd_render(args: argparse.Namespace) -> int:
    root = Path(args.root).expanduser()
    path = resolve_target(root, args.target)
    events = load_events(path)

    rendered = [
        block
        for block in (
            render_event(event, include_meta=args.include_meta, max_chars=args.max_chars)
            for event in events
        )
        if block
    ]

    if args.tail is not None:
        rendered = rendered[-args.tail :]
    else:
        rendered = rendered[: args.limit]

    for block in rendered:
        print(block.rstrip())
        print()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Inspect Claude Code session history under ~/.claude/projects."
    )
    parser.add_argument(
        "--root",
        default=str(DEFAULT_ROOT),
        help="Session root directory (default: ~/.claude/projects)",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    recent = subparsers.add_parser("recent", help="List recent sessions.")
    recent.add_argument("--limit", type=int, default=20)
    recent.add_argument("--project", help="Filter by bucket/path/cwd fragment.")
    recent.set_defaults(func=cmd_recent)

    find = subparsers.add_parser("find", help="Find sessions by metadata-ish query.")
    find.add_argument("query")
    find.add_argument("--limit", type=int, default=20)
    find.add_argument("--project", help="Filter by bucket/path/cwd fragment.")
    find.set_defaults(func=cmd_find)

    grep = subparsers.add_parser("grep", help="Search raw transcript lines.")
    grep.add_argument("query")
    grep.add_argument("--limit", type=int, default=50)
    grep.add_argument("--project", help="Filter by path fragment before scanning.")
    grep.add_argument("--ignore-case", action="store_true")
    grep.set_defaults(func=cmd_grep)

    summary = subparsers.add_parser("summary", help="Print a compact session summary.")
    summary.add_argument("target", help="Session ID prefix or direct .jsonl path.")
    summary.set_defaults(func=cmd_summary)

    render = subparsers.add_parser("render", help="Render a readable transcript excerpt.")
    render.add_argument("target", help="Session ID prefix or direct .jsonl path.")
    render.add_argument("--limit", type=int, default=40, help="Render first N events.")
    render.add_argument("--tail", type=int, help="Render last N events instead.")
    render.add_argument("--include-meta", action="store_true", help="Include meta/system noise.")
    render.add_argument("--max-chars", type=int, default=280, help="Max chars per rendered segment.")
    render.set_defaults(func=cmd_render)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
