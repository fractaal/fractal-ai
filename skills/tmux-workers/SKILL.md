---
name: tmux-workers
description: >-
  Spawn, drive, and read back from tmux panes as shell workers or subagent
  workers. Use when you need to: run long-running jobs in parallel without
  blocking your main context, orchestrate multiple Claude CLI subagents via
  pane I/O, or interactively control shells and read their output programmatically.
  Keyword triggers: "run in parallel", "spawn a worker", "background agent",
  "tmux pane", "subagent in tmux".
---

# tmux Workers

## Overview

You are already running inside a tmux pane. The tmux server socket is live and you have full `tmux` access via `Bash`. This skill gives you a repeatable, disciplined pattern for:

1. **Shell workers** — run commands in isolated panes, tail their output, and clean up.
2. **Subagent workers** — spawn a `claude` CLI subagent in a pane, feed it a prompt, poll until done, and read the result back.
3. **Parallel fan-out** — spin up N workers at once, await all, collect results.
4. **Persistent peer agent** — run a peer agent (e.g. Codex) as a long-lived interactive REPL in a pane that both you *and the user* can drive. **Preferred for sustained peer-agent collaboration** — see Pattern 6.

## Prerequisites

- You must be inside a tmux session (`$TMUX` is set). Verify: `echo $TMUX_PANE`.
- `tmux` is on `$PATH`.
- For subagent workers: your chosen agent CLI is on `$PATH` (e.g. `claude`, `codex`, `sgpt`).

---

## Core Primitives

### Spawn a pane

```bash
PANE=$(tmux split-window -h -d -P -F "#{pane_id}")
# -h  = horizontal split (side by side); use -v for vertical
# -d  = do not switch focus to new pane
# -P  = print new pane info
# -F  = format: just the pane ID (%N)
```

### Send a command

```bash
tmux send-keys -t "$PANE" "your command here" Enter
```

### Read pane output (visible buffer)

```bash
tmux capture-pane -p -t "$PANE"
```

### Read full scrollback (all history)

```bash
tmux capture-pane -p -S - -t "$PANE"
```

### Kill a pane when done

```bash
tmux kill-pane -t "$PANE"
```

### List all panes in current window

```bash
tmux list-panes -F "#{pane_id} #{pane_pid} #{pane_current_command}"
```

---

## Pattern 1 — Shell Worker

Run a command in a background pane, poll until the shell prompt returns, then read output.

```bash
# 1. Spawn
PANE=$(tmux split-window -h -d -P -F "#{pane_id}")

# 2. Run
tmux send-keys -t "$PANE" "my-long-running-command 2>&1 | tee /tmp/worker-out.txt" Enter

# 3. Poll (check if command finished — prompt reappears)
scripts/poll_pane_done.sh "$PANE"

# 4. Read
cat /tmp/worker-out.txt

# 5. Cleanup
tmux kill-pane -t "$PANE"
```

**Tip:** Always `tee` output to a temp file. `capture-pane` only shows the visible viewport; the file gives you the full output regardless of scrollback limits.

---

## Pattern 2 — AI Subagent Worker

Spawn an agent CLI process in a pane, give it a task, and read the result.
`spawn_agent.sh` handles the full lifecycle. Use `--agent-cmd` to select the agent
(defaults to `claude -p`). Prompts are passed via a `mktemp` file — no quoting hell.
The output file is also `mktemp`-generated unless you supply `--out`.

```bash
# Simple — auto-generates a unique output file, prints its path to stdout
OUTFILE=$(scripts/spawn_agent.sh --prompt "Summarize foo.txt")
cat "$OUTFILE"

# With explicit output path and a different agent
scripts/spawn_agent.sh \
  --prompt "Explain this diff: $(git diff HEAD~1)" \
  --out /tmp/my-review.txt \
  --agent-cmd "codex" \
  --timeout 120
cat /tmp/my-review.txt
```

**Important:** The agent is instructed in the prompt to write its final answer to the output
file. Don't rely solely on `capture-pane` for long outputs — the buffer truncates.
Each run gets a unique file via `mktemp`, so parallel calls never collide.

