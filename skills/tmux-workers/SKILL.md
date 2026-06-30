---
name: tmux-workers
description: >-
  Drive a cross-harness agent CLI (Pi, Codex) — or any executor you want on a
  SHARED pane the human can also open and type into — inside a live tmux window:
  launch, brief, steer with send-keys, block until it goes idle, all
  interactively. Use it for sustained workers (implementer, reviewer,
  investigator) whose harness is NOT a native subagent, or when the shared
  inspectable surface is the point. For a peer Claude under a Claude
  orchestrator, drive it with native Agent/SendMessage subagent tooling instead
  — reach here only for non-native harnesses (Pi, Codex) or the shared-pane
  case. Ships helper scripts: launch-agent.sh, send-keys-then-enter.sh,
  wait-for-text.sh, wait-for.sh. Non-interactive shell/headless workers are the
  appendix here, not the headline.
  Keyword triggers: "run Pi in a pane", "run Codex in a pane", "tmux pane",
  "shared pane", "drive an agent", "wait for the agent", "block on the agent",
  "interactive agent worker", "agent in a window", "steer the agent".
---

# tmux Workers

## What this is for

You run a **cross-harness** agent CLI — Pi or Codex — as a **sustained worker**
inside a tmux window. You launch it, brief it, watch it, steer it mid-task,
read its output, and hand it the next job — across a whole collaboration. (A
peer **Claude** under a Claude orchestrator is driven with native
`Agent`/`SendMessage` subagent tooling instead — reach for tmux when the worker
is not a native subagent, or when the human wants to open the same window and
type into it.)

The agent runs **interactively**, not headless, and that is the entire point:

- The window is **inspectable** — you (and the human) watch the agent work live.
- The window is a **shared surface** — the human can switch to that window and
  type into the *same pane*, as a third hand, to correct or steer the agent
  mid-task. A headless `codex exec` is a sealed box; nobody can see in or reach
  in. An interactive pane is a room everyone can walk into.
- The REPL **keeps full context** across every follow-up. You send the next
  brief into the same window — no session-ID juggling, no cold restarts.

This skill is the interactive pattern, scripted. Non-interactive workers
(headless one-shots, background shell jobs) still exist — they are the
**Appendix** at the bottom, not the body.

## Prerequisites

- You are inside a tmux session. Verify: `echo $TMUX` is non-empty.
- `tmux` is on `$PATH`.
- The agent CLI you want is on `$PATH` (`pi`, `codex`, `claude`, …).
- The helper scripts in `scripts/` are executable (they ship `+x`).

---

## The interactive agent lifecycle

Six steps. Steps 3→5 loop for as long as the collaboration runs.

```
 1. LAUNCH    open a window, start the agent CLI         launch-agent.sh
 2. BRIEF     write the brief to a file, send a one-liner send-keys-then-enter.sh
 3. BLOCK     wait until the agent goes idle             wait-for.sh
 4. READ      capture the pane scrollback                tmux capture-pane -S
 5. FOLLOW UP send the next brief into the SAME window   send-keys-then-enter.sh
 6. CLEANUP   kill the window when the WHOLE job is over tmux kill-window
```

The agent process is a REPL — it **never exits** between turns. So you do not
wait for a shell prompt to return (that is the non-interactive model). You wait
for the agent's **busy marker to disappear**. That is what step 3 does.

---

## The helper scripts

All four live in `scripts/`. They are pure bash + tmux — portable across every
agent that ships this skill. Run any with no args for usage.

### `launch-agent.sh` — open an agent in its own window

```bash
PANE=$(scripts/launch-agent.sh --cmd pi \
  --dir ~/Symph/symph-aria/.worktrees/feature-x \
  --name pi-feature-x)
```

`tmux new-window` rooted in `--dir`, named `--name` (pick something findable —
the human navigates by it), launches `--cmd`, waits `--boot-wait` seconds (or
polls `--ready <regex>`), then prints **only the pane id** to stdout. `--here`
splits the current window instead, for side-by-side.

### `send-keys-then-enter.sh` — type a prompt and submit it

