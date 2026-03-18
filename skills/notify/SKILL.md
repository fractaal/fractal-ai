---
name: notify
description: >-
  Pop up a macOS dialog box and/or play a sound to grab the user's attention.
  Use when the user says "ping me", "notify me", "alert me", "let me know",
  "get my attention", or any variation of wanting to be notified. Also use
  proactively when a long-running task completes and the user might have
  context-switched away.
---

# Notify

Grab the user's attention with a macOS dialog box and sound.

## How to use

Run the script at `~/.fractal-ai/skills/notify/scripts/notify.sh`.

### Quick usage

```bash
# Simple — blocking dialog + Glass sound
~/.fractal-ai/skills/notify/scripts/notify.sh "Your task is done!"

# Custom title and sound
~/.fractal-ai/skills/notify/scripts/notify.sh -m "Build passed" -t "CI" -s Hero

# Non-blocking notification center banner
~/.fractal-ai/skills/notify/scripts/notify.sh -m "FYI: deploy complete" --style notification

# Urgent — repeat the sound 3 times
~/.fractal-ai/skills/notify/scripts/notify.sh -m "NEED YOUR EYES" -s Basso --repeat 3

# DEFCON 1 — sound blares on infinite loop until user clicks OK
~/.fractal-ai/skills/notify/scripts/notify.sh -m "PROD IS DOWN" -s Sosumi --loop
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `-m`, `--message` | *(required)* | The message to display |
| `-t`, `--title` | `Agent Ping` | Dialog/notification title |
| `-s`, `--sound` | `Glass` | macOS sound: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink |
| `--style` | `dialog` | `dialog` (blocking modal) or `notification` (banner, non-blocking) |
| `--repeat` | `1` | How many times to play the sound |
| `--loop` | off | Sound loops infinitely until the dialog is dismissed. Use for P0/critical alerts |

## When to use this

- The user explicitly asks to be pinged/notified/alerted.
- A long-running background task finishes (builds, deploys, test suites).
- You need user input and they may have walked away.

## Guidelines

- Default to `dialog` style — it's modal and impossible to miss.
- For informational/non-urgent pings, use `--style notification`.
- For urgent things, use `--repeat 3` and a strong sound like `Basso` or `Sosumi`.
- For critical/P0 situations, use `--loop -s Sosumi` — the sound will blare nonstop until the user clicks OK. This is the nuclear option. Use it when something is genuinely on fire.
- **Sound choice for `--loop`:** Use `Sosumi` or `Ping` — they loop cleanly. Avoid `Basso` for looping (it sounds awful on repeat).
- Keep messages short and actionable.

### Message content — IMPORTANT

The user runs many agents in parallel and may not remember which one is pinging them. Your message **must** include enough context for the user to immediately orient themselves. Include:

1. **Who you are** — the project/repo you're working in, or the task you were given.
2. **What happened** — the event that triggered the notification (task done, build failed, need input, etc.).
3. **What you need** — what action, if any, the user should take.

**Good examples:**
- `"[myapp backend] Build passed. All 42 tests green. Ready for your review."`
- `"[infra/terraform] Need input: can't resolve which AWS region to target. Waiting on you."`
- `"[P0 api-gateway] 502s spiking in prod. Get back here NOW."`

**Bad examples:**
- `"Done!"` — done with what?
- `"Need your help"` — which agent? what help?
- `"Task complete"` — what task? where?
