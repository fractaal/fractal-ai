"""Claude Code session provider — reads ~/.claude/projects/ JSONL + session registry."""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from common import NormalizedEvent, SessionMeta, Provider, clip, normalize_whitespace, load_jsonl


CLAUDE_ROOT = Path.home() / ".claude" / "projects"
CLAUDE_REGISTRY = Path.home() / ".claude" / "sessions"


def _load_session_names() -> dict[str, str]:
    """Map sessionId → human name from the auto-rename registry."""
    names: dict[str, str] = {}
    if not CLAUDE_REGISTRY.exists():
        return names
    for f in CLAUDE_REGISTRY.glob("*.json"):
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
            sid = data.get("sessionId")
            name = data.get("name")
            if sid and name:
                names[sid] = name
        except (json.JSONDecodeError, OSError):
            continue
    return names


def _is_local_command_noise(text: str) -> bool:
    stripped = text.strip()
    return stripped.startswith((
        "<local-command-caveat>",
        "<command-name>",
        "<local-command-stdout>",
        "<local-command-stderr>",
    ))


def _extract_content_parts(
    content: Any, *, include_meta: bool
) -> list[NormalizedEvent]:
    """Walk a Claude message.content array and yield normalized events."""
    if isinstance(content, str):
        if not include_meta and _is_local_command_noise(content):
            return []
        return [NormalizedEvent(timestamp="", role="text", content=content)]

    if not isinstance(content, list):
        return []

    parts: list[NormalizedEvent] = []
    for item in content:
        if not isinstance(item, dict):
            continue
        item_type = item.get("type")
        if item_type == "text":
            text = item.get("text")
            if isinstance(text, str) and text.strip():
                if not include_meta and _is_local_command_noise(text):
                    continue
                parts.append(NormalizedEvent(timestamp="", role="text", content=text))
        elif item_type == "tool_use":
            name = str(item.get("name") or "unknown-tool")
            tool_input = item.get("input")
            if include_meta:
                parts.append(NormalizedEvent(
                    timestamp="", role="tool_use", content=f"{name} {clip(json.dumps(tool_input, ensure_ascii=False), 180)}",
                    tool_name=name,
                ))
            else:
                parts.append(NormalizedEvent(
                    timestamp="", role="tool_use", content=name, tool_name=name,
                ))
        elif item_type == "tool_result":
            content_value = item.get("content")
            rendered = _render_tool_result(content_value)
            if rendered:
                parts.append(NormalizedEvent(timestamp="", role="tool_result", content=rendered))
        elif include_meta and item_type == "thinking":
            thinking = item.get("thinking")
            if isinstance(thinking, str) and thinking.strip():
                parts.append(NormalizedEvent(timestamp="", role="thinking", content=clip(thinking, 180)))
    return parts


def _render_tool_result(content: Any) -> str:
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


class ClaudeProvider(Provider):
    name = "claude"
    label = "Claude"

    def __init__(self, root: Path | None = None):
        self.root = root or CLAUDE_ROOT
        self._session_names: dict[str, str] | None = None

    @property
    def session_names(self) -> dict[str, str]:
        if self._session_names is None:
            self._session_names = _load_session_names()
        return self._session_names

    def iter_session_files(self) -> Iterable[Path]:
        if not self.root.exists():
            return []
        files: list[Path] = []
        for path in self.root.rglob("*.jsonl"):
            if "subagents" in path.parts:
                continue
            if path.name.startswith("agent-"):
                continue
            files.append(path)
        return sorted(files)

    def session_id_from_path(self, path: Path) -> str:
        return path.stem

    def bucket_from_path(self, path: Path) -> str:
        return path.parent.name

    def session_name(self, path: Path, events: list[dict[str, Any]] | None = None) -> str:
        sid = self.session_id_from_path(path)
        return self.session_names.get(sid, "")

    def summarize(self, path: Path) -> SessionMeta:
        events = load_jsonl(path)
        sid = self.session_id_from_path(path)
        bucket = self.bucket_from_path(path)
        name = self.session_name(path, events)

        started_at = ended_at = cwd = git_branch = ""
        user_count = assistant_count = tool_use_count = 0
        first_user = last_assistant = ""

        for event in events:
            ts = event.get("timestamp")
            if isinstance(ts, str):
                if not started_at:
                    started_at = ts
                ended_at = ts

            if not cwd:
                v = event.get("cwd")
                if isinstance(v, str):
                    cwd = v

            if not git_branch:
                v = event.get("gitBranch")
                if isinstance(v, str):
                    git_branch = v

            event_type = event.get("type")
            message = event.get("message")

            if event_type == "user":
                user_count += 1
                if not first_user:
                    parts = _extract_content_parts(
                        message.get("content") if isinstance(message, dict) else event.get("content"),
                        include_meta=False,
                    )
                    joined = normalize_whitespace(" ".join(p.content for p in parts))
                    if joined:
                        first_user = clip(joined, 200)
            elif event_type == "assistant":
                assistant_count += 1
                parts = _extract_content_parts(
                    message.get("content") if isinstance(message, dict) else event.get("content"),
                    include_meta=False,
                )
                joined = normalize_whitespace(" ".join(p.content for p in parts))
                if joined:
                    last_assistant = clip(joined, 200)

            if isinstance(message, dict):
                content = message.get("content")
                if isinstance(content, list):
                    tool_use_count += sum(
                        1 for item in content
                        if isinstance(item, dict) and item.get("type") == "tool_use"
                    )

        return SessionMeta(
            path=path,
            harness="Claude",
            session_id=sid,
            name=name,
            bucket=bucket,
            started_at=started_at,
            ended_at=ended_at,
            cwd=cwd,
            git_branch=git_branch,
            user_count=user_count,
            assistant_count=assistant_count,
            tool_use_count=tool_use_count,
            first_user=first_user,
            last_assistant=last_assistant,
        )

    def load_events(self, path: Path, *, include_meta: bool = False) -> list[NormalizedEvent]:
        raw = load_jsonl(path)
        events: list[NormalizedEvent] = []
        for event in raw:
            event_type = str(event.get("type") or "unknown")
            if not include_meta and event.get("isMeta"):
                continue
            if event_type not in {"user", "assistant", "system"} and not include_meta:
                continue

            timestamp = str(event.get("timestamp") or "")
            subtype = event.get("subtype")
            role = event_type if not subtype else f"{event_type}/{subtype}"

            message = event.get("message")
            content = message.get("content") if isinstance(message, dict) else event.get("content")
            parts = _extract_content_parts(content, include_meta=include_meta)

            if not parts:
                if include_meta:
                    events.append(NormalizedEvent(
                        timestamp=timestamp, role=role,
                        content=clip(json.dumps(event, ensure_ascii=False), 280),
                        harness="Claude",
                    ))
                continue

            body = "\n".join(clip(p.content, 280) for p in parts if p.content.strip())
            if body:
                events.append(NormalizedEvent(
                    timestamp=timestamp, role=role, content=body, harness="Claude",
                    tool_name=next((p.tool_name for p in parts if p.tool_name), None),
                ))
        return events

