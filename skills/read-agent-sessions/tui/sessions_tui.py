#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["textual>=0.80"]
# ///
"""
agent-sessions-tui — a Textual TUI over the read-agent-sessions engine.

Browse, filter, and inspect agent session transcripts across Claude Code, Pi,
and Codex CLI from one window. Reuses the exact provider/summarize/load_events
machinery the `read-agent-sessions` CLI uses — this is purely a front end.

Search modes (driven from the one search box):
  - plain text            → live, in-memory metadata filter (every keystroke)
  - `g: <term>` + Enter   → raw lexical grep across transcript JSONL
  - `s: <term>` + Enter   → semantic search via qmd over prerendered corpus

Startup is instant after the first run: session summaries are cached on disk
keyed by (path, mtime, size); a background pass refreshes anything new and
streams the newest sessions into the list first.
"""
from __future__ import annotations

import asyncio
import json
import os
import shutil
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

# ── Wire in the read-agent-sessions engine (sibling scripts/ dir) ──────────
SCRIPTS_DIR = (Path(__file__).resolve().parent.parent / "scripts")
sys.path.insert(0, str(SCRIPTS_DIR))

from common import SessionMeta, NormalizedEvent  # noqa: E402
from provider_claude import ClaudeProvider  # noqa: E402
from provider_pi import PiProvider  # noqa: E402
from provider_codex import CodexProvider  # noqa: E402

from rich.text import Text  # noqa: E402

from textual import work  # noqa: E402
from textual.app import App, ComposeResult  # noqa: E402
from textual.binding import Binding  # noqa: E402
from textual.containers import Horizontal, Vertical  # noqa: E402
from textual.widgets import (  # noqa: E402
    DataTable,
    Footer,
    Header,
    Input,
    RichLog,
    Static,
)
from textual.widgets.data_table import RowDoesNotExist  # noqa: E402


PROVIDERS = {p.name: p for p in (ClaudeProvider(), PiProvider(), CodexProvider())}
CACHE_PATH = Path.home() / ".cache" / "agent-sessions-tui" / "index.json"

HARNESS_GLYPH = {"Claude": "C", "Pi": "π", "Codex": "X"}
HARNESS_STYLE = {"Claude": "bold #d97757", "Pi": "bold #8b5cf6", "Codex": "bold #10a37f"}


# ── Index / cache layer ────────────────────────────────────────────────────

def _meta_to_record(meta: SessionMeta, st: os.stat_result) -> dict:
    rec = asdict(meta)
    rec["path"] = str(meta.path)
    rec["_mtime"] = st.st_mtime
    rec["_size"] = st.st_size
    return rec


