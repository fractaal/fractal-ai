"""Prerender agent sessions as Markdown files for Obsidian + qmd indexing."""
from __future__ import annotations

import json
import platform
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from common import SessionMeta, Provider, NormalizedEvent, clip, normalize_whitespace, load_jsonl
from provider_claude import ClaudeProvider
from provider_pi import PiProvider
from provider_codex import CodexProvider


DEFAULT_VAULT = Path.home() / "Dropbox" / "DropsyncFiles" / "MindPalace"
SESSIONS_DIR = "Sessions"
MANIFEST_NAME = ".prerender-manifest.json"
MIN_USER_TURNS = 3


ALL_PROVIDERS: list[Provider] = [
    ClaudeProvider(),
    PiProvider(),
    CodexProvider(),
]


def slugify(text: str) -> str:
    """Convert text to a filesystem-safe slug: lowercase, hyphens, no special chars."""
    text = text.strip()
    # Strip status brackets like [Complete] or [In Progress]
    text = re.sub(r"^\[.*?\]\s*", "", text)
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-{2,}", "-", text)
    text = text.strip("-")
    if len(text) > 60:
        text = text[:60].rsplit("-", 1)[0]
    return text or "untitled"


def model_slug(model: str) -> str:
    """Normalize model ID for filenames: lowercase, dots become hyphens."""
    if not model:
        return "unknown"
    slug = model.lower().replace(".", "-").replace(" ", "-")
    return slug.strip("-")


HOSTNAME = platform.node().lower() or "unknown"


def session_filename(meta: SessionMeta) -> str:
    """Build filename: 2026-05-22.Session-Name.claude.claude-opus-4-7.unixboat.md"""
    date = (meta.started_at or meta.ended_at or "")[:10]
    if not date or len(date) != 10:
        date = "undated"
    name = slugify(meta.name or meta.first_user or "untitled")
    harness = meta.harness.lower()
    model = model_slug(meta.model)
    return f"{date}.{name}.{harness}.{model}.{HOSTNAME}.md"


def format_timestamp_short(ts: str) -> str:
    """2026-05-26T00:15:32.542Z → 00:15"""
    if not ts or len(ts) < 16:
        return ""
    return ts[11:16]


def render_session_to_markdown(
    provider: Provider, path: Path, meta: SessionMeta
) -> str:
    """Render a session JSONL into a clean Markdown document."""
    events = provider.load_events(path, include_meta=False, include_thinking=True)
    lines: list[str] = []

    # YAML frontmatter
    name_escaped = (meta.name or meta.first_user or "untitled").replace('"', '\\"')
    lines.append("---")
    lines.append(f"date: {(meta.started_at or '')[:10]}")
    lines.append(f"harness: {meta.harness.lower()}")
    lines.append(f"model: {meta.model or 'unknown'}")
    lines.append(f"session_id: {meta.session_id}")
    lines.append(f'name: "{name_escaped}"')
    lines.append(f"cwd: {meta.cwd or 'unknown'}")
    if meta.git_branch:
        lines.append(f"branch: {meta.git_branch}")
    lines.append(f"user_turns: {meta.user_count}")
    lines.append(f"assistant_turns: {meta.assistant_count}")
    lines.append(f"tool_uses: {meta.tool_use_count}")
    lines.append(f"host: {HOSTNAME}")
    lines.append(f"source: {meta.path}")
    lines.append("---")
    lines.append("")

    # Title
    display_name = meta.name or clip(meta.first_user or "Untitled Session", 80)
    lines.append(f"# {display_name}")
    lines.append("")

    # Metadata line
    time_range = ""
    start_short = format_timestamp_short(meta.started_at)
    end_short = format_timestamp_short(meta.ended_at)
    if start_short and end_short and start_short != end_short:
        time_range = f" {start_short}–{end_short}"
    elif start_short:
        time_range = f" {start_short}"

    lines.append(
        f"> **{meta.harness}** · {meta.model or 'unknown'} · "
        f"{(meta.started_at or '')[:10]}{time_range} · `{meta.cwd or '?'}`"
    )
    lines.append("")
    lines.append("---")
    lines.append("")

    # Conversation body — collect tool call chains, skip noise
    pending_tools: list[str] = []

    def flush_tools():
        nonlocal pending_tools
        if not pending_tools:
            return
        if len(pending_tools) == 1:
            lines.append(f"> Tool Call: {pending_tools[0]}")
        else:
            names = ", ".join(pending_tools)
            lines.append(f"> Tool Calls: {names} ({len(pending_tools)})")
        lines.append("")
        pending_tools = []

    for event in events:
        ts_short = format_timestamp_short(event.timestamp)
        ts_label = f" ({ts_short})" if ts_short else ""
        content = event.content.strip()
        if not content:
            continue

        # Skip tool results
        if event.role == "tool_result":
            continue

        # Collect tool calls into a chain
        if event.tool_name and event.role in ("assistant", "tool_use"):
            pending_tools.append(event.tool_name)
            continue

        # Non-tool event: flush any pending tool chain first
        flush_tools()

        # Strip inline [tool_use] / [tool_result] from mixed-content events
        cleaned_lines = []
        for line in content.split("\n"):
            stripped = line.strip()
            if stripped.startswith("[tool_use]"):
                pending_tools.append(stripped[len("[tool_use]"):].strip())
            elif stripped.startswith("[tool_result]"):
                continue
            else:
                cleaned_lines.append(line)

        # Flush any tools extracted from mixed content
        flush_tools()

        body = "\n".join(cleaned_lines).strip()
        if not body:
            continue

        if event.role == "user":
            lines.append(f"> User{ts_label}")
        elif event.role == "assistant":
            lines.append(f"> Assistant{ts_label}")
        elif event.role == "thinking":
            lines.append(f"> Thinking{ts_label}")
        else:
            lines.append(f"> {event.role}{ts_label}")

        lines.append("")
        lines.append("```")
        lines.append(body)
        lines.append("```")
        lines.append("")

    flush_tools()
    return "\n".join(lines)


