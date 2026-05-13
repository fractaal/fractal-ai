---
name: recover-wedged-hyprland
description: >-
  INVOKE/LOAD WHEN: Ben says his Hyprland session is frozen, the display is
  black or stuck, he can't switch TTYs, the mouse/keyboard is captured,
  Sunshine/Moonlight streaming wedged the desktop, his bar/dock/overview is
  gone after a Sunshine session, quickshell crashed, or any variation of
  "my desktop locked up", "screen frozen", "display died", "compositor hung",
  "shell crashed", "qs died", "bar gone", "kick me back to login",
  "can you log me out". Also use when Ben SSHes in and asks for help
  recovering a stuck or partially-broken GUI session on his CachyOS box (the
  GPD Win Max 2). KEYWORDS: "frozen", "wedged", "hung", "stuck display",
  "black screen", "can't switch TTY", "compositor", "Hyprland", "quickshell",
  "qs", "bar disappeared", "plasmalogin", "kick me to greeter",
  "restart session", "Sunshine froze", "Sunshine disconnect", "aquamarine",
  "PwDefaultTracker", "PipeWire".
---

# Recover wedged Hyprland session (Ben's CachyOS box)

This is a personal sysadmin recipe for Ben's specific setup — GPD Win Max 2 running CachyOS with Hyprland under plasmalogin (KDE's display manager). It is *not* a generic guide; the procedures and known-bug references below are tuned to this exact environment.

Read this skill end-to-end before acting. Some of the gotchas (especially the plasmalogin greeter-respawn bug and the SSH-session safety rule) bit us in real downtime, and the recipe encodes those hard-won lessons.

## What "wedged" means here

Ben uses Hyprland on tty2 or tty3 with `plasmalogin` as the DM. The known failure modes are:

- **Hard wedge (Hyprland)** — Hyprland process alive, IPC dead, log frozen mid-line, single thread spinning at ~77% CPU. `hyprctl monitors` times out with "IPC didn't respond in time". Display is black or frozen on its last frame, keyboard is captured (Ctrl+Alt+F-keys to switch TTY does nothing).
- **Soft wedge (Hyprland)** — Hyprland IPC still responds but rendering has stopped, frames aren't being delivered to outputs (or to Sunshine streams). CPU usage on Hyprland is elevated but not pegged.
- **Quickshell-only crash (Hyprland survives)** — Hyprland is healthy and IPC responds, but the `qs -c ii` desktop shell has segfaulted, taking the bar/dock/overview/notifications/cliphist UI with it. App windows still tile, keyboard still works, workspace switching still works. Ben will perceive this as "my UI is broken" or "the shell crashed", not "wedged". **Recovery is one line — do NOT terminate the session.** See the dedicated section below.

Both wedge modes have been traced to the **same aquamarine event-loop bug** (smoking-gun log signature below). The quickshell-only crash is a separate `PwDefaultTracker` null-deref, also Sunshine-related — see its own section.

**⚠️ First, fork on which mode this is.** Before doing anything else, run:

```bash
pgrep -af Hyprland                                                    # is the compositor alive?
pgrep -af 'qs -c'                                                     # is the shell alive?
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ | head -1)
timeout 3 hyprctl version >/dev/null && echo "IPC alive" || echo "IPC dead"
```

- IPC alive + `qs -c` missing → **Quickshell-only crash.** Jump to the quickshell section. Do not terminate the GUI session.
- IPC dead OR Hyprland missing → **Hyprland wedge.** Continue with the wedge-recovery procedure below.
- Both alive → user is reporting something else; ask before acting.

## Quickshell-only crash: recovery

