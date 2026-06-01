---
name: observability-pass
description: 'A targeted, exhaustive instrumentation pass on a SPECIFIC slice of code the user names — trace every hop, log every decision/branch/catch/boundary, leave no code path unturned. Stronger and narrower than code-review''s A10: A10 flags gaps in a review; THIS goes and closes every one in the named paths. Invoke when the user asks for an observability/instrumentation/logging pass, or says "make this debuggable", "no code path unturned", "log out the wazoo on X".'
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# Observability Pass

You are doing a **deliberate, exhaustive instrumentation pass** on a specific slice of code. This is not a review that *flags* missing logs — it is the act of going through the named paths and **closing every observability gap**, so that if any path breaks in production the log alone names the failing hop and the reason, with no repro and no debugger.

The standard is the user's own words: **no code path unturned.** Take it literally. The only thing that should NOT be logged is per-tick / hot-loop spam — and even that gets logged on meaningful state *transitions* (see "The one exception"). Everything else leaves a trail.

This is intentionally 10x stronger than `code-reviewer`'s A10 `observability-gap` trigger. A10 is a review heuristic ("this looks under-instrumented, flag it"). This skill is a targeted operation: the user points at a slice, and you make that slice *fully observable*, end to end, verified.

## When this runs

The user invokes it deliberately, on a named target — "do an observability pass on the perform_action path", "instrument the new resolver", "make the auth flow fully traceable". It is a **personal-judgement, on-demand** discipline, not something to apply to a whole codebase unprompted. Scope is whatever the user names; if they didn't name a scope, ask for one (a function, a file, a feature's request→response path, a subsystem).

**Scope discipline:** instrument the NAMED paths and everything they call that is *yours*. Do not wander into unrelated code. Do not instrument the runtime/library/engine internals you merely *call* — you cannot, and the boundary log + an outcome-watch is how you observe a black box from outside (see step 4).

## The method

### 1. Scope it precisely

State, in one or two lines, exactly which paths are in scope. A path = a user/event action → every hop it flows through → the outcome. If the feature has more than one entry (a first-call path vs. a follow-up path; a success branch vs. a failure branch), each is a path and each gets traced.

### 2. Trace every hop — actually trace it

`grep` for every caller of the entry point and every callee it invokes. Read the bodies. Build a **hop table** — one row per hop from entry to outcome. This is the spine of the pass; you instrument against it and you report against it. Do not work from memory of what the code "probably does" — open it.

Include the hops you didn't write but the path flows through (a shared dispatcher, a callback sink, a self-loop where an outcome re-enters the entry point). The bug that hides is in the hop you assumed was fine.

### 3. At each hop, fire on every trigger

For each hop, add a structured log at every one of these (any that apply):

1. **Entry / intent** — the hop started; log the inputs that decide what it does (IDs, counts, the action/verb, key flags). One line that says "we are about to do X with these parameters".
2. **Decision point** — any branch, guard, permission/tier gate, cache hit/miss, match/no-match, retry/give-up. Log **which way it went AND why.** "why" is not optional — if the decision rests on an underlying check that produces a reason (a validator's message, an engine's "can't because…", an exception text), **surface that reason in the log.** A decision logged without its cause is half a clue.
3. **External-call boundary** — any HTTP / DB / RPC / subprocess / filesystem / cross-process / engine-API call. Log **before** (intent + context) and **after** (outcome + metadata: status, count, elapsed, id). This is the seam between your code and a black box; both sides must be visible.
4. **Drop / skip / early-return** — anywhere code does `continue`, `return null`, `break`, swallows an item, filters something out, or chooses to do nothing. A silent drop is the single most common way a feature becomes a no-op with zero trace. Log what was dropped and why.
5. **State mutation that matters** — enqueue/dequeue, flag flip, set membership, status transition, anything a later hop or a sibling path reads. Log the transition.
6. **Outcome** — the hop's result (done / failed-with-reason / partial), and any follow-on it triggers (e.g. "chained N follow-up actions").

### 4. Kill every silent catch — and the dangerous default

`catch { }` and `catch { return X; }` with no log are **banned** in the scoped paths. Every catch logs at WARN/ERROR with the exception message (and stack when it's a real bug, not an expected miss).

Pay special attention to the **catch that returns a success-ish or terminal default on error** — e.g. a completion check that `catch { return Done; }`, or a validator that `catch { return false; }`. These don't just hide the error; they can manufacture a *false positive* (a "succeeded" that didn't, a "not allowed" that actually threw). These are the highest-value lines in the whole pass. Log them loudly; consider whether the default is even correct.

