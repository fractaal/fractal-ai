"""Codex CLI session provider — reads ~/.codex/sessions/YYYY/MM/DD/ JSONL.

Real Codex event types (verified against live data):
  Top-level: session_meta, response_item, event_msg, turn_context
  response_item payload types: function_call, function_call_output,
    reasoning, message, tool_search_call, tool_search_output
  Content item types: input_text (user), output_text (assistant)
  Roles: user, assistant, developer
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from common import NormalizedEvent, SessionMeta, Provider, clip, normalize_whitespace, load_jsonl


CODEX_ROOT = Path.home() / ".codex" / "sessions"


class CodexProvider(Provider):
    name = "codex"
    label = "Codex"

    def __init__(self, root: Path | None = None):
        self.root = root or CODEX_ROOT

    def iter_session_files(self) -> Iterable[Path]:
        if not self.root.exists():
            return []
        files: list[Path] = []
        for path in self.root.rglob("*.jsonl"):
            files.append(path)
        return sorted(files)

    def session_id_from_path(self, path: Path) -> str:
        stem = path.stem
        if stem.startswith("rollout-"):
            stem = stem[len("rollout-"):]
        return stem

    def bucket_from_path(self, path: Path) -> str:
        parts = path.relative_to(self.root).parts
        if len(parts) >= 3:
            return "/".join(parts[:3])
        return str(path.parent)

    def session_name(self, path: Path, events: list[dict[str, Any]] | None = None) -> str:
        raw = events if events is not None else load_jsonl(path)
        for event in raw:
            if event.get("type") == "response_item":
                payload = event.get("payload", {})
                if payload.get("type") == "message" and payload.get("role") == "user":
                    text = self._payload_text(payload)
                    if text and not self._is_injected_context(text):
                        return clip(text, 80)
        return ""

    def summarize(self, path: Path) -> SessionMeta:
        events = load_jsonl(path)
        sid = ""
        bucket = self.bucket_from_path(path)

        started_at = ended_at = cwd = git_branch = model = ""
        user_count = assistant_count = tool_use_count = 0
        first_user = last_assistant = ""

        for event in events:
            ts = event.get("timestamp")
            if isinstance(ts, str):
                if not started_at:
                    started_at = ts
                ended_at = ts

            etype = event.get("type")

            if etype == "session_meta":
                payload = event.get("payload", {})
                if not sid:
                    sid = payload.get("id", "")
                if not cwd:
                    cwd = payload.get("cwd", "")
                if not model:
                    model = self._extract_model_from_meta(payload)

            elif etype == "response_item":
                payload = event.get("payload", {})
                ptype = payload.get("type", "")
                role = payload.get("role", "")

                if ptype == "message":
                    text = self._payload_text(payload)
                    if role == "assistant":
                        assistant_count += 1
                        if text:
                            last_assistant = clip(text, 200)
                    elif role == "user":
                        if not self._is_injected_context(text):
                            user_count += 1
                            if not first_user and text:
                                first_user = clip(text, 200)

                elif ptype in ("function_call", "custom_tool_call", "tool_search_call"):
                    tool_use_count += 1

        if not sid:
            sid = self.session_id_from_path(path)
        name = first_user[:80] if first_user else ""

        return SessionMeta(
            path=path,
            harness="Codex",
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
            model=model,
        )

    def load_events(self, path: Path, *, include_meta: bool = False, include_thinking: bool = False) -> list[NormalizedEvent]:
        raw = load_jsonl(path)
        events: list[NormalizedEvent] = []
        for event in raw:
            etype = event.get("type")
            ts = str(event.get("timestamp") or "")

            if etype == "response_item":
                payload = event.get("payload", {})
                ptype = payload.get("type", "")
                role = payload.get("role", "")

                if ptype == "message":
                    text = self._payload_text(payload)
                    if text and role in ("user", "assistant"):
                        events.append(NormalizedEvent(
                            timestamp=ts, role=role, content=text, harness="Codex",
                        ))

                elif ptype in ("function_call", "custom_tool_call"):
                    tool_name = payload.get("name", "unknown-tool")
                    if include_meta:
                        args_str = payload.get("arguments", "")
                        events.append(NormalizedEvent(
                            timestamp=ts, role="tool_use",
                            content=f"{tool_name} {clip(args_str if isinstance(args_str, str) else json.dumps(args_str, ensure_ascii=False), 180)}",
                            harness="Codex", tool_name=tool_name,
                        ))
                    else:
                        events.append(NormalizedEvent(
                            timestamp=ts, role="tool_use", content=tool_name,
                            harness="Codex", tool_name=tool_name,
                        ))

                elif ptype in ("function_call_output", "custom_tool_call_output"):
                    output = payload.get("output", "")
                    if include_meta and output:
                        events.append(NormalizedEvent(
                            timestamp=ts, role="tool_result",
                            content=clip(output, 220), harness="Codex",
                        ))

                elif ptype == "reasoning" and include_meta:
                    summary = payload.get("summary")
                    if isinstance(summary, list) and summary:
                        text = " ".join(
                            s.get("text", "") for s in summary
                            if isinstance(s, dict) and s.get("text")
                        )
                    else:
                        text = ""
                    if text:
                        events.append(NormalizedEvent(
                            timestamp=ts, role="thinking",
                            content=clip(text, 180), harness="Codex",
                        ))

                elif ptype in ("tool_search_call", "tool_search_output", "web_search_call") and include_meta:
                    events.append(NormalizedEvent(
                        timestamp=ts, role="meta",
                        content=clip(json.dumps(payload, ensure_ascii=False), 280),
                        harness="Codex",
                    ))

            elif etype == "session_meta" and include_meta:
                payload = event.get("payload", {})
                events.append(NormalizedEvent(
                    timestamp=ts, role="meta",
                    content=f"session {payload.get('id', '?')} cwd={payload.get('cwd', '?')} model={payload.get('model_provider', '?')}",
                    harness="Codex",
                ))

        return events

    @staticmethod
    def _extract_model_from_meta(payload: dict[str, Any]) -> str:
        import re
        bi = payload.get("base_instructions")
        if isinstance(bi, dict):
            text = bi.get("text", "")
        elif isinstance(bi, str):
            text = bi
        else:
            text = ""
        m = re.search(r"based on ([\w.-]+)", text, re.IGNORECASE)
        if m:
            return m.group(1).lower()
        return payload.get("model_provider", "")

    @staticmethod
    def _is_injected_context(text: str) -> bool:
        if not text:
            return False
        stripped = text.lstrip()
        return stripped.startswith(("# AGENTS.md instructions", "<permissions instructions>", "# CLAUDE.md"))

    def _payload_text(self, payload: dict[str, Any]) -> str:
        content = payload.get("content")
        if isinstance(content, str):
            return normalize_whitespace(content)
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict):
                    itype = item.get("type", "")
                    if itype in ("input_text", "output_text", "text"):
                        text = item.get("text")
                        if isinstance(text, str) and text.strip():
                            parts.append(text)
            return normalize_whitespace(" ".join(parts))
        return ""
