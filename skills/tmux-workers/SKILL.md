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

## Prerequisites

- You must be inside a tmux session (`$TMUX` is set). Verify: `echo $TMUX_PANE`.
- `tmux` is on `$PATH`.
- For subagent workers: `claude` CLI is on `$PATH`.

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

## Pattern 2 — Claude Subagent Worker

Spawn a `claude` CLI process in a pane, give it a task via stdin/heredoc, and read the result.

```bash
# 1. Spawn (narrow vertical split so it doesn't crowd main pane)
PANE=$(tmux split-window -v -d -l 20 -P -F "#{pane_id}")

# 2. Run claude with a prompt, write result to file
PROMPT="Your task here. Write your final answer to /tmp/agent-result.txt and nothing else after that."
tmux send-keys -t "$PANE" "claude -p '$PROMPT' > /tmp/agent-result.txt 2>&1" Enter

# 3. Poll until done
scripts/poll_pane_done.sh "$PANE"

# 4. Read result
cat /tmp/agent-result.txt

# 5. Cleanup
tmux kill-pane -t "$PANE"
```

**Important:** Tell the agent in the prompt to write its final answer to a known file. Don't rely solely on `capture-pane` for long outputs — the buffer truncates.

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
- `scripts/spawn_agent.sh` — full spawn-send-poll-read-cleanup cycle for a single Claude subagent.
- `scripts/fanout.sh` — parallel fan-out over N tasks, one pane each.

---

## Rules & Discipline

- **Always clean up panes.** Kill every pane you spawn. Leaked panes accumulate.
- **Always tee to a file.** Never rely on `capture-pane` alone for output you care about.
- **Give subagents a write target.** Prompt them explicitly to write their final answer to `/tmp/<name>.txt`. Parse that file, not the pane buffer.
- **Don't poll tightly.** Use `sleep 2` between capture-pane checks. CPU waste and noise if you spin hot.
- **One task per pane.** Don't reuse a pane for multiple sequential tasks. Spawn fresh, kill when done.
- **Keep prompts self-contained.** A subagent in a pane has no shared context with your session. Pass everything it needs in the prompt string.
- **Timeout everything.** `poll_pane_done.sh` accepts a `--timeout` arg. Always set one. Hung agents must not block forever.
