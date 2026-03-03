---
name: codex-review-loop
description: >-
  Run an iterative PR review-fix loop with Codex review comments using GitHub CLI.
  Use when a PR is open, Codex can review it, and the goal is to repeatedly:
  wait for new review comments, validate each comment against accepted
  guarantees/scope/tradeoffs, fix only valid items, push, ping `@codex review`,
  and continue until no valid Codex comments remain.
---

# Codex Review Loop

## Overview

Drive a disciplined PR loop: wait for new comments, separate Codex comments from other reviewers, triage validity against project guarantees and non-goals, apply only valid fixes, then re-request review until convergence.

## Preconditions

- `gh` CLI is installed and authenticated.
- You have push access to the PR branch.

## Step 0 — Define Your Contract (MANDATORY before entering the loop)

**You MUST NOT start polling for comments until you have written the following into the chat, explicitly, for the user to see and approve:**

### 1. Contract to Defend

State the PR's accepted guarantees, explicit non-goals, and chosen tradeoffs. Be specific — not "we handle errors gracefully" but "we accept that `callback.done` is fire-and-forget; we do not block completion on gateway acknowledgment."

Example:
> **Guarantees:** Firestore request is always released, done callback is always attempted.
> **Non-goals:** Guaranteeing the gateway receives the done callback before the request is marked complete.
> **Accepted tradeoffs:** Done callback is fire-and-forget from an isolated task; if it fails, the gateway will recover via its own timeout.

### 2. Desperation Tripwires

Define concrete, measurable lines that — if crossed — mean you MUST stop the loop and rethink:

- **LOC ceiling:** "If my cumulative diff exceeds +N net lines across iterations, I stop." (Suggest: +30 for bugfixes, +80 for features.)
- **Iteration ceiling:** "If I'm still fixing comments after N rounds, I stop." (Suggest: 3 rounds.)
- **Pattern tripwire:** "If I'm adding a second try/except, retry, flag, or fallback for the same underlying issue, I stop."

Example:
> **LOC tripwire:** +40 net lines.
> **Iteration tripwire:** 3 rounds.
> **Pattern tripwire:** Any second defensive handler for cancel-scope corruption means I'm treating symptoms.

### 3. User Approval

After writing the above, **ask the user to confirm** before proceeding. Do not enter the loop until the user says go. This is the moment to catch misaligned assumptions.

---

## Scripts

- `scripts/wait_for_pr_comments.py`
- `scripts/ping_and_wait_codex_review.py`

Purpose:
- Polls PR comments every N seconds (default 30s).
- Baselines current comments.
- Exits when new comments appear.
- Optional author-gated mode keeps polling until target author comments appear.
- Optional persistent state file keeps loop continuity across context compaction/restarts.

Examples:

```bash
# One command: ping `@codex review`, then wait for new Codex comments
scripts/ping_and_wait_codex_review.py --repo symphco/symph-aria --pr 8

# Same, but wait for any author comment
scripts/ping_and_wait_codex_review.py --repo symphco/symph-aria --pr 8 --any-author

# Wait-only mode (do not post a ping)
scripts/ping_and_wait_codex_review.py --repo symphco/symph-aria --pr 8 --skip-ping

# Wait for any new PR comment
scripts/wait_for_pr_comments.py --repo symphco/symph-aria --pr 8

# Wait until Codex comments specifically
# (`--author codex` also matches `chatgpt-codex-connector[bot]`)
scripts/wait_for_pr_comments.py --repo symphco/symph-aria --pr 8 --author codex --require-author

# Persist seen-comment state in repo so loop survives compaction/restarts
scripts/wait_for_pr_comments.py \
  --repo symphco/symph-aria --pr 8 --author codex \
  --state-file .codex/review-loop/pr-8-state.json
```

## STOP — Read This Before Every Iteration

**Code is a liability. Every line you add is a line that can break, a line someone must understand, a line that encodes assumptions that will go stale.** This loop is NOT a license to codemonkey through comments, blindly adding fix after fix after fix, watching the diff grow +10, +10, +10, +10 LOC per cycle. That is a failure mode, not progress.

**The desperation smell:** If your fixes are getting louder — more flags, more retries, more nested exception handlers, more "but what if THIS edge case" — you are fighting symptoms instead of eliminating a root cause. Stop. Step back. Ask yourself: *"Wait — why am I doing this? Can't I just X instead?"*

**Before fixing N comments that look like N separate problems, check if they share one root cause.** If they do, the correct move is to eliminate that cause — even if it means a different, simpler approach than what each individual comment suggests. A rockstar fix is a **negative LOC diff** that makes N problems disappear at once. A good fix is small and neutral. A fix that keeps piling on defensive code to handle the same underlying issue at every surface point is **wrong**, full stop.

**How good fixes look:**
- Negative LOC diff that eliminates a class of problems (best)
- Small, neutral LOC change that addresses a real defect (good)
- Monotonically growing diff that handles the same root issue at N downstream points (+10, +10, +10...) — **this is wrong, stop and rethink**

If you find yourself in the third category after 2+ iterations, you MUST pause the loop, articulate the root cause in a PR comment, and propose a simpler alternative before writing more code.

## Workflow

0. **Complete Step 0 — Define Your Contract.** Do not proceed until the user approves.
1. Set loop marker state file for this PR.
2. Wait for comment delta.
3. If new comments are not from Codex, continue waiting.
4. For each new Codex comment, decide validity using `references/validity-rubric.md` **against the contract defined in Step 0**.
5. **Check desperation tripwires** from Step 0. If any are crossed, STOP — post a PR comment explaining the root cause and propose a simpler alternative. Do not continue fixing.
6. Apply response policy:
   - Valid: react `+1`, implement fix.
   - Invalid: react `-1`, reply with precise rationale tied to the contract from Step 0.
7. Commit, push, and ping review again: `@codex review`.
8. Repeat steps 2-7 until no valid Codex comments remain.

## Reaction Commands

Use the comment `type` from script output (`issue` or `review`).

```bash
# +1 / -1 reaction on issue comment
# CONTENT is +1 or -1
gh api -X POST repos/$REPO/issues/comments/$COMMENT_ID/reactions \
  -H "Accept: application/vnd.github+json" \
  -f content="$CONTENT"

# +1 / -1 reaction on review comment
# CONTENT is +1 or -1
gh api -X POST repos/$REPO/pulls/comments/$COMMENT_ID/reactions \
  -H "Accept: application/vnd.github+json" \
  -f content="$CONTENT"
```

Reply for invalid comments:

```bash
# Reply in PR thread (simple and reliable)
gh pr comment $PR --repo $REPO --body "Re: <comment-url>\nNot applying this because <contract-aligned reason>."

# Optional: inline reply to a review comment
gh api -X POST repos/$REPO/pulls/$PR/comments \
  -f body="Not applying this because <contract-aligned reason>." \
  -F in_reply_to=$COMMENT_ID
```

## Rules

- Never apply suggestions blindly.
- Never reject without explicit contract/scope rationale.
- Prefer minimal diffs that satisfy valid comments.
- After each fix batch, rerun tests/lint relevant to changed files.
- Keep the loop state file updated (`--state-file`) until review convergence.
