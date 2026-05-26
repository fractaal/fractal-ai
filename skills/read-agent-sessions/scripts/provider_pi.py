"""Pi session provider — reads ~/.pi/agent/sessions/ JSONL."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from common import NormalizedEvent, SessionMeta, Provider, clip, normalize_whitespace, load_jsonl


PI_ROOT = Path.home() / ".pi" / "agent" / "sessions"


class PiProvider(Provider):
    name = "pi"
    label = "Pi"

    def __init__(self, root: Path | None = None):
        self.root = root or PI_ROOT

    def iter_session_files(self) -> Iterable[Path]:
        if not self.root.exists():
            return []
        files: list[Path] = []
        for path in self.root.rglob("*.jsonl"):
            files.append(path)
        return sorted(files)

    def session_id_from_path(self, path: Path) -> str:
        # Filename: 2026-05-17T17-23-50-461Z_019e36f7-323d-7f61-9bd2-305bdfda894e.jsonl
        stem = path.stem
        parts = stem.split("_", 1)
        return parts[1] if len(parts) > 1 else stem

    def bucket_from_path(self, path: Path) -> str:
        return path.parent.name

    def session_name(self, path: Path, events: list[dict[str, Any]] | None = None) -> str:
        raw = events if events is not None else load_jsonl(path)
        name = ""
        for event in raw:
            if event.get("type") == "session_info":
                v = event.get("name")
                if isinstance(v, str) and v.strip():
                    name = v.strip()
            elif event.get("type") == "custom" and event.get("customType") == "pi-auto-rename":
                data = event.get("data")
                if isinstance(data, dict):
                    v = data.get("name")
                    if isinstance(v, str) and v.strip():
                        name = v.strip()
        return name

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

            etype = event.get("type")

            if etype == "session":
                if not cwd:
                    v = event.get("cwd")
                    if isinstance(v, str):
                        cwd = v

            if etype == "message":
                msg = event.get("message", {})
                role = msg.get("role", "")
                text = self._message_text(msg)

                if role == "user":
                    user_count += 1
                    if not first_user and text:
                        first_user = clip(text, 200)
                elif role == "assistant":
                    assistant_count += 1
                    if text:
                        last_assistant = clip(text, 200)
                elif role == "toolResult":
                    tool_use_count += 1

        return SessionMeta(
            path=path,
            harness="Pi",
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
            etype = event.get("type")
            ts = str(event.get("timestamp") or "")

            if etype == "message":
                msg = event.get("message", {})
                role = msg.get("role", "")

                if role in ("user", "assistant"):
                    text = self._message_text(msg)
                    if text:
                        events.append(NormalizedEvent(
                            timestamp=ts, role=role, content=text, harness="Pi",
                        ))
                elif role == "toolResult":
                    tool_name = msg.get("toolName", "unknown-tool")
                    text = self._message_text(msg)
                    if include_meta or text:
                        events.append(NormalizedEvent(
                            timestamp=ts, role="tool_result",
                            content=f"[{tool_name}] {clip(text, 220)}" if text else f"[{tool_name}]",
                            harness="Pi", tool_name=tool_name,
                        ))

            elif etype == "model_change" and include_meta:
                provider = event.get("provider", "")
                model = event.get("modelId", "")
                events.append(NormalizedEvent(
                    timestamp=ts, role="meta",
                    content=f"model → {provider}/{model}", harness="Pi",
                ))

            elif etype in ("session", "session_info", "thinking_level_change", "custom"):
                if include_meta:
                    events.append(NormalizedEvent(
                        timestamp=ts, role="meta",
                        content=clip(json.dumps(event, ensure_ascii=False), 280),
                        harness="Pi",
                    ))

        return events

    def _message_text(self, msg: dict[str, Any]) -> str:
        content = msg.get("content")
        if isinstance(content, str):
            return normalize_whitespace(content)
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    text = item.get("text")
                    if isinstance(text, str) and text.strip():
                        parts.append(text)
            return normalize_whitespace(" ".join(parts))
        return ""