---

## Pattern 3 — Parallel Fan-out

Spawn N workers at once, await all, then collect.

```bash
PANES=()
for i in 1 2 3; do
  P=$(tmux split-window -h -d -P -F "#{pane_id}")
  tmux send-keys -t "$P" "do-work-$i > /tmp/result-$i.txt 2>&1" Enter
  PANES+=("$P")
done

# Await all
for P in "${PANES[@]}"; do
  scripts/poll_pane_done.sh "$P"
done

# Collect
for i in 1 2 3; do
  echo "=== result $i ===" && cat /tmp/result-$i.txt
done

# Cleanup
for P in "${PANES[@]}"; do
  tmux kill-pane -t "$P"
done
```

---

## Polling — How to Know a Pane is Done

Use `scripts/poll_pane_done.sh`. It works by watching for the shell prompt to reappear after the last command line — a reliable signal that the foreground process exited.

Two strategies (the script uses both):

1. **Prompt sentinel**: check `capture-pane` for a prompt string (`$`, `❯`, `➜`) appearing after the command line.
2. **PID watch**: read the pane's foreground PID via `tmux display-message -p -t $PANE "#{pane_pid}"`, then check if child processes of that PID are gone.

For claude subagents, strategy 1 is more robust since the CLI spawns multiple child processes.

---

## Scripts

- `scripts/poll_pane_done.sh` — polls a pane until its shell prompt returns; exits 0 on done, 1 on timeout.
- `scripts/spawn_agent.sh` — full spawn-send-poll-read-cleanup cycle for a single subagent. Accepts `--agent-cmd` to select the agent binary; defaults to `claude -p`. Uses `mktemp` for both prompt and output files — no collisions.
- `scripts/fanout.sh` — parallel fan-out over N tasks, one pane each. Also accepts `--agent-cmd`.

---

## Pattern 4 — Visible AI Subagent (User Watches Live)

When the user wants to SEE the agent working in the pane (not just collect results), do NOT
use `spawn_agent.sh` (it redirects stdout to a file, making the pane blank). Instead, manually
spawn the pane and use `tee` so output goes to both the terminal AND a file:

```bash
# Write prompt to a temp file to avoid quoting issues
cat > /tmp/agent-prompt.txt << 'EOF'
Your prompt here...
EOF

# Spawn pane — output is VISIBLE and saved to file
OUTFILE=/tmp/agent-result.txt
PANE=$(tmux split-window -h -d -P -F "#{pane_id}")
tmux send-keys -t "$PANE" \
  "codex exec --full-auto \"\$(cat /tmp/agent-prompt.txt)\" 2>&1 | tee '$OUTFILE'; echo '===DONE===' >> '$OUTFILE'" Enter
```

**Key difference from Pattern 2:** `tee` replaces `>` so the user sees streaming output live.
Poll and read back the same way — check for `===DONE===` sentinel in the output file.

### Agent-specific commands

| Agent | Headless (non-interactive) | Flags |
|-------|---------------------------|-------|
| Claude | `claude -p "prompt"` | `--dangerously-skip-permissions` if aliased |
| Codex | `codex exec "prompt"` | `--full-auto` for sandboxed auto-approval |
| Gemini | `gemini -p "prompt"` | `--yolo` for auto-approval |

**Note:** When spawning Claude as a subagent from Claude, the inner Claude has no shared
context. You're just asking yourself the same question twice. Prefer Codex or Gemini for
genuine second opinions.

---

## Pattern 5 — Resume a Previous Subagent Session

Both Codex and Gemini persist sessions and support resuming with follow-up questions.
This lets you ask follow-ups without re-sending the full context.

**Always resume by explicit session ID, not `--last`.** If multiple agents are spawning
Codex/Gemini sessions concurrently, `--last` creates a race condition — you might
resume the wrong session.

### Gemini