def load_cache() -> dict[str, dict]:
    try:
        return json.loads(CACHE_PATH.read_text("utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def save_cache(cache: dict[str, dict]) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = CACHE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(cache), "utf-8")
        tmp.replace(CACHE_PATH)
    except OSError:
        pass


def all_session_paths() -> list[tuple[str, Path]]:
    """(harness_name, path) for every session, newest-mtime first."""
    pairs: list[tuple[str, Path, float]] = []
    for name, provider in PROVIDERS.items():
        for path in provider.iter_session_files():
            try:
                mt = path.stat().st_mtime
            except OSError:
                continue
            pairs.append((name, path, mt))
    pairs.sort(key=lambda t: t[2], reverse=True)
    return [(n, p) for n, p, _ in pairs]


def summarize_one(harness: str, path: Path, cache: dict[str, dict]) -> dict | None:
    """Return a session record, reusing the disk cache when fresh."""
    key = str(path)
    try:
        st = path.stat()
    except OSError:
        return None
    hit = cache.get(key)
    if hit and hit.get("_mtime") == st.st_mtime and hit.get("_size") == st.st_size:
        return hit
    try:
        meta = PROVIDERS[harness].summarize(path)
    except Exception:
        return None
    rec = _meta_to_record(meta, st)
    cache[key] = rec
    return rec


def sort_key(rec: dict) -> str:
    return rec.get("ended_at") or rec.get("started_at") or ""


# ── The app ─────────────────────────────────────────────────────────────────

class SessionsTUI(App):
    CSS = """
    Screen { layers: base; }
    #body { height: 1fr; }
    #left { width: 42%; min-width: 34; border-right: solid $primary-darken-2; }
    #search { border: round $primary; margin: 0 1; }
    #status { height: 1; color: $text-muted; padding: 0 2; }
    #list { height: 1fr; }
    #right { width: 1fr; }
    #meta { height: auto; max-height: 40%; padding: 0 1; border-bottom: solid $primary-darken-2; }
    #transcript { height: 1fr; padding: 0 1; }
    DataTable { height: 1fr; }
    DataTable > .datatable--cursor { background: $primary; color: $text; }
    """

    BINDINGS = [
        Binding("ctrl+c,q", "quit", "Quit"),
        Binding("/", "focus_search", "Search"),
        Binding("escape", "leave_search", "List", show=False),
        Binding("tab", "focus_transcript", "Inspect"),
        Binding("ctrl+r", "rescan", "Rescan"),
        Binding("ctrl+t", "cycle_thinking", "Thinking"),
        Binding("ctrl+o", "open_externally", "Reveal"),
        Binding("ctrl+y", "copy_id", "Copy ID"),
        Binding("ctrl+h", "cycle_harness", "Harness"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.cache: dict[str, dict] = {}
        self.sessions: list[dict] = []          # all known records, sorted recent-first
        self._visible: list[dict] = []           # currently shown (post-filter)
        self.by_id: dict[str, dict] = {}        # session_id -> record
        self.harness_filter: str | None = None  # None=all, else 'claude'/'pi'/'codex'
        self.show_thinking = True
        self._filter_timer = None
        self._current_id: str | None = None

    # ---- compose ----
    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Horizontal(id="body"):
            with Vertical(id="left"):
                yield Input(
                    placeholder="filter…   g: grep raw   s: semantic (Enter to run)",
                    id="search",
                )
                yield Static("", id="status")
                table = DataTable(id="list", cursor_type="row", zebra_stripes=True)
                table.add_column("When", width=16)
                table.add_column("·", width=2)
                table.add_column("Session")
                yield table
            with Vertical(id="right"):
                yield Static("Select a session…", id="meta")
                yield RichLog(id="transcript", wrap=True, markup=False, highlight=False)
        yield Footer()

    def on_mount(self) -> None:
        self.title = "agent-sessions"
        self.sub_title = "Claude · Pi · Codex"
        self.cache = load_cache()
        self.focus_list()  # arrows browse immediately; `/` jumps to search
        self.refresh_index()

    # ---- indexing ----
    @work(exclusive=True, group="index")
    async def refresh_index(self) -> None:
        self.set_status("indexing…")
        pairs = await asyncio.to_thread(all_session_paths)
        records: dict[str, dict] = {}
        done = 0
        # Stream newest sessions in first so the list is useful immediately.
        for harness, path in pairs:
            rec = await asyncio.to_thread(summarize_one, harness, path, self.cache)
            done += 1
            if rec:
                records[rec["session_id"]] = rec
            if done % 25 == 0 or done == len(pairs):
                self.sessions = sorted(records.values(), key=sort_key, reverse=True)
                self.by_id = {r["session_id"]: r for r in self.sessions}
                self.apply_filter(self.query_one("#search", Input).value, run_remote=False)
                self.set_status(f"indexing… {done}/{len(pairs)}")
        # Drop cache entries for files that no longer exist.
        live = {str(p) for _, p in pairs}
        for stale in [k for k in self.cache if k not in live]:
            del self.cache[stale]
        await asyncio.to_thread(save_cache, self.cache)
        self.set_status_default()

    def action_rescan(self) -> None:
        self.refresh_index()

    # ---- filtering / search ----
    def on_input_changed(self, event: Input.Changed) -> None:
        if self._filter_timer is not None:
            self._filter_timer.stop()
        value = event.value
        # grep/semantic only fire on Enter; live-filter plain text.
        if value[:2].lower() in ("g:", "s:"):
            return
        self._filter_timer = self.set_timer(0.12, lambda: self.apply_filter(value))

    def on_input_submitted(self, event: Input.Submitted) -> None:
        value = event.value.strip()
        low = value[:2].lower()
        if low == "g:":
            self.run_grep(value[2:].strip())
        elif low == "s:":
            self.run_semantic(value[2:].strip())
        else:
            self.apply_filter(value)
        self.focus_list()

    def _matches(self, rec: dict, needle: str) -> bool:
        if not needle:
            return True
        hay = " ".join(str(rec.get(k) or "") for k in (
            "session_id", "name", "first_user", "last_assistant",
            "cwd", "git_branch", "bucket", "harness", "model",
        )).lower()
        return all(tok in hay for tok in needle.lower().split())

    def apply_filter(self, value: str, *, run_remote: bool = True) -> None:
        value = value or ""
        if value[:2].lower() in ("g:", "s:"):
            return
        recs = [r for r in self.sessions if self._passes_harness(r) and self._matches(r, value)]
        self.populate(recs)
        self.set_status_default(extra=f"{len(recs)} shown" + (f" · /{value}" if value else ""))

    def _passes_harness(self, rec: dict) -> bool:
        if not self.harness_filter:
            return True
        return (rec.get("harness") or "").lower() == self.harness_filter

    @work(exclusive=True, group="search", thread=True)
    def run_grep(self, term: str) -> None:
        if not term:
            return
        self.call_from_thread(self.set_status, f"grep '{term}'…")
        hits: dict[str, int] = {}
        needle = term.lower()
        for rec in self.sessions:
            if not self._passes_harness(rec):
                continue
            try:
                with open(rec["path"], "r", encoding="utf-8") as fh:
                    c = sum(1 for line in fh if needle in line.lower())
            except OSError:
                c = 0
            if c:
                hits[rec["session_id"]] = c
        recs = [dict(self.by_id[sid], _grep=hits[sid]) for sid in hits if sid in self.by_id]
        recs.sort(key=lambda r: r["_grep"], reverse=True)
        self.call_from_thread(self.populate, recs, True)
        self.call_from_thread(
            self.set_status, f"grep '{term}': {len(recs)} sessions (by hit count)"
        )

    @work(exclusive=True, group="search", thread=True)
    def run_semantic(self, term: str) -> None:
        if not term:
            return
        qmd = shutil.which("qmd")
        if not qmd:
            self.call_from_thread(self.set_status, "semantic: qmd not on PATH")
            return
        self.call_from_thread(self.set_status, f"semantic '{term}'… (qmd)")
        try:
            subprocess.run([qmd, "update"], capture_output=True, timeout=120)
            subprocess.run([qmd, "embed"], capture_output=True, timeout=600)
            out = subprocess.run(
                [qmd, "query", term, "--json", "--full", "-c", "sessions", "-n", "30"],
                capture_output=True, text=True, timeout=300,
            ).stdout
        except (subprocess.SubprocessError, OSError) as e:
            self.call_from_thread(self.set_status, f"semantic failed: {e}")
            return
        ordered = self._semantic_to_records(out)
        if not ordered:
            self.call_from_thread(self.set_status, f"semantic '{term}': no mappable hits")
            return
        self.call_from_thread(self.populate, ordered, True)
        self.call_from_thread(
            self.set_status, f"semantic '{term}': {len(ordered)} sessions (by relevance)"
        )

    def _semantic_to_records(self, qmd_json: str) -> list[dict]:
        """Map qmd `--full` results → session records via the body's session_id frontmatter.

        qmd's `file` field is a `qmd://` URI with a re-slugified name, so it
        can't be read as a path. The `--full` body, however, carries the
        prerendered frontmatter verbatim — `session_id:` is the stable key.
        """
        try:
            data = json.loads(qmd_json)
        except json.JSONDecodeError:
            return []
        results = data if isinstance(data, list) else data.get("results", [])
        ordered: list[dict] = []
        seen: set[str] = set()
        for item in results:
            if not isinstance(item, dict):
                continue
            sid = self._sid_from_body(item.get("body") or item.get("snippet") or "")
            if sid and sid in self.by_id and sid not in seen:
                seen.add(sid)
                ordered.append(self.by_id[sid])
        return ordered

    @staticmethod
    def _sid_from_body(body: str) -> str | None:
        for line in body.splitlines():
            if line.startswith("session_id:"):
                return line.split(":", 1)[1].strip()
        return None

    # ---- table population ----
    def populate(self, recs: list[dict], remote: bool = False) -> None:
        table = self.query_one("#list", DataTable)
        prev = self._current_id
        table.clear()
        self._visible = recs
        for rec in recs:
            harness = rec.get("harness", "")
            glyph = Text(HARNESS_GLYPH.get(harness, "?"), style=HARNESS_STYLE.get(harness, ""))
            when = (rec.get("ended_at") or rec.get("started_at") or "")[:16].replace("T", " ")
            label = rec.get("name") or rec.get("first_user") or rec.get("last_assistant") or "—"
            if remote and "_grep" in rec:
                label = f"[{rec['_grep']}] {label}"
            table.add_row(when, glyph, Text(label, no_wrap=True), key=rec["session_id"])
        if prev and any(r["session_id"] == prev for r in recs):
            try:
                table.move_cursor(row=table.get_row_index(prev))
            except (RowDoesNotExist, KeyError):
                pass

    # ---- selection / inspector ----
    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        sid = event.row_key.value
        if sid and sid != self._current_id:
            self._current_id = sid
            self.load_transcript(sid)

    @work(exclusive=True, group="render")
    async def load_transcript(self, sid: str) -> None:
        rec = self.by_id.get(sid)
        if not rec:
            return
        self.render_meta(rec)
        log = self.query_one("#transcript", RichLog)
        log.clear()
        log.write(Text("loading transcript…", style="dim italic"))
        harness = rec["harness"]
        path = Path(rec["path"])
        try:
            events = await asyncio.to_thread(
                PROVIDERS[harness.lower()].load_events, path,
                include_meta=False, include_thinking=self.show_thinking,
            )
        except Exception as e:
            log.clear()
            log.write(Text(f"failed to load: {e}", style="bold red"))
            return
        if self._current_id != sid:
            return  # user moved on
        log.clear()
        if not events:
            log.write(Text("(no rendered events)", style="dim italic"))
            return
        for ev in events:
            for chunk in self._render_event(ev):
                log.write(chunk)

    def _render_event(self, ev: NormalizedEvent):
        role = ev.role.split("/")[0]
        ts = (ev.timestamp or "")[11:19]
        content = (ev.content or "").rstrip()
        if not content and role not in ("tool_use",):
            return
        if role == "user":
            yield Text(f"▌ user  {ts}", style="bold #4ec9b0")
            yield Text(content, style="#d4d4d4")
        elif role == "assistant" or role == "text":
            yield Text(f"▌ assistant  {ts}", style="bold #569cd6")
            yield Text(content, style="#e8e8e8")
        elif role == "thinking":
            yield Text("· thinking", style="dim italic #b5cea8")
            yield Text(content, style="dim italic #9a9a9a")
        elif role == "tool_use":
            yield Text(f"⚙ tool → {ev.tool_name or content}", style="#dcdcaa")
            if ev.tool_name and content and content != ev.tool_name:
                yield Text(content, style="dim #c8c8a0")
        elif role == "tool_result":
            yield Text("↳ result", style="#c586c0")
            yield Text(content, style="dim #b0b0b0")
        else:
            yield Text(f"[{role}] {ts}", style="dim")
            yield Text(content, style="dim")
        yield Text("")  # spacer

    def render_meta(self, rec: dict) -> None:
        h = rec.get("harness", "")
        head = Text()
        head.append(f"{HARNESS_GLYPH.get(h, '?')} {h}", style=HARNESS_STYLE.get(h, "bold"))
        head.append("  ")
        head.append(rec.get("name") or rec.get("first_user") or "—", style="bold")
        head.append("\n")
        head.append(f"id {rec.get('session_id','')[:18]}", style="dim")
        head.append(f"   {rec.get('model') or '?'}", style="dim cyan")
        head.append("\n")
        head.append(
            f"{(rec.get('started_at') or '')[:19].replace('T',' ')}"
            f"  →  {(rec.get('ended_at') or '')[11:19]}",
            style="dim",
        )
        head.append("\n")
        head.append(
            f"{rec.get('user_count',0)}u / {rec.get('assistant_count',0)}a / "
            f"{rec.get('tool_use_count',0)} tools",
            style="dim",
        )
        head.append("\n")
        head.append(f"cwd {rec.get('cwd') or '?'}", style="dim")
        if rec.get("git_branch"):
            head.append(f"  ({rec['git_branch']})", style="dim green")
        self.query_one("#meta", Static).update(head)

    # ---- status line ----
    def set_status(self, text: str) -> None:
        self.query_one("#status", Static).update(text)

    def set_status_default(self, extra: str = "") -> None:
        hf = self.harness_filter or "all"
        think = "thinking:on" if self.show_thinking else "thinking:off"
        base = f"harness:{hf} · {think} · {len(self.sessions)} indexed"
        self.set_status(f"{base}{(' · ' + extra) if extra else ''}")

    # ---- actions ----
    def focus_list(self) -> None:
        self.query_one("#list", DataTable).focus()

    def action_focus_search(self) -> None:
        self.query_one("#search", Input).focus()

    def action_leave_search(self) -> None:
        self.focus_list()

    def action_focus_transcript(self) -> None:
        self.query_one("#transcript", RichLog).focus()

    def action_cycle_thinking(self) -> None:
        self.show_thinking = not self.show_thinking
        self.set_status_default()
        if self._current_id:
            self.load_transcript(self._current_id)

    def action_cycle_harness(self) -> None:
        order = [None, "claude", "pi", "codex"]
        self.harness_filter = order[(order.index(self.harness_filter) + 1) % len(order)]
        self.apply_filter(self.query_one("#search", Input).value, run_remote=False)

    def action_open_externally(self) -> None:
        rec = self.by_id.get(self._current_id or "")
        if not rec:
            return
        path = rec["path"]
        opener = shutil.which("xdg-open")
        if opener:
            subprocess.Popen([opener, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.set_status(f"opened {path}")
        else:
            self.set_status(path)

    def action_copy_id(self) -> None:
        rec = self.by_id.get(self._current_id or "")
        if not rec:
            return
        sid = rec["session_id"]
        copied = False
        if shutil.which("qdbus6"):
            try:
                subprocess.run(
                    ["qdbus6", "org.kde.klipper", "/klipper", "setClipboardContents", sid],
                    capture_output=True, timeout=5,
                )
                copied = True
            except (subprocess.SubprocessError, OSError):
                pass
        self.set_status(f"{'copied' if copied else 'id'}: {sid}")


if __name__ == "__main__":
    SessionsTUI().run()
