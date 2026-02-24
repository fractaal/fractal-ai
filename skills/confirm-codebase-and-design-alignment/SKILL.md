---
name: confirm-codebase-and-design-alignment
description: INVOKE/LOAD BEFORE IMPLEMENTING ANY SIGNIFICANT CODE CHANGE (SUCH AS A NEW FEATURE). WHY: Verify the request against existing system contracts, prior decisions, and codebase intent. If misaligned, surface the conflict early and propose alternatives.
---

# Confirming Codebase and Design Alignment

## Overview

Prevent implementation drift by checking that a requested change fits the system's existing contracts and design intent. If the request conflicts with known constraints or prior decisions, pause and surface the mismatch before coding.

## When to Use

Use this skill whenever:

- A request alters control/data flow (e.g., return data from tools, make X synchronous, change API semantics).
- A request touches a core contract (tool calling, async behavior, state ownership, determinism).
- A request might conflict with existing design decisions or architecture.

## Workflow

1. Identify the implied contract.
2. Verify against reality (code, docs, and prior decisions).
3. Detect mismatch and surface it immediately.
4. Present aligned alternatives.
5. Ask for a decision before implementing.

## Rules

- Do not smooth over contract mismatches by implementing anyway.
- Prefer explicit alignment over silent accommodation.
- If multiple valid interpretations exist, ask which one to pursue.
- If the request is aligned, proceed without extra friction.

## Response Template (recommended)

- Assumption: what the request seems to assume.
- Conflict: what the system actually does.
- Options: aligned alternatives.
- Recommendation: suggested path and why.
- Question: ask for the choice.

## Examples

Mismatch example:

- Request: Add a tool that returns data immediately to a script.
- Conflict: Tools are async; scripts will not see results the same tick.
- Options: Put data in ctx, or use next-tick read pattern.
- Ask for choice.

Aligned example:

- Request: Expose a new sensor field in ctx.
- Fits: Data belongs in ctx and is consumed synchronously.
