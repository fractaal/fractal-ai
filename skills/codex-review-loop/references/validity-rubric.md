# Validity Rubric

Use this to decide whether a Codex review comment is valid to fix.

## Root-Cause Checkpoint (MANDATORY — run this FIRST)

Before triaging individual comments, look at the batch as a whole:

1. **Do multiple comments describe symptoms of the same underlying issue?** If yes, identify the root cause. Fix the cause, not each symptom individually.
2. **Would the proposed fix add defensive/handling code, or would it eliminate the problem?** Prefer elimination. If the only fix you can think of is "catch this exception and retry/fallback," ask whether the exception can be prevented from occurring in the first place.
3. **Is the cumulative diff growing monotonically across iterations?** If your PR is getting bigger each cycle without converging, you are likely treating symptoms. Pause and rethink the approach.

If this checkpoint reveals a simpler root-cause fix, apply that instead of addressing comments individually — even if it means the fix looks different from what the reviewer suggested.

## Accept As Valid

- The comment identifies a real behavior defect, race, regression risk, security issue, or missing guardrail.
- The fix aligns with explicit project guarantees and current architecture.
- The requested change is in scope for the PR.
- The concern is reproducible from code, logs, tests, or contract text.

## Reject As Invalid

- The comment conflicts with already accepted tradeoffs or explicit non-goals.
- The comment assumes a contract that the project does not provide.
- The request asks for broader redesign outside PR scope.
- The concern is speculative with no concrete failure mode.
- **Multiple comments describe the same root cause** — reject the individual symptom fixes and propose the root-cause elimination instead.

## Response Policy

- Valid comment:
  - React with `+1`.
  - Implement and verify.
- Invalid comment:
  - React with `-1`.
  - Reply with a concise, technical explanation referencing the contract/scope decision.

## Suggested Invalid-Reply Template

```
Not applying this change.
Reason: <explicit contract/scope/tradeoff>.
Current behavior intentionally guarantees <X>, and this suggestion would violate <Y>/expand scope beyond this PR.
```
