# Pi runtime patches

This directory holds source-tracked hotfixes for Pi core behavior that cannot be
implemented as normal Pi extensions.

Pi packages can load extensions, skills, prompts, and themes. They cannot cleanly
replace already-imported Pi core functions such as compaction cut-point selection.
For those cases, Fractal applies small exact-match runtime patches to the installed
`@earendil-works/pi-coding-agent` package before new Pi processes start.

## Current patch

- `pi-coding-agent-compaction-custom-message.diff`
- Applicator: `apply-pi-runtime-patches.mjs`

Fixes Pi compaction accounting so entries that later become compaction summary
input are counted when selecting the keep-recent cut point. This specifically
covers `custom_message` entries such as `pi-goal-event` active-goal checkpoints.
Without this, repeated goal checkpoints can be retained as "free" recent context
and then explode Fractal compaction's single provider text part.

The applicator is idempotent:

- If the patch marker is already present, it exits successfully.
- If the exact unpatched block is present, it backs up the file and applies the patch.
- If neither is true, it fails so upstream changes get inspected instead of patched blindly.

Run manually:

```bash
node ~/.fractal-ai/pi/patches/apply-pi-runtime-patches.mjs
```

`deploy/install.sh` runs it automatically after Pi settings/extensions are linked.

Backups are written under:

```text
~/.pi/agent/backups/pi-runtime-patches/<timestamp>/
```