```bash
# List saved sessions — note the UUID
gemini --list-sessions
# Output: 1. Your prompt here... (1 hour ago) [bff0d69a-c59a-4bf7-8524-6655fc297e64]

# Resume by UUID with a follow-up, visible in pane
PANE=$(tmux split-window -h -d -P -F "#{pane_id}")
tmux send-keys -t "$PANE" \
  "gemini --resume bff0d69a-c59a-4bf7-8524-6655fc297e64 -p 'Your follow-up' --yolo 2>&1 | tee /tmp/gemini-followup.txt" Enter
```

### Codex

```bash
# Session IDs are UUIDs embedded in filenames under ~/.codex/sessions/YYYY/MM/DD/
# e.g. rollout-2026-04-01T14-00-36-019d47a1-24ef-7232-9600-1c3392bbdd41.jsonl
# The UUID is everything after the timestamp: 019d47a1-24ef-7232-9600-1c3392bbdd41

# Resume by session UUID with a follow-up
PANE=$(tmux split-window -h -d -P -F "#{pane_id}")
tmux send-keys -t "$PANE" \
  "codex exec resume '019d47a1-24ef-7232-9600-1c3392bbdd41' --full-auto 'Your follow-up' 2>&1 | tee /tmp/codex-followup.txt" Enter
```

### Capturing session ID at spawn time

To make resume reliable, capture the session ID when you first spawn the agent.
For Codex, extract it from the session file created during the run:

```bash
# After Codex finishes, find the session file it just wrote
CODEX_SESSION=$(ls -t ~/.codex/sessions/$(date +%Y/%m/%d)/ | head -1 | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')
echo "Codex session: $CODEX_SESSION"
```

For Gemini, the UUID is shown in `--list-sessions` output.

**Important:** Headless sessions (`codex exec`, `gemini -p`) DO save session history and
are resumable. You don't need to have run them interactively first.

---

## Pattern 6 — Persistent Interactive Peer Agent ★ preferred for sustained collaboration

Patterns 2 / 4 / 5 spawn a *headless* agent (`codex exec`, `claude -p`) for a
one-shot job. When a peer agent instead **owns a workstream** — many briefs and
follow-ups across a long session (e.g. Codex implementing a service's backend
while you build the frontend) — run it as a **persistent interactive REPL in a
tmux pane** instead. This is the **preferred** shape for sustained collaboration.

**Why preferred:**

- The pane is **inspectable** — the user watches the peer work live.
- The pane is **interjectable** — the user can *type into the same pane* as a
  third party, to steer or correct the peer mid-task. A headless `codex exec`
  is a black box; nobody can see or touch it.
- The REPL **keeps full context** across every follow-up — no `codex exec
  resume` / session-ID juggling (Pattern 5). Just send the next task.

(`codex exec` / Patterns 2 & 4 are still right for a genuine *one-shot*
consultation — a review, a single question. Pattern 6 is for an ongoing peer.)

### Spawn — interactive, NOT `exec`

```bash
CODEX_PANE=$(tmux split-window -h -d -P -F '#{pane_id}')
tmux send-keys -t "$CODEX_PANE" \
  'codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox --search -m gpt-5.5 -c model_reasoning_effort=high -C /abs/path/to/repo "Read /tmp/brief.md and begin."' Enter
```

| Flag | Why |
|---|---|
| *(no `exec`)* | Bare `codex` is the interactive TUI — the whole point. `codex exec` is headless. |
| `--no-alt-screen` | **Mandatory.** Otherwise the TUI uses the alternate screen, where `capture-pane` sees only the current viewport — no scrollback. Inline mode keeps history readable. |
| `--dangerously-bypass-approvals-and-sandbox` | Peer-engineer model — no per-action approval prompts (the host machine is the sandbox). The user can still interject by typing. |
| `-C /abs/path` | Roots the agent in the target repo. |
| `[PROMPT]` positional | A short single-line kickoff. Long briefs go in a file (below). |

First run shows a **"Do you trust the contents of this directory?"** prompt —
`tmux send-keys -t "$CODEX_PANE" Enter` once to confirm.

### Brief via a file, drive via send-keys

Long multi-line briefs sent through `send-keys` into a TUI are fragile —
embedded newlines submit the message early. Write the brief to a file (Write
tool) and `send-keys` a one-liner pointing at it:

