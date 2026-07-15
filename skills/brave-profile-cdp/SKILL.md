---
name: brave-profile-cdp
description: Operate Ben's existing authenticated Brave Work or Personal profile directly through the Chrome DevTools Protocol (CDP). Use when the user asks to control logged-in Brave, inspect a page with existing profile cookies/session state, expose Brave over CDP, switch between Work and Personal profiles, or avoid an isolated Chrome DevTools MCP browser that is not authenticated.
compatibility: Linux, Brave, curl, Python 3, and Node.js 22 or newer.
---

# Brave Profile CDP

Use Brave's real profile session through CDP instead of copying cookies or logging
an isolated automation browser into the user's accounts.

Prefer Chrome DevTools MCP for ordinary browsing. Use this skill when existing
Brave authentication/profile state is the point.

## Security boundaries

CDP grants full control of the selected authenticated browser profile.

- Bind only to `127.0.0.1`. Never use `0.0.0.0`, a public interface, or a tunnel.
- Never print or persist cookies, passwords, authorization headers, localStorage,
  or session tokens. Perform authenticated work inside the page and return only
  the needed result.
- Put private screenshots/downloads in `/tmp`; do not commit or upload them unless
  the user explicitly asks.
- Opening or reading a page is not permission to submit forms, send messages,
  change account state, or perform destructive actions. Apply the normal
  confirmation rules to those actions.
- Do not kill or relaunch an existing Brave session without warning the user;
  doing so closes or interrupts their browser windows.

## 1. Reuse an existing CDP session

Check before relaunching anything:

```bash
curl -fsS http://127.0.0.1:9222/json/version
pgrep -af 'brave.*remote-debugging-port=9222' | head
```

If the endpoint works and the main process uses the requested
`--profile-directory`, reuse it.

Brave is a singleton: launching another command while Brave is already running
usually forwards to the existing process and does **not** retrofit CDP flags or
switch the controlled profile.

## 2. Discover profile directory names

Never infer a directory from the visible profile name. Read Brave's native
profile registry:

```bash
python - <<'PY'
import json
from pathlib import Path

state = Path.home() / '.config/BraveSoftware/Brave-Browser/Local State'
profiles = json.loads(state.read_text()).get('profile', {}).get('info_cache', {})
for directory, info in profiles.items():
    print(f"{directory} => {info.get('name', '<unnamed>')}")
PY
```

On Ben's current machine this has mapped `Default => Personal` and
`Profile 1 => Work`, but always rediscover it because profile directories can
change.

## 3. Relaunch the selected profile with CDP

If Brave is running without CDP or with the wrong profile, ask Ben to close all
Brave windows—or obtain explicit permission to stop the process—before launching:

```bash
brave \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9222 \
  --profile-directory='Profile 1' \
  --restore-last-session
```

Replace `Profile 1` with the directory discovered above. Start this as a
harness-managed background process; do not append `&`, daemonize it, or use
`nohup`.

Verify both the listener and selected profile:

```bash
curl -fsS http://127.0.0.1:9222/json/version
pgrep -af 'brave.*remote-debugging-port=9222' | head
```

Keep any background-task id returned by the harness. Stop that task only when
Ben asks or explicitly approves closing the controlled browser.

To switch between Work and Personal, repeat this controlled close/relaunch flow.
Do not assume cookies from one profile are available in the other.

## 4. List and select page targets

```bash
curl -fsS http://127.0.0.1:9222/json/list |
  python -c 'import json,sys; [(print(x.get("id"), x.get("title"), x.get("url"))) for x in json.load(sys.stdin) if x.get("type") == "page"]'
```

Prefer opening a new target instead of commandeering a tab Ben is using:

```bash
url='https://example.com/'
encoded=$(python -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$url")
curl -fsS -X PUT "http://127.0.0.1:9222/json/new?$encoded" > /tmp/brave-cdp-target.json
python -m json.tool /tmp/brave-cdp-target.json
```

Select targets by exact or well-constrained URL, not by list position:

```bash
ws=$(
  curl -fsS http://127.0.0.1:9222/json/list |
  python -c 'import json,sys; print(next(x["webSocketDebuggerUrl"] for x in json.load(sys.stdin) if x.get("type") == "page" and x.get("url", "").endswith("/AN-7475")))'
)
```

## 5. Call CDP directly

The bundled helper sends one CDP method call over a target WebSocket:

```bash
CALL=~/.fractal-ai/skills/brave-profile-cdp/scripts/cdp-call.mjs
node "$CALL" "$ws" Runtime.evaluate \
  '{"expression":"({title:document.title,url:location.href,text:document.body.innerText})","returnByValue":true}'
```

Await an authenticated in-page request without extracting credentials:

```bash
node "$CALL" "$ws" Runtime.evaluate \
  '{"expression":"(async()=>{const r=await fetch(\"/api/build\",{credentials:\"include\"}); return {status:r.status,text:await r.text()}})()","awaitPromise":true,"returnByValue":true}'
```

Navigate an existing target:

```bash
node "$CALL" "$ws" Page.navigate '{"url":"https://example.com/next"}'
```

Capture a screenshot:

```bash
node "$CALL" "$ws" Page.captureScreenshot \
  '{"format":"png","captureBeyondViewport":true}' |
  python -c 'import base64,json,sys; sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)["data"]))' \
  > /tmp/brave-cdp.png
```

A CDP response proves only that the protocol call completed. After navigation or
UI interaction, inspect the resulting URL/DOM and verify the intended user-visible
outcome.

## Troubleshooting

- **Connection refused:** Brave was not started with the CDP flags, or it exited.
- **Flags appear ignored:** another Brave singleton was already running. Close it
  with the user's knowledge, then relaunch.
- **Wrong account/session:** check the main process's `--profile-directory` and
  rediscover the profile map.
- **`401` despite using Brave:** that profile is not logged into the site; do not
  claim authentication carried over.
- **Target disappeared:** refresh `/json/list`; navigation can replace targets.
- **Node says `WebSocket` is undefined:** use Node.js 22 or newer.