If the triage fork pointed you here — Hyprland IPC alive, `pgrep -af 'qs -c'` empty — recovery is one line. **Don't touch the session.**

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ | head -1)
hyprctl dispatch exec 'qs -c ii'           # inherits Hyprland session env
sleep 2
pgrep -af 'qs -c'                          # expect a new PID
timeout 3 qs -c ii ipc show >/dev/null && echo "IPC up" || echo "still down"
```

Using `hyprctl dispatch exec` (not just `qs -c ii &` from your SSH shell) matters: it makes Hyprland the parent, so the new qs inherits `WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`, `ILLOGICAL_IMPULSE_VIRTUAL_ENV`, and the eGPU `GBM_BACKEND`/`AQ_DRM_DEVICES` env that `hypr-launch` set at session start. The cliphist `wl-paste --watch` watchers keep running across a quickshell crash and reattach to the new instance on the next copy — don't restart them.

### Smoking gun: PipeWire default-sink null-deref

`coredumpctl info <pid>` on the crashed `quickshell` core shows this signature:

```
#5  qs::service::pipewire::PwDefaultTracker::setDefaultSink(qs::service::pipewire::PwNode*)
#4  QObject::disconnect(...)
#6  qs::service::pipewire::PwDefaultTracker::onMetadataProperty(...)
```

And the journal correlates with Sunshine disconnecting:

```
sunshine[...]: Info: CLIENT DISCONNECTED
sunshine[...]: Info: Setting default sink to: [alsa_output.pci-0000_c5_00.6.analog-stereo]
... (within ~3s) ...
systemd-coredump[...]: Process <pid> (quickshell) of user 1000 dumped core.
```

Cause: `PwDefaultTracker::setDefaultSink` calls `QObject::disconnect` on a `PwNode*` that's being torn down as the default sink swaps. Hits a null/dangling deref. The exposure is the Sunshine disconnect because Sunshine restores the system's previous default sink on its way out — any other sudden default-sink change would likely fire it too (e.g. yanking a USB headset).

Quickshell tries to auto-relaunch itself after a crash (frame `qsCheckCrash` in the backtrace), but the auto-relaunch can *also* die immediately inside libwayland message dispatch — you may see two coredumps within a second of each other. Either way the recovery is the same: dispatch a fresh `qs -c ii` from Hyprland.

### When the backtrace doesn't match

If `qs -c` is gone but the coredump backtrace does **not** mention `PwDefaultTracker`, save the backtrace and the user's last action before relaunching — the recovery one-liner still works, but the underlying bug is a different one and worth noting separately.

## The smoking gun (recognize this signature)

(Hyprland-wedge path from here on.)

In `/run/user/1000/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log`, look at the tail:

```
ERR from aquamarine ]: dispatchIdle: dispatched an non readable idle event on fd : <N>
ERR from aquamarine ]: dispatchIdle: dispatched an non readable idle event on fd : <N>
... (repeated a few times)
DEBUG from aquamarine ]: GBM: Allocated a new buffer with size [Vector2D: x: 3024, y: 1964] ...
DEBUG from aquamarine ]: drm: Modesetting DP-8 with 3024x1964@59.98Hz
... (log ends here, often mid-line)
```

The log going silent right after a `Modesetting DP-8` line is the canonical wedge signature. It's typically immediately preceded by Sunshine spawning virtual input devices ("Sunshine X-Box One (virtual) pad", "Sunshine Nintendo (virtual) pad", "Pen passthrough", "Touch passthrough" via libinput). The race appears to be between aquamarine's event loop dispatching idle on an fd that just got closed/reopened by libseat during a hot-plug, while a DRM modeset on the eGPU output (DP-8, the AOC CU34G2XP) is in flight.

When you see this signature, the diagnosis is **not** "memory pressure" or "Minecraft is heavy" — it's the aquamarine bug, and the fix is to nuke the session, not free RAM. Memory thrash is usually a downstream effect (the user can't quit the game because the compositor isn't drawing the in-game menus), not the root cause. Ben has corrected this misdiagnosis explicitly, so trust the log signature over a tempting RAM theory.

## Triage commands

Run these from an SSH session if Ben has one open, or guide him to run them himself if not:

```bash
# Find the GUI session and the SSH session — DO NOT terminate the SSH one
loginctl list-sessions

# Find Hyprland and check whether IPC is responsive
pgrep -af Hyprland
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ | head -1)
timeout 3 hyprctl monitors

# Read the log tail for the aquamarine signature
LOG=/run/user/1000/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log
tail -50 "$LOG"

# Active VT (greeter usually moves to tty1 after a respawn)
cat /sys/class/tty/tty0/active
```

The session list will look something like:

| SESSION | TTY  | CLASS   | What it is                                    |
|---------|------|---------|------------------------------------------------|
| 3       | -    | manager | systemd `user@1000.service` — **DO NOT KILL** |
| 7       | tty3 | user    | The wedged Hyprland GUI session — kill this   |
| 8       | pts/2| user    | SSH session (Claude is here) — **DO NOT KILL**|

The GUI session is the one with `seat0` and a real `tty<N>` — terminate that one specifically by ID. Never `terminate-user 1000` or kill session 3 (the systemd manager); both will take down SSH and any background user services.

## The two-step recovery

This is the procedure. **Both steps are required.** plasmalogin on this box reliably fails to respawn the greeter after its helper exits — it leaves itself idle in `Active: active (running)` with zero greeter children. We've hit this twice in one day. Restarting the service forces a fresh greeter.

```bash
# Step 1 — terminate the GUI session (replace 7 with whatever ID it has)
sudo loginctl terminate-session 7
sleep 5

# Step 2 — restart plasmalogin so the greeter respawns
sudo systemctl restart plasmalogin
sleep 4