```bash
tmux send-keys -t "$CODEX_PANE" 'Read /tmp/codex-<topic>.md in full and implement it. Commit when done.' Enter
```

**Submit quirk:** `send-keys … Enter` sometimes leaves the text sitting in the
`›` input box unsent. Capture the pane; if the message is still in the input,
send a second bare `Enter`. Follow-up tasks: `send-keys` the next instruction
into the **same pane** — context persists. Brief at intent level (see the
`consulting-other-agents` skill) — the peer is a peer, not a typist.

### Blocking on the peer — poll for IDLE

An interactive REPL process **never exits**, so `tail --pid` and
`poll_pane_done.sh` (which wait for a shell prompt) do **not** work here. Block
by polling the pane for the peer's idle state.

Codex's TUI shows `• Working (Xs • esc to interrupt)` while processing a turn,
and `• Waiting for background terminal` while a sub-command runs. **Idle =
neither marker present.**

Run this with the Bash tool's `run_in_background: true` — it exits when the peer
goes idle, giving you exactly one completion notification:

```bash
for i in $(seq 1 240); do
  cap=$(tmux capture-pane -p -t "$CODEX_PANE" 2>/dev/null) || { echo PANE_GONE; break; }
  grep -qE 'Working \(|Waiting for' <<<"$cap" || { echo "CODEX_IDLE after ~$((i*10))s"; break; }
  sleep 10
done
echo '=== codex pane ==='
tmux capture-pane -p -S -120 -t "$CODEX_PANE" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -45
```

Then read the peer's final report from the pane scrollback, or the committed
result directly (`git log`). **While blocked, do real parallel work** — the
non-peer side of the task — rather than emitting "still working" status turns;
fall back to a pure blocking wait only when no independent work remains.

### Cleanup

A persistent peer pane is *intentionally* long-lived — **do not kill it between
tasks**; that destroys the context that makes it valuable. Kill it only when the
whole collaboration is over.

---

## Rules & Discipline

- **Always clean up panes.** Kill every pane you spawn. Leaked panes accumulate.
- **Always `tee` to a file.** Never use bare `>` redirect — it hides output from the user. Use `2>&1 | tee /tmp/file.txt` so output streams to both the pane (visible) and the file (readable by you).
- **Don't ask subagents to write to /tmp files for reviews/verdicts.** The `tee` approach pollutes the output file with terminal artifacts (tool output, shell commands, hex dumps). Instead, let the subagent emit its response naturally to the pane, then use `tmux capture-pane -p -S - -t "$PANE"` and `grep -A` on a known marker (e.g. "## Review", "Verdict", "Findings") to extract the content from scrollback. This is more reliable than fighting file corruption. Reserve `/tmp` write targets for structured data the subagent generates programmatically, not prose.
- **Don't poll tightly.** Use `sleep 2` between capture-pane checks. CPU waste and noise if you spin hot.
- **One task per pane.** Don't reuse a pane for multiple sequential tasks. Spawn fresh, kill when done. *(Exception: a persistent peer-agent pane — Pattern 6 — is deliberately reused across many tasks and kept alive for the whole collaboration.)*
- **Keep prompts self-contained.** A subagent in a pane has no shared context with your session. Pass everything it needs in the prompt string.
- **Timeout everything.** `poll_pane_done.sh` accepts a `--timeout` arg. Always set one. Hung agents must not block forever.
- **Prefer `tee` over `spawn_agent.sh` when the user is watching.** `spawn_agent.sh` redirects stdout to a file, making the pane appear blank. Only use it for fire-and-forget background work where the user doesn't need to see progress.
- **Always resume existing sessions for follow-up work.** If you previously spawned a subagent (e.g. Codex for code review) and now need to send it related follow-up work (e.g. "review the fixes for the issues you flagged"), ALWAYS resume the existing session instead of spawning a fresh one. The subagent already has the full conversation context — a cold start loses that and forces re-reading everything. Capture the session ID when you first spawn it, and use `codex exec resume '<id>'` / `gemini --resume <id>` for follow-ups. This is not optional — if there's a natural prior session to continue, continue it.