For an external black box you call (a library/engine you can't instrument inside), the boundary log (step 3) plus, where the operation is async/fire-and-forget, an **outcome watch that narrates itself** (polling/observing the result and logging each meaningful transition) is how you keep it observable from outside.

### 5. Add loud traps for "impossible" states

Where an invariant should hold but the code can't prove it at compile time — a parsed-but-unhandled result, a registered-but-missing handler, a count that should never be zero here — add an explicit branch that logs a **loud WARN naming it as a probable caller bug**, rather than letting it pass silently. The "impossible" state is exactly what you'll be hunting at 2am; make it announce itself.

### 6. Log content rules (don't make the trail a liability)

- **Log:** IDs, GUIDs, names, counts, operation/verb names, timing, status codes, decision outcomes, the underlying "why" strings.
- **Don't log:** user content / message bodies, credentials, secrets, tokens, full request/response payloads.
- **Truncate** partial content that's genuinely useful for debugging (first ~100–200 chars via a `Clip`/`truncate` helper), never the whole 15KB blob.
- Use the project's **structured logger**, not `print`/`console.log`/`Debug.Log` ad hoc — match the surrounding code's logger and tag convention exactly (read a neighbour first).
- Respect the runtime's **floor severity**. If the repo's instructions say a level is dropped (e.g. "DEBUG is dropped in prod"), don't put load-bearing trail logs below it — they're functionally invisible. Put the reconstructable trail at INFO (or the repo's lowest *kept* level); reserve WARN/ERROR for catches, drops, and traps.
- Keep the tag/prefix consistent (e.g. `[Subsystem] verb: …`) so the whole path is greppable as one stream.

### 7. The one exception — per-tick / hot-loop spam

The only code that should NOT log every pass is something that runs every frame / every tick / every iteration of a tight loop, where per-iteration logging would bury the trail and tank performance. Even then, do not go dark:

- **Edge-triggered, not level-triggered.** Log when the tick's *meaningful state changes* — the condition flips, the phase transitions, a threshold is crossed, an error first appears — not on every identical pass. "Still running" every 50ms is spam; "entered Cancelling" once is the signal.
- **Optionally gate verbose per-tick detail behind a debug flag** (a `verbose`/`traceTicks` bool, default off) so it can be turned on for a session when hunting a specific tick-level bug, and stays silent otherwise.
- A timeout / give-up / unexpected-exit inside the loop is NOT spam — always log it.

### 8. Build, then VERIFY by exercising the path

Instrumentation you didn't run is a guess. After editing:

1. **Build** the affected projects; fix any errors.
2. **Exercise the scoped path** for real if you can — drive the entry point (an HTTP call, a unit/smoke invocation, a CLI run) and **`grep` the resulting log for the expected trail.** Confirm the breadcrumbs actually appear, in order, with the IDs/reasons populated.
3. If the path can't be exercised headlessly (needs a running game/GUI/external system), say so plainly and hand the user the exact log lines to look for when *they* exercise it.

### 9. Report: the hop table + the honest residual

Deliver a **hop table** — every hop from entry to outcome, each marked ✅ instrumented — so the user can see coverage at a glance. Then state the **honest residual**: what is deliberately NOT logged and why. There almost always is one, and naming it is the difference between "comprehensive" and "claimed comprehensive":

- Trivial non-decision plumbing (building a struct/JSON body — nothing to decide; it either works or throws-and-is-caught).
- Engine/library internals you call but don't own (covered by the boundary log + outcome watch).
- Per-tick detail intentionally gated/edge-triggered per step 7.

If you cannot point to the log line that would fire for a given failure in a scoped path, that path is **not done** — go back and add it. The bar is: **name any failure in scope, and name the log line that catches it.**

## The acceptance test

> Pick any hop in the scoped paths. Imagine it fails — wrong branch, thrown exception, silent drop, external call errors. **Does the log, by itself, tell you which hop failed and why — with no repro, no debugger, no added logging after the fact?**

If yes for every hop: done. If no for any hop: not done.

## Anti-patterns (what a weak pass looks like)

- **Boundaries only.** Logging entry and exit but leaving the decision-making middle (the resolver, the matcher, the branch ladder) a black box. The middle is *where it picks wrong* — it needs the most logging, not the least.
- **Decision without cause.** "rejected candidate X" without the reason X was rejected. Half a clue is a second debugging session.
- **Surviving silent catches.** Any `catch {}` left in scope. Especially one returning a terminal/success default.
- **`return null` / `continue` with no log.** The silent no-op; the feature "does nothing" and the log is empty.
- **Trail below floor severity.** A beautiful trail at DEBUG in a runtime that drops DEBUG = no trail.
- **"Comprehensive" with no residual stated.** If you didn't name what you left out, you didn't audit the boundary of the pass.
- **Claimed, not verified.** "Added logging" without building and exercising the path to see the breadcrumbs actually print.
