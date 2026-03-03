#!/usr/bin/env python3
"""Post a Codex review ping on a PR, then wait for new Codex comments.

This wraps:
1) `gh pr comment ... --body "@codex review"`
2) `wait_for_pr_comments.py --author codex --require-author ...`
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


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
    return proc.stdout.strip()


def _infer_repo() -> str:
    return _run_gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])


def _infer_pr_number() -> int:
    raw = _run_gh(["pr", "view", "--json", "number", "--jq", ".number"])
    try:
        return int(raw)
    except ValueError as exc:
        raise RuntimeError(f"Unable to infer PR number from gh output: {raw!r}") from exc


def _default_state_path(repo: str, pr_number: int) -> Path:
    repo_token = repo.replace("/", "-")
    return Path(".codex/review-loop") / f"{repo_token}-pr-{pr_number}.json"


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ping @codex review and wait for new Codex comments.",
    )
    parser.add_argument("--repo", help="GitHub repo in owner/name format. Auto-detected if omitted.")
    parser.add_argument("--pr", type=int, help="PR number. Auto-detected if omitted.")
    parser.add_argument(
        "--message",
        default="@codex review",
        help="Comment body used to request Codex review.",
    )
    parser.add_argument(
        "--author",
        default="codex",
        help="Target reviewer login to wait for (default: codex).",
    )
    parser.add_argument(
        "--any-author",
        action="store_true",
        help="Wait for any new comments instead of requiring --author comments.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=30.0,
        help="Polling interval in seconds for waiting script (default: 30).",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=0,
        help="Stop waiting after this many seconds (0 = no timeout).",
    )
    parser.add_argument(
        "--state-file",
        help="State file path. Default: .codex/review-loop/<repo>-pr-<n>.json",
    )
    parser.add_argument(
        "--baseline-now",
        action="store_true",
        help="Reset baseline before waiting (ignore existing state file).",
    )
    parser.add_argument(
        "--skip-ping",
        action="store_true",
        help="Do not post the review ping comment; only perform waiting.",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()

    try:
        repo = args.repo or _infer_repo()
        pr_number = args.pr or _infer_pr_number()
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    state_path = Path(args.state_file) if args.state_file else _default_state_path(repo, pr_number)
    state_path = state_path.expanduser()
    state_path.parent.mkdir(parents=True, exist_ok=True)

    if not args.skip_ping:
        try:
            result = _run_gh([
                "pr",
                "comment",
                str(pr_number),
                "--repo",
                repo,
                "--body",
                args.message,
            ])
            if result:
                print(result, file=sys.stderr)
        except RuntimeError as exc:
            print(str(exc), file=sys.stderr)
            return 2

    wait_script = Path(__file__).resolve().parent / "wait_for_pr_comments.py"
    cmd = [
        sys.executable,
        str(wait_script),
        "--repo",
        repo,
        "--pr",
        str(pr_number),
        "--interval",
        str(args.interval),
        "--timeout-seconds",
        str(args.timeout_seconds),
        "--state-file",
        str(state_path),
    ]

    if args.baseline_now:
        cmd.append("--baseline-now")

    if not args.any_author:
        cmd.extend(["--author", args.author, "--require-author"])

    proc = subprocess.run(cmd, check=False)
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
