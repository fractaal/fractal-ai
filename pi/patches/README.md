# Pi runtime patches

This directory holds source-tracked hotfixes for Pi core behavior that cannot be
implemented as normal Pi extensions.

Pi packages can load extensions, skills, prompts, and themes. They cannot cleanly
replace already-imported Pi core functions such as compaction cut-point selection.
For those cases, Fractal applies small exact-match runtime patches to the installed
`@earendil-works/pi-coding-agent` package before new Pi processes start.

## Current patches

- `pi-coding-agent-compaction-custom-message.diff`
- `pi-coding-agent-indefinite-retries.diff`
- `apply-pi-runtime-patches.mjs` also carries the compaction stop-the-world barrier patch.
- Applicator: `apply-pi-runtime-patches.mjs`

`pi-coding-agent-compaction-custom-message.diff` fixes Pi compaction cut-point
selection. It counts every entry that later becomes compaction summary input,
including `custom_message` entries such as `pi-goal-event` active-goal
checkpoints, so repeated goal checkpoints cannot be retained as "free" recent
context and then explode Fractal compaction's single provider text part. It also
keeps the post-compaction live suffix provider-replay-safe: delayed/background
tool results must retain their matching assistant tool call, and pre-existing
orphan tool results are summarized away when a later safe suffix exists. This
prevents OpenAI/Codex `No tool call found for function call output` failures
after compaction.

`pi-coding-agent-indefinite-retries.diff` changes Pi's agent-level retry default
from 3 attempts to unbounded retries. Explicit finite `retry.maxRetries` settings
still cap retries. The retry backoff is capped at 10 seconds, and unbounded
`auto_retry_start` events report `maxAttempts: null` so interactive/RPC consumers
do not render a misleading finite cap.

The compaction stop-the-world barrier patch makes core compaction/retry a safepoint:
when an assistant message is classified as context overflow, Pi snapshots that
classification before extension hooks run, enters a barrier, defers extension-triggered
turns/messages, ignores nested `ctx.compact()` requests, runs core compaction, retries
when appropriate, and only then releases deferred extension traffic. This prevents goal
or monitor/background extensions from racing the transcript compactor or masking the
overflow before core can recover.

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