# Verify
pgrep -af 'plasmalogin|startplasma-login'   # expect a fresh helper + greeter
cat /sys/class/tty/tty0/active              # expect tty1 (greeter usually lands here)
```

After this, tell Ben which tty the greeter is on — it usually moves to **tty1** after a restart even if the wedged session was on tty2/tty3, so he may need `Ctrl+Alt+F1` if his screen is still showing the old VT's frozen buffer.

## Sudo is required and may not be cached

Ben's box has `!tty_tickets` and a 60-minute sudo timestamp (see `~/CLAUDE.md`). If `sudo -n` fails:

1. Ask Ben to run `! sudo -v` in the Claude prompt (sometimes works, sometimes doesn't depending on tty attachment).
2. If that fails, ask him to open a real terminal (konsole or another SSH window) and run `sudo -v` there. The timestamp is shared globally across all his processes thanks to `!tty_tickets`, so refreshing in any terminal is enough.

## When SSH isn't available — recovery from the physical keyboard

Ben's `kernel.sysrq` is set to `438` (drop-in at `/etc/sysctl.d/99-sysrq.conf`), which enables keyboard control, sync, remount-RO, signal, and reboot. The SysRq key on the GPD is **Fn+P** (PrtSc). The chord is therefore `Alt + Fn + P + <letter>`.

Recovery sequence, easiest to most nuclear:

| Try | Chord                 | What happens                                                  |
|-----|-----------------------|---------------------------------------------------------------|
| 1   | Alt+Fn+P, then **R**  | SysRq "unraw" — releases keyboard from Wayland. After this, `Ctrl+Alt+F3` should switch TTY again. |
| 2   | (after R) `Ctrl+Alt+F3`, log in, then `sudo pkill -9 Hyprland; sudo systemctl restart plasmalogin` | Same recipe as above, but from a TTY shell |
| 3   | Alt+Fn+P then `R E I S U B` one-per-second | REISUB safe reboot — last resort short of holding power |
| 4   | Long-press power button | Hard shutdown. Avoid the suspend-via-power-button path because of Ben's prior s2idle bag-cook history (see `user_hardware.md`) |

## Aftercare — restarting Sunshine

If Ben was streaming and wants Sunshine back up after relogging into Hyprland:

```bash
systemctl --user start sunshine.service
systemctl --user status sunshine.service --no-pager -l | head -20
```

The user unit is `sunshine.service`, web UI at `https://localhost:47990`, NVENC encoders use the eGPU when docked.

**Caveat — Sunshine has TWO independent bug exposures on this box**:

1. **Connect-side (Hyprland wedge)**: re-running Sunshine after a wedge will most likely re-trigger the wedge as soon as a Moonlight client connects, because the aquamarine `dispatchIdle` race is still present. Check `pacman -Q hyprland aquamarine` for pending updates — known upstream issue, may be patched.
2. **Disconnect-side (Quickshell crash)**: every Moonlight client disconnect has a high chance of crashing `quickshell` via the `PwDefaultTracker` null-deref above, because Sunshine restores the default audio sink on its way out. This is independent of the aquamarine bug and lives in the `illogical-impulse-quickshell-git` binary (built locally by end-4's installer, so updating means re-running that installer — not a `pacman -Syu`). Has fired 3× in one day on 2026-05-12.

If Ben streams, expect to relaunch quickshell after every Moonlight session even on a clean run.

## Why not less destructive options?

A few things you'll be tempted to try; here's why they don't work in this exact failure mode:

- **`hyprctl dispatch exit`** — IPC is wedged, command times out.
- **`SUPER+SHIFT+M` / Hyprland keybinds** — same, plus keyboard is captured.
- **`killall -USR1 Hyprland`** — Hyprland has no SIGUSR1 handler that helps here.
- **`SIGTERM Hyprland` only** — works, but plasmalogin won't respawn the greeter on its own. Use the two-step recipe instead.
- **`SIGSTOP` heavy processes (Minecraft etc.)** — does nothing for the aquamarine wedge. Only useful if memory pressure is the actual root cause, which it usually isn't on this box.

## Memory pressure is a separate issue

If Ben's box is *also* thrashing zram (you'll see ~50+ GiB used, load >5, multiple multi-GB JVMs), that's worth flagging — but treat it as a separate problem from the wedge. The session-restart procedure above is correct regardless. Don't conflate the two: Ben has explicitly pushed back on "it's the RAM" theories when the actual cause was the compositor bug.

## Logging this for future you

After a successful recovery, consider whether to:

- Append a one-line incident note to today's engineering log via `write-engineering-logs` (timestamp, wedge signature confirmed, actions taken).
- Update `~/.claude/projects/-home-benjude/memory/` if a *new* failure mode surfaces — the existing aquamarine signature is already well-documented in this skill so doesn't need its own memory file.