def load_manifest(manifest_path: Path) -> dict[str, Any]:
    if manifest_path.exists():
        try:
            return json.loads(manifest_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {"rendered": {}}


def save_manifest(manifest_path: Path, manifest: dict[str, Any]) -> None:
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def prerender(
    output_dir: Path,
    *,
    force: bool = False,
    min_turns: int = MIN_USER_TURNS,
    dry_run: bool = False,
) -> int:
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / MANIFEST_NAME
    manifest = load_manifest(manifest_path)
    rendered_map: dict[str, str] = manifest.get("rendered", {})

    new_count = 0
    skip_count = 0
    error_count = 0

    for provider in ALL_PROVIDERS:
        for path in provider.iter_session_files():
            source_key = str(path)
            source_mtime = path.stat().st_mtime

            # Skip if already rendered and source hasn't changed
            if not force and source_key in rendered_map:
                prev = rendered_map[source_key]
                if isinstance(prev, dict) and prev.get("mtime", 0) >= source_mtime:
                    skip_count += 1
                    continue

            try:
                meta = provider.summarize(path)
            except Exception as e:
                print(f"  error summarizing {path}: {e}", file=sys.stderr)
                error_count += 1
                continue

            # Quality gate
            if meta.user_count < min_turns:
                skip_count += 1
                continue

            filename = session_filename(meta)
            out_path = output_dir / filename

            if dry_run:
                print(f"  would render: {filename} ({meta.harness}, {meta.user_count} turns)")
                new_count += 1
                continue

            try:
                # Clean up stale file if name changed
                prev = rendered_map.get(source_key)
                if isinstance(prev, dict) and prev.get("output") and prev["output"] != filename:
                    stale = output_dir / prev["output"]
                    if stale.exists():
                        stale.unlink()

                content = render_session_to_markdown(provider, path, meta)
                out_path.write_text(content, encoding="utf-8")
                rendered_map[source_key] = {
                    "mtime": source_mtime,
                    "output": filename,
                    "harness": meta.harness,
                    "session_id": meta.session_id,
                }
                new_count += 1
                print(f"  rendered: {filename}")
            except Exception as e:
                print(f"  error rendering {path}: {e}", file=sys.stderr)
                error_count += 1

    if not dry_run:
        manifest["rendered"] = rendered_map
        save_manifest(manifest_path, manifest)

    print(f"\n{new_count} rendered, {skip_count} skipped, {error_count} errors")
    return 0 if error_count == 0 else 1
