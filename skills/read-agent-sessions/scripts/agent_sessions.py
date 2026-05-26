#!/usr/bin/env python3
"""Unified CLI for searching and reading session history across Claude, Pi, and Codex."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

# Allow imports from the same directory when invoked directly
if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import SessionMeta, Provider, clip, normalize_whitespace
from provider_claude import ClaudeProvider
from provider_pi import PiProvider
from provider_codex import CodexProvider


ALL_PROVIDERS: list[Provider] = [
    ClaudeProvider(),
    PiProvider(),
    CodexProvider(),
]

PROVIDER_MAP = {p.name: p for p in ALL_PROVIDERS}


def get_providers(harness_filter: str | None) -> list[Provider]:
    if not harness_filter:
        return ALL_PROVIDERS
    name = harness_filter.lower()
    if name in PROVIDER_MAP:
        return [PROVIDER_MAP[name]]
    # Fuzzy: allow "Claude", "PI", etc.
    for p in ALL_PROVIDERS:
        if p.name == name or p.label.lower() == name:
            return [p]
    print(f"Unknown harness '{harness_filter}'. Available: {', '.join(PROVIDER_MAP)}", file=sys.stderr)
    raise SystemExit(1)


def all_session_files(providers: list[Provider]) -> list[tuple[Provider, Path]]:
    pairs: list[tuple[Provider, Path]] = []
    for provider in providers:
        for path in provider.iter_session_files():
            pairs.append((provider, path))
    return pairs


def passes_project_filter(meta: SessionMeta, project_filter: str | None) -> bool:
    if not project_filter:
        return True
    needle = project_filter.lower()
    haystacks = [meta.bucket, meta.cwd, str(meta.path), meta.name]
    return any(needle in v.lower() for v in haystacks if v)


def format_harness_tag(harness: str) -> str:
    return f"({harness})"


# ── Commands ─────────────────────────────────────────────────────────

def cmd_recent(args: argparse.Namespace) -> int:
    providers = get_providers(args.harness)
    summaries: list[SessionMeta] = []
    for provider, path in all_session_files(providers):
        meta = provider.summarize(path)
        if passes_project_filter(meta, args.project):
            summaries.append(meta)

    summaries.sort(key=lambda s: s.ended_at or s.started_at or "", reverse=True)

    for meta in summaries[: args.limit]:
        name_display = meta.name or clip(meta.first_user or meta.last_assistant or "-", 60)
        print(
            f"{meta.ended_at or meta.started_at}\t"
            f"{meta.session_id[:12]}\t"
            f"{format_harness_tag(meta.harness)}\t"
            f"{name_display}"
        )
    return 0


def cmd_find(args: argparse.Namespace) -> int:
    providers = get_providers(args.harness)
    query = args.query.lower()
    matches: list[SessionMeta] = []

    for provider, path in all_session_files(providers):
        meta = provider.summarize(path)
        if not passes_project_filter(meta, args.project):
            continue
        haystacks = [
            meta.session_id, meta.bucket, meta.cwd, meta.git_branch,
            meta.name, meta.first_user, meta.last_assistant, str(meta.path),
        ]
        if any(query in v.lower() for v in haystacks if v):
            matches.append(meta)

    matches.sort(key=lambda s: s.ended_at or s.started_at or "", reverse=True)
    for meta in matches[: args.limit]:
        name_line = f"  name: {meta.name}" if meta.name else ""
        print(
            f"{meta.session_id} {format_harness_tag(meta.harness)}\n"
            f"  path: {meta.path}\n"
            f"  ended: {meta.ended_at or meta.started_at}\n"
            f"  cwd: {meta.cwd or '-'}\n"
            f"  branch: {meta.git_branch or '-'}"
            f"{name_line}\n"
            f"  first_user: {meta.first_user or '-'}\n"
        )

    if not matches:
        print(f"No sessions matched '{args.query}'.", file=sys.stderr)
        return 1
    return 0


def cmd_grep(args: argparse.Namespace) -> int:
    providers = get_providers(args.harness)
    needle = args.query.lower() if args.ignore_case else args.query
    hit_count = 0

    for provider, path in all_session_files(providers):
        if args.project and args.project.lower() not in str(path).lower():
            continue
        with path.open("r", encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, start=1):
                haystack = line.lower() if args.ignore_case else line
                if needle in haystack:
                    print(f"{format_harness_tag(provider.label)} {path}:{lineno}: {clip(line.strip(), 220)}")
                    hit_count += 1
                    if hit_count >= args.limit:
                        return 0

    if hit_count == 0:
        print(f"No transcript lines matched '{args.query}'.", file=sys.stderr)
        return 1
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    provider, path = resolve_target(args)
    meta = provider.summarize(path)

    print(f"path: {meta.path}")
    print(f"harness: {meta.harness}")
    print(f"session_id: {meta.session_id}")
    if meta.name:
        print(f"name: {meta.name}")
    print(f"project_bucket: {meta.bucket}")
    print(f"started_at: {meta.started_at or '-'}")
    print(f"ended_at: {meta.ended_at or '-'}")
    print(f"cwd: {meta.cwd or '-'}")
    print(f"git_branch: {meta.git_branch or '-'}")
    print(f"user_messages: {meta.user_count}")
    print(f"assistant_messages: {meta.assistant_count}")
    print(f"tool_uses: {meta.tool_use_count}")
    print(f"first_user: {meta.first_user or '-'}")
    print(f"last_assistant: {meta.last_assistant or '-'}")
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    provider, path = resolve_target(args)
    events = provider.load_events(path, include_meta=args.include_meta)
    max_chars = args.max_chars

    if args.tail is not None:
        events = events[-args.tail:]
    else:
        events = events[: args.limit]

    for event in events:
        label = event.role
        ts = event.timestamp or "-"
        content = clip(event.content, max_chars) if max_chars else event.content
        print(f"[{ts}] {label}")
        print(content.rstrip())
        print()
    return 0


def resolve_target(args: argparse.Namespace) -> tuple[Provider, Path]:
    target = args.target
    harness_filter = getattr(args, "harness", None)

    # Direct file path
    candidate = Path(target).expanduser()
    if candidate.exists():
        # Figure out which provider owns this path
        for p in get_providers(harness_filter):
            try:
                candidate.relative_to(p.root)
                return (p, candidate)
            except ValueError:
                continue
        # Fallback: try each provider
        for p in ALL_PROVIDERS:
            try:
                candidate.relative_to(p.root)
                return (p, candidate)
            except ValueError:
                continue
        # Last resort: guess Claude (most common)
        return (ALL_PROVIDERS[0], candidate)

    # Search by ID prefix / path fragment
    target_lower = target.lower()
    providers = get_providers(harness_filter)
    matches: list[tuple[Provider, Path]] = []

    for provider, path in all_session_files(providers):
        sid = provider.session_id_from_path(path)
        if sid.lower().startswith(target_lower) or target_lower in str(path).lower():
            matches.append((provider, path))

    if not matches:
        print(f"No session matched '{target}'.", file=sys.stderr)
        raise SystemExit(1)

    if len(matches) > 1:
        print(f"Multiple sessions matched '{target}':", file=sys.stderr)
        for provider, path in matches[:20]:
            print(f"  ({provider.label}) {path}", file=sys.stderr)
        if len(matches) > 20:
            print(f"  ... and {len(matches) - 20} more", file=sys.stderr)
        raise SystemExit(2)

    return matches[0]


# ── Argument parser ──────────────────────────────────────────────────

def _harness_arg(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--harness",
        choices=["claude", "pi", "codex"],
        help="Restrict to a single harness (default: search all).",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="read-agent-sessions",
        description="Search and read session history across Claude, Pi, and Codex.",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    # recent
    p = sub.add_parser("recent", help="List recent sessions across all harnesses.")
    _harness_arg(p)
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--project", help="Filter by bucket/path/cwd/name fragment.")
    p.set_defaults(func=cmd_recent)

    # find
    p = sub.add_parser("find", help="Find sessions by metadata query.")
    _harness_arg(p)
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--project", help="Filter by bucket/path/cwd/name fragment.")
    p.set_defaults(func=cmd_find)

    # grep
    p = sub.add_parser("grep", help="Search raw transcript lines.")
    _harness_arg(p)
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--project", help="Filter by path fragment before scanning.")
    p.add_argument("--ignore-case", action="store_true")
    p.set_defaults(func=cmd_grep)

    # summary
    p = sub.add_parser("summary", help="Print a compact session summary.")
    _harness_arg(p)
    p.add_argument("target", help="Session ID prefix or direct .jsonl path.")
    p.set_defaults(func=cmd_summary)

    # render
    p = sub.add_parser("render", help="Render a readable transcript excerpt.")
    _harness_arg(p)
    p.add_argument("target", help="Session ID prefix or direct .jsonl path.")
    p.add_argument("--limit", type=int, default=40, help="Render first N events.")
    p.add_argument("--tail", type=int, help="Render last N events instead.")
    p.add_argument("--include-meta", action="store_true", help="Include meta/system noise.")
    p.add_argument("--max-chars", type=int, default=280, help="Max chars per segment.")
    p.set_defaults(func=cmd_render)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
