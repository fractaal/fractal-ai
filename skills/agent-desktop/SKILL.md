---
name: agent-desktop
description: >-
  Run GUI work in a nested Hyprland "agent desktop" so the agent can open
  windows, click, type, and screenshot without stealing focus from Ben's live
  session or surprising him with windows. Use when a task needs a real GUI app
  driven by the agent (browser, editor, installer, native app) while Ben keeps
  using his machine, or when Ben says an agent "stole my focus", "popped up a
  window", "took over my screen", or asks for a sandbox/scratch desktop for GUI
  automation. Ships scripts/agentdesk (start, run, shot, stop, status, env).
  NOT a security boundary — same uid, same $HOME. Do NOT use for headless CLI
  work, which needs no desktop at all.
---

# Agent desktop

A second Hyprland, nested inside Ben's session, that the agent drives. Its
windows and focus are its own. Ben can look at it whenever he wants; nothing in
it lands on his screen unless he opens that window.

## Use it when

- A task needs a real GUI app driven by the agent, and Ben is still using the machine.
- You are about to launch a browser/editor/GUI installer and would otherwise
  pop a window into his face.

**Do not** use it for headless CLI work. Most tasks need no desktop at all;
starting one is pure waste.

## Commands

```bash
S=~/.claude/skills/agent-desktop/scripts/agentdesk

"$S" start                      # launch it, prints the env it pinned
"$S" run kitty                  # run ANY command inside it
"$S" run brave --user-data-dir=/tmp/agent-brave
"$S" shot /tmp/desk.png         # screenshot just this desktop
"$S" status                     # instance, socket, pid, window list
"$S" stop
```

**Always launch GUI work through `agentdesk run`.** That is the whole point:
it makes the correct environment ambient, so you cannot forget it. Do not
hand-set `WAYLAND_DISPLAY` and hope.

## Driving it

Inside `agentdesk run`, these are already scoped to the agent desktop:

| Want | Use |
|---|---|
| type text | `wtype 'hello'` / `wtype -k Return` |
| move cursor | `hyprctl dispatch movecursor X Y` |
| click | `hyprctl dispatch sendshortcut ',mouse:272,activewindow'` |
| windows | `hyprctl clients -j`, `hyprctl dispatch focuswindow …` |
| screenshot | `grim out.png` (or `agentdesk shot`) |
| a browser | prefer CDP via the `brave-profile-cdp` skill over synthetic clicks |

## The two ways input escapes into Ben's session

Both are silent, and both are closed by `agentdesk run`. Know them anyway,
because they explain why this design is shaped the way it is.

1. **`ydotool` / anything on `/dev/uinput`.** It creates a *kernel* input
   device; libinput hands it to seat0, which is Ben. The nested compositor has
   no libinput backend at all — its device list is only `wl_pointer` /
   `wl_keyboard` proxied from the parent — so uinput input can never arrive
   here. `agentdesk run` puts a shim on `PATH` that refuses ydotool loudly.
   This also rules out any uinput-based computer-use stack (e.g.
   `agent-sh/computer-use-linux`, whose pointer backend is uinput and whose
   screenshot backend is the portal). Those drive the *real* session by design.

2. **Inherited `DISPLAY`.** An X11-capable app inheriting `DISPLAY=:0` renders
   into the *parent's* Xwayland — Ben's screen. `agentdesk run` unsets it and
   forces Wayland backends, so such an app fails loudly instead of appearing on
   his monitor.

Everything else is socket-scoped and structurally safe: `wtype`, `grim`, and
every Wayland client connect to a named socket, and `hyprctl` keys off the
instance signature. There is no code path from a `wayland-2` client to the
`wayland-1` compositor.

## Known limits

- **Not a security boundary.** Same uid, same `$HOME`. It contains focus and
  windows, nothing more. Do not describe it to Ben as a sandbox.
- **Dies with Ben's session.** It is nested, so it needs a parent compositor.
  Hyprland cannot run standalone-headless: aquamarine ships a headless backend
  but Hyprland exposes no way to select it, and starting with no DRM and no
  parent dies in `CBackend::create()`. If it must outlive his session, that is
  a different tool (headless `labwc`/`cage` + `wayvnc`, or Xvfb).
- **Portals are shared.** `xdg-desktop-portal-hyprland` is one user service
  bound to Ben's instance, so a portal-mediated file picker or screenshare
  prompt from an agent app can still surface on *his* screen. Prefer apps and
  flags that avoid portals.
- **Don't start the rice in it.** quickshell binds
  `/run/user/1000/quickshell` and would collide with the real session. The
  shipped config deliberately does not source `~/.config/hypr/*`.

## Brave: the compositor isolation does NOT save you here

Running `agentdesk run brave` against Ben's normal profile does the **opposite**
of what you want. Chromium enforces one instance per `--user-data-dir` via
`SingletonLock` / `SingletonSocket` in the profile dir. A second launch does not
start a browser — it hands its command line to the **already-running** Brave
over a socket in `/tmp` and exits. That running Brave is on Ben's screen, so the
tab opens *there*.

The compositor isolation is airtight; Brave routes around it one layer up,
because the handoff is a filesystem socket both sessions can reach. This is the
same root cause as the Discord Canary session-loss (two Electron instances, one
profile dir).

So a separate `--user-data-dir` is **mandatory**, not advisory:

```bash
agentdesk run brave --user-data-dir=$HOME/.local/share/agentdesk-brave
```

That profile starts logged out. To seed it with Ben's logins, copy the profile —
and note this works on his box specifically because `~/.config/brave-flags.conf`
sets `--password-store=basic`, so cookies are encrypted with a fixed key rather
than a keyring entry, and a copy decrypts fine under the same uid.

Practical notes when seeding:
- The full profile is ~2.2 GB (`Default` alone ~1.1 GB). Copy to disk, **not**
  `/tmp` — that's tmpfs, i.e. RAM, on a handheld.
- Most of that bulk is cache. `Local State` plus `Default/{Cookies,Preferences,
  Login Data,Web Data}` is enough to be logged in.
- `Cookies` is live SQLite. Copy with Brave closed, or accept a possible torn
  read and re-seed if sessions look wrong.
- The clone is a point-in-time snapshot: logins made later in one do not appear
  in the other, and some services will invalidate one of two concurrent sessions.

If the task is really "drive a page in the browser I'm already logged into",
prefer CDP against his live Brave (`brave-profile-cdp` skill) and accept that
the window is on his screen — that avoids the whole cloning problem.

## Letting Ben watch

The agent desktop is just a window in his session. He can focus it like any
other window, and input reaches it *only* while it is focused — so watching it
is safe, and looking away costs nothing.