```bash
scripts/send-keys-then-enter.sh "$PANE" \
  'Read /tmp/brief.md in full and implement it. Commit when done.'
```

Sends the text literally (`send-keys -l`, so no word is mistaken for a key
name), then a separate `Enter`, then **verifies it submitted** — see "The
submit quirk" below. `--no-verify` skips the check; `--settle S` tunes the
gap before Enter.

### `wait-for-text.sh` — block until a string appears or vanishes

```bash
scripts/wait-for-text.sh "$PANE" 'BUILD PASSED'              # wait to appear
scripts/wait-for-text.sh "$PANE" 'Working\.\.\.' --gone      # wait to vanish
```

Polls the pane. `--gone` inverts (wait for absence — this is the "wait for the
busy marker to disappear" move). `--stable N` requires the condition to hold N
consecutive polls, so a redraw blip cannot end the wait early. `--timeout`,
`--interval`, `--quiet`. Exit 0 met · 1 timeout · 2 pane gone.

### `wait-for.sh` — block until an agent finishes its turn

```bash
scripts/wait-for.sh pi "$PANE" --timeout 3600        # reads as "wait-for pi"
```

The one you reach for most. First arg is the **agent preset** — `pi`, `codex`,
`claude`, or `any` (the union, safe when you are not sure which CLI is in the
pane). It looks up that CLI's busy marker (see the table below) and waits for
it to vanish — a thin wrapper over `wait-for-text.sh --gone`. `--timeout` /
`--stable` / `--interval` / `--quiet` pass through.

---

## Worked example — driving Pi (from the real run)

This is the actual shape that drove an overnight implementation. Lightly
trimmed; the briefs were longer.

```bash
# 1. LAUNCH — Pi, its own named window, rooted in the worktree
PANE=$(scripts/launch-agent.sh --cmd pi \
  --dir ~/Symph/symph-aria/.worktrees/comment-to-transcript \
  --name pi-comment)

# 2. BRIEF — the long brief goes in a FILE (Write tool); the pane gets a
#    one-liner pointing at it. Brief at intent, not diff (see below).
scripts/send-keys-then-enter.sh "$PANE" \
  'Read /tmp/pi-comment-brief.md in full and implement it. You are in the git worktree on branch feat/comment-to-transcript. Investigate the current handling before writing code. Commit when done. Do NOT push or deploy.'

# 3. BLOCK until Pi goes idle.
#    On Claude Code: run THIS LINE as the Monitor tool's command, so the
#    blocking wait does not sit in your context window.
scripts/wait-for.sh pi "$PANE" --timeout 3600

# 4. READ BACK — scrollback (-S), blank lines stripped
tmux capture-pane -p -S -200 -t "$PANE" | grep -v '^[[:space:]]*$' | tail -90

# 5. FOLLOW UP — next brief into the SAME window; Pi keeps full context
scripts/send-keys-then-enter.sh "$PANE" \
  'Codex reviewed it — verdict SHIP WITH FIXES. Read /tmp/pi-fixes.md and implement the fix round. Commit when done.'
scripts/wait-for.sh pi "$PANE" --timeout 1800

# ... loop 3→5 for every round ...

# 6. CLEANUP — only when the whole collaboration is done
tmux kill-window -t "$PANE"
```

To **steer mid-task**, you do not wait for idle — you send into the pane while
the agent is still working, exactly as the human would by typing into the
window: `scripts/send-keys-then-enter.sh "$PANE" 'Stop — the schema changed, revert that last edit.'`

---

## Blocking properly

### Busy markers — how "idle" is detected

An interactive agent shows a **busy marker** in its status line while it
processes a turn. Idle = that marker is absent. `wait-for.sh` knows these:

| Agent CLI | Busy marker (regex) | Verified |
|---|---|---|
| Pi | `Working\.\.\.` | yes — real sessions |
| Codex | `esc to interrupt` (turn) · `Waiting for background terminal` (sub-command) | yes |
| Claude | `…\s*\([^)]*[0-9]+s` — gerund-ellipsis + live timer | yes — probed |
| *(any)* | `Working\.\.\.|esc to interrupt|Waiting for background terminal|Auto-compacting|…\s*\([^)]*[0-9]+s` | default |
| Gemini | **not verified** | capture-pane it once mid-turn, read the marker, pass it to `wait-for-text.sh --gone` explicitly |

Markers are **distinctive** where the CLI allows — bare `Working` is avoided
(it would false-match the agent's own prose, "Working on the fix…", and the
pane would never read as idle). Pi and Codex have stable keywords; Codex shows
its marker inside `Working (1s • esc to interrupt)`.

**Claude Code has no stable keyword.** Its working line is an animated glyph +
a *random* gerund + a live timer — `✻ Schlepping… (13s · ↑ 374 tokens)`,
`· Meandering… (0s)` — with no fixed word and no "esc to interrupt". It is
matched heuristically: a gerund-ellipsis `…` followed by a parenthesised
elapsed time. Its idle line, `✻ Cogitated for Xs`, has no `… (`, so busy and
idle separate cleanly. This is the one marker that is a heuristic, not a
keyword — if it ever misbehaves, capture the pane and look.

If a CLI changes its status text in an update, these regexes are the one thing
to re-check — they live in `wait-for.sh` and `send-keys-then-enter.sh`.

### Debounce — why `--stable`

A single capture can catch the pane mid-redraw and momentarily miss a marker
that is really still there. `--stable N` (default 2) requires the idle
condition to hold for N consecutive polls before the wait returns, so one bad
frame cannot declare the agent done early.

### Run the wait asynchronously, not inline

`wait-for.sh` is a blocking loop — never run it inline, it burns context for
nothing. Run it **asynchronously** so it waits outside your context and
notifies you when the agent goes idle: on **Claude Code**, hand the
`wait-for.sh …` invocation to the **Monitor tool**; on **Pi**, to its async
monitor tooling (a Pi extension modelled on Claude's Monitor). On an agent with
neither (Codex, Gemini), run it as a blocking background job and check its exit
code.

**While blocked, do real parallel work** — the other side of the task — instead
of emitting "still waiting" turns. Fall back to a pure wait only when there is
genuinely no independent work left.

### Continuous watch (long-lived agent)

`wait-for.sh` is a *one-shot* block — it returns the first time the agent
goes idle. To watch an agent across a long session and get notified on every
state change, use an **edge-triggered** loop (run it under the Monitor tool):

```bash
prev=unknown; cand=unknown; hold=0
while true; do
  cap=$(tmux capture-pane -p -t "$PANE" 2>/dev/null) || { echo "$PANE -> PANE GONE $(date +%H:%M:%S)"; exit 1; }
  if grep -qE 'Working\.\.\.|esc to interrupt|Waiting for background terminal|Auto-compacting|…\s*\([^)]*[0-9]+s' <<<"$cap"; then
    now=working; else now=idle; fi
  if [ "$now" = "$cand" ]; then hold=$((hold+1)); else cand=$now; hold=1; fi
  # debounce: a new state must hold 2 consecutive polls before it counts
  if [ "$hold" -ge 2 ] && [ "$cand" != "$prev" ]; then
    echo "$PANE -> $cand  $(date +%H:%M:%S)"; prev=$cand
  fi
  sleep 10
done
```

**The `hold >= 2` debounce is not optional** — it is the same discipline as
`wait-for.sh --stable`. An agent dips out of `Working...` for a single poll all
the time — between a shell sub-command finishing and its next step starting.
That is a FALSE idle. Un-debounced, this loop wakes you on every blip and you
burn a turn capturing a pane that is still working. Debounced, a state must
survive two polls (~20s) to fire.

For the Execution agent you supervise across a whole change, this continuous
watch — not the one-shot `wait-for.sh` — is your default: one standing Monitor
for the life of the collaboration. One gotcha: if Execution runs its own
monitor on *your* pane, `capture-pane` of *its* pane can show your content
reflected back — two agents watching each other is fine, just don't misread
the mirror.

---

## The submit quirk

Sending a prompt into a TUI input box and pressing Enter does not always
submit it — the text can sit unsent in the `›` box. `send-keys-then-enter.sh`
handles this for you: after sending, it captures the pane, and if the agent did
**not** start working, it sends a second bare `Enter` to push the message
through. If you ever drive a pane by hand with raw `tmux send-keys`, remember
this — capture the pane and send a bare `Enter` if the message is still parked.

If the pane shows an **error** instead of a parked message — e.g. a Codex/Pi
`previous_response_not_found` session error — the message did not land because
the agent's turn failed, not because Enter was missed. Recovery: `tmux
send-keys -t "$PANE" Up` recalls your last input into the box, then a separate
`Enter` resubmits it. That clears most transient agent-session errors without
retyping the brief.

---

## Briefing discipline

- **Long briefs go in a file.** Multi-line text sent through `send-keys`
  submits early on the first embedded newline. Write the brief with the Write
  tool to `/tmp/<topic>.md`, then `send-keys-then-enter.sh` a one-liner:
  `'Read /tmp/<topic>.md in full and …'`.
- **Brief at intent, not diff.** The agent in the pane is a peer engineer, not
  a typist. State what to achieve and why; let it decide how. Load the
  `consulting-other-agents` skill before you write the brief — it details the
  failure modes (leading the witness, muzzling the peer, smuggling unverified
  claims) that waste the collaboration.
- **The pane has no shared context with you.** Everything the agent needs goes
  in the brief or the brief file.

### Launching specific agent CLIs

What to pass as `launch-agent.sh --cmd`:

| Agent | `--cmd` value |
|---|---|
| Pi | `pi` |
| Codex | `codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox --search -m gpt-5.5 -c model_reasoning_effort=high` |
| Claude | `claude` |

`--no-alt-screen` for Codex is **important**: without it the TUI uses the
alternate screen and `capture-pane` sees only the current viewport — no
scrollback to read back. Some agents show a first-run "trust this directory?"
prompt; clear it with one `tmux send-keys -t "$PANE" Enter`.

---

## Rules & discipline

- **The window is shared — name it well.** `--name pi-gw-impl`, not `agent`.
  The human finds and joins the agent by window name.
- **One agent per window, reused across that agent's tasks.** An interactive
  REPL keeps context — that is its value. Send follow-ups into the same window;
  do not spawn a fresh one per task.
- **Do not kill the window between tasks.** A persistent peer window is
  *intentionally* long-lived. Killing it destroys the context that makes it
  worth running interactively. Kill it only when the whole collaboration ends.
- **Read back from scrollback, not just the viewport.** `tmux capture-pane -p
  -S -200 -t "$PANE"` — the agent's output scrolls past the visible area.
- **Timeout every wait.** `wait-for.sh <agent> <pane> --timeout N`. A hung
  agent must not block forever.
- **Clean up panes you spawned for throwaway work.** Persistent agent windows
  are the exception; everything else gets killed when done.

---

## Appendix — non-interactive workers

The interactive pattern above is the default. These non-interactive shapes
still have narrow uses.

### Shell worker — a long command in a background pane

Run a long build/test in a pane, poll until the **shell prompt returns**
(process exited), read the output:

```bash
PANE=$(tmux split-window -h -d -P -F '#{pane_id}')
tmux send-keys -t "$PANE" 'long-build 2>&1 | tee /tmp/build.txt' Enter
scripts/poll_pane_done.sh "$PANE" --timeout 600   # waits for the shell prompt
cat /tmp/build.txt
tmux kill-pane -t "$PANE"
```

`poll_pane_done.sh` watches for the prompt to reappear — correct for a shell
command, **wrong for an interactive agent** (whose REPL never returns a
prompt). For agents, use `wait-for.sh`.

### Headless one-shot agent

A single fire-and-forget agent call — one review, one question, no follow-ups
— does not need a pane at all. That is `codex exec` / `claude -p`, and the
canonical invocations live in the **`consulting-other-agents`** skill. Use that,
not a pane, for one-shots.
