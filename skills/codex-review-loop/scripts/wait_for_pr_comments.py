#!/usr/bin/env python3
"""Poll GitHub PR comments and exit when new comments are detected.

Supports two modes:
- Default: exit when any new comment appears after baseline.
- Author-gated: continue polling until a new comment from a target author appears.

State can be persisted across invocations via --state-file so the loop survives
context compaction or agent restarts.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_CANONICAL_AUTHOR_ALIASES: dict[str, set[str]] = {
    "codex": {
        "codex",
        "codex[bot]",
        "chatgpt-codex-connector",
        "chatgpt-codex-connector[bot]",
    },
}


@dataclass(frozen=True)
class PRComment:
    comment_id: int
    comment_type: str  # "issue" | "review"
    user_login: str
    created_at: str | None
    updated_at: str | None
    body: str
    url: str | None


def _run_gh(args: list[str]) -> str:
    proc = subprocess.run(
        ["gh", *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.strip() or "<no stderr>"
        raise RuntimeError(f"gh {' '.join(args)} failed: {stderr}")
    return proc.stdout


def _run_gh_json(args: list[str]) -> Any:
    output = _run_gh(args)
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON from gh {' '.join(args)}") from exc


def _infer_repo() -> str:
    return _run_gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]).strip()


def _infer_pr_number() -> int:
    raw = _run_gh(["pr", "view", "--json", "number", "--jq", ".number"]).strip()
    try:
        return int(raw)
    except ValueError as exc:
        raise RuntimeError(f"Unable to infer PR number from gh output: {raw!r}") from exc


def _flatten_paginated(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, list):
        flattened: list[dict[str, Any]] = []
        for item in payload:
            if isinstance(item, list):
                for inner in item:
                    if isinstance(inner, dict):
                        flattened.append(inner)
            elif isinstance(item, dict):
                flattened.append(item)
        return flattened
    if isinstance(payload, dict):
        return [payload]
    return []


def _normalize_whitespace(text: str) -> str:
    return " ".join(text.split())


def _fetch_comments(repo: str, pr_number: int) -> list[PRComment]:
    issue_payload = _run_gh_json(
        [
            "api",
            "--paginate",
            "--slurp",
            f"repos/{repo}/issues/{pr_number}/comments",
        ]
    )
    review_payload = _run_gh_json(
        [
            "api",
            "--paginate",
            "--slurp",
            f"repos/{repo}/pulls/{pr_number}/comments",
        ]
    )

    comments: list[PRComment] = []
    for comment in _flatten_paginated(issue_payload):
        cid = comment.get("id")
        if not isinstance(cid, int):
            continue
        user = comment.get("user")
        user_login = user.get("login") if isinstance(user, dict) else ""
        comments.append(
            PRComment(
                comment_id=cid,
                comment_type="issue",
                user_login=str(user_login or ""),
                created_at=(str(comment.get("created_at")) if comment.get("created_at") else None),
                updated_at=(str(comment.get("updated_at")) if comment.get("updated_at") else None),
                body=_normalize_whitespace(str(comment.get("body") or "")),
                url=(str(comment.get("html_url")) if comment.get("html_url") else None),
            )
        )

    for comment in _flatten_paginated(review_payload):
        cid = comment.get("id")
        if not isinstance(cid, int):
            continue
        user = comment.get("user")
        user_login = user.get("login") if isinstance(user, dict) else ""
        comments.append(
            PRComment(
                comment_id=cid,
                comment_type="review",
                user_login=str(user_login or ""),
                created_at=(str(comment.get("created_at")) if comment.get("created_at") else None),
                updated_at=(str(comment.get("updated_at")) if comment.get("updated_at") else None),
                body=_normalize_whitespace(str(comment.get("body") or "")),
                url=(str(comment.get("html_url")) if comment.get("html_url") else None),
            )
        )

    comments.sort(key=lambda c: (c.created_at or "", c.comment_id))
    return comments


def _author_aliases(author: str) -> set[str]:
    normalized = author.strip().lower()
    aliases = {normalized}

    # Add canonical alias families (bidirectional).
    for family in _CANONICAL_AUTHOR_ALIASES.values():
        if normalized in family:
            aliases.update(family)

    if normalized.endswith("[bot]"):
        stripped = normalized.removesuffix("[bot]").strip()
        if stripped:
            aliases.add(stripped)
            for family in _CANONICAL_AUTHOR_ALIASES.values():
                if stripped in family:
                    aliases.update(family)
    else:
        aliases.add(f"{normalized}[bot]")
    return aliases


def _is_author_match(login: str, author: str) -> bool:
    return login.strip().lower() in _author_aliases(author)


def _load_state(path: Path | None) -> set[int]:
    if path is None or not path.exists():
        return set()
    try:
        raw = json.loads(path.read_text())
    except Exception:
        return set()
    if not isinstance(raw, dict):
        return set()
    ids = raw.get("seen_comment_ids")
    if not isinstance(ids, list):
        return set()
    seen: set[int] = set()
    for value in ids:
        if isinstance(value, int):
            seen.add(value)
    return seen


def _save_state(path: Path | None, *, repo: str, pr_number: int, seen_ids: set[int]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "repo": repo,
        "pr_number": pr_number,
        "seen_comment_ids": sorted(seen_ids),
        "updated_at_epoch": int(time.time()),
    }
    path.write_text(json.dumps(payload, indent=2) + "\n")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Wait for new PR comments via gh CLI.",
    )
    parser.add_argument("--repo", help="GitHub repo in owner/name format. Auto-detected if omitted.")
    parser.add_argument("--pr", type=int, help="PR number. Auto-detected from current branch if omitted.")
    parser.add_argument("--interval", type=float, default=30.0, help="Polling interval in seconds (default: 30).")
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=0,
        help="Stop waiting after this many seconds (0 = no timeout).",
    )
    parser.add_argument(
        "--author",
        help=(
            "Target author login "
            "(e.g. codex, codex[bot], chatgpt-codex-connector[bot])."
        ),
    )
    parser.add_argument(
        "--require-author",
        action="store_true",
        help="Only exit when a new comment from --author appears.",
    )
    parser.add_argument(
        "--state-file",
        help="Optional JSON file for persisting seen comment IDs across invocations.",
    )
    parser.add_argument(
        "--baseline-now",
        action="store_true",
        help="Ignore saved state and reset baseline to current comments.",
    )
    return parser.parse_args()


def _serialize_comments(comments: list[PRComment]) -> list[dict[str, Any]]:
    serialized: list[dict[str, Any]] = []
    for comment in comments:
        serialized.append(
            {
                "id": comment.comment_id,
                "type": comment.comment_type,
                "user_login": comment.user_login,
                "created_at": comment.created_at,
                "updated_at": comment.updated_at,
                "url": comment.url,
                "body": comment.body,
            }
        )
    return serialized


def main() -> int:
    args = _parse_args()

    if args.require_author and not args.author:
        print("--require-author requires --author", file=sys.stderr)
        return 2

    try:
        repo = args.repo or _infer_repo()
        pr_number = args.pr or _infer_pr_number()
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    state_path = Path(args.state_file).expanduser() if args.state_file else None

    try:
        initial_comments = _fetch_comments(repo, pr_number)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    current_ids = {c.comment_id for c in initial_comments}
    seen_ids = set() if args.baseline_now else _load_state(state_path)
    if not seen_ids:
        seen_ids = set(current_ids)

    _save_state(state_path, repo=repo, pr_number=pr_number, seen_ids=seen_ids)

    author_baseline_count = 0
    if args.author:
        author_baseline_count = sum(1 for c in initial_comments if _is_author_match(c.user_login, args.author))

    started_at = time.time()

    while True:
        if args.timeout_seconds > 0 and (time.time() - started_at) >= args.timeout_seconds:
            timeout_payload = {
                "status": "timeout",
                "repo": repo,
                "pr_number": pr_number,
                "interval_seconds": args.interval,
                "timeout_seconds": args.timeout_seconds,
                "author": args.author,
                "require_author": bool(args.require_author),
                "seen_comment_count": len(seen_ids),
            }
            print(json.dumps(timeout_payload, indent=2))
            return 124

        time.sleep(max(args.interval, 1.0))

        try:
            latest_comments = _fetch_comments(repo, pr_number)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 2

        new_comments = [c for c in latest_comments if c.comment_id not in seen_ids]
        if not new_comments:
            continue

        seen_ids.update(c.comment_id for c in new_comments)
        _save_state(state_path, repo=repo, pr_number=pr_number, seen_ids=seen_ids)

        author_new_comments: list[PRComment] = []
        if args.author:
            author_new_comments = [
                c for c in new_comments if _is_author_match(c.user_login, args.author)
            ]

        if args.require_author and args.author and not author_new_comments:
            continue

        payload = {
            "status": "new_comments",
            "repo": repo,
            "pr_number": pr_number,
            "interval_seconds": args.interval,
            "author": args.author,
            "require_author": bool(args.require_author),
            "baseline_total_count": len(current_ids),
            "baseline_author_count": author_baseline_count,
            "new_total_count": len(new_comments),
            "new_author_count": len(author_new_comments),
            "new_comments": _serialize_comments(new_comments),
            "new_author_comments": _serialize_comments(author_new_comments),
        }
        print(json.dumps(payload, indent=2))
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
