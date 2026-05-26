"""Shared types and utilities for read-agent-sessions."""
from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable


@dataclass
class NormalizedEvent:
    timestamp: str
    role: str  # user, assistant, system, tool_use, tool_result, thinking, meta, text
    content: str
    harness: str = ""
    tool_name: str | None = None


@dataclass
class SessionMeta:
    path: Path
    harness: str  # "Claude", "Pi", "Codex"
    session_id: str
    name: str
    bucket: str
    started_at: str
    ended_at: str
    cwd: str
    git_branch: str
    user_count: int
    assistant_count: int
    tool_use_count: int
    first_user: str
    last_assistant: str


class Provider(ABC):
    name: str
    label: str

    @abstractmethod
    def iter_session_files(self) -> Iterable[Path]: ...

    @abstractmethod
    def session_id_from_path(self, path: Path) -> str: ...

    @abstractmethod
    def bucket_from_path(self, path: Path) -> str: ...

    @abstractmethod
    def session_name(self, path: Path, events: list[dict[str, Any]] | None = None) -> str: ...

    @abstractmethod
    def summarize(self, path: Path) -> SessionMeta: ...

    @abstractmethod
    def load_events(self, path: Path, *, include_meta: bool = False) -> list[NormalizedEvent]: ...


def normalize_whitespace(text: str) -> str:
    return " ".join(text.split())


def clip(text: str, max_chars: int) -> str:
    text = normalize_whitespace(text)
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 1].rstrip() + "…"


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
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
