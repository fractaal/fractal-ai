---
name: writing-and-maintaining-tests
description: Write, review, refactor, or delete tests so they verify required behavior and forbidden side effects at the correct abstraction level instead of freezing implementation choreography. Use for unit, integration, regression, acceptance, end-to-end, and characterization tests; test-driven development; refactors; bug fixes; flaky or mock-heavy suites; questions about what deserves coverage; and audits of implementation-heavy tests.
---

# Writing and Maintaining Tests

## Core rule

Test the contract at the abstraction level under test:

> Given meaningful input and state, does the system produce the promised outcome without prohibited side effects?

For a pure function, the contract may be an exact input/output mapping: passing `Alice` returns green; `2 + 3` returns `5`.

For a business process, test the business result. Do not replace that result with assertions about private helpers, cursor movement, polling choreography, internal data structures, or the order in which implementation steps happen.

If refilling a water bottle is itself a required outcome, test it. If it is merely an incidental way the current implementation reaches some other outcome, do not freeze it into the suite.

## Match the test to the level

- **Pure function:** Assert returned values and documented deterministic errors.
- **Stateful unit:** Assert documented state transitions through its public interface.
- **UI component:** Assert visible/accessibility output and user interactions, not component internals.
- **API or process boundary:** Assert request/response contracts, authorization, durable state changes, and externally visible side effects.
- **Business workflow:** Assert the actor's starting state, action, promised outcome, and prohibited side effects across the workflow.
- **Reliability or security mechanism:** Assert the real guarantee—exactly-once effect, ordering, bounded work, fail-closed authorization, recovery, or liveness—not the current retry loop or storage trick.

“Behavior” does not mean “only pixels.” Durable writes, messages sent, jobs not started, authorization decisions, idempotency, ordering, bounded request volume, and recovery after failure are behavior when callers or operators rely on them.

## Design a test

Before writing test code:

1. **Name the contract.** State it in caller or owner vocabulary. Use mechanism terms only when the mechanism is itself an owned contract, such as a wire format, algorithm, or idempotency key.
2. **Write Given / When / Then.** Use business or caller vocabulary.
3. **Choose a stable observation seam.** Prefer a public function, API, rendered UI, persisted state, emitted boundary message, or externally owned dependency.
4. **Name prohibited side effects.** Assert only risks the contract genuinely forbids, such as charging twice, starting a cloud worker, losing queued input, or leaking another user's data.
5. **Use the lowest test level that can prove the contract.** Do not use an end-to-end test for arithmetic; do not use a mocked unit test to claim a distributed workflow works.
6. **Run the refactor test.** Ask: “Could the internals be replaced wholesale while preserving the contract and leave this test unchanged?” If not, either the implementation is the contract or the test is coupled at the wrong level.

Prefer test names such as:

- `a waiting guest message appears once under Pending`
- `reconnecting discovers messages queued while the host was offline`
- `a failed first message prevents later messages from being accepted out of order`

Avoid names such as:

- `advances dispatch cursor after retaining event`
- `calls helper B after helper A`
- `polls the broker exactly twice`

unless that exact mechanism is an owned, documented contract.

## Use mocks and fakes carefully

Mock at real boundaries, not between every internal function.

Good uses:

- Prevent a real payment while asserting one charge request with the promised amount.
- Replace an email provider while asserting the user receives the required notification.
- Replace a remote Gateway while asserting the local runtime receives one message.
- Assert a cloud worker was not started when local execution is required.

Bad uses:

- Mock every private collaborator and assert the full call sequence.
- Assert internal helper call counts instead of the final state.
- Reproduce the implementation in the test and compare it to itself.
- Treat a mocked transport success as proof of the end-to-end feature.

A collaborator call is valid to assert when the call is itself an externally meaningful side effect or boundary contract. It is not valid merely because spying on it is convenient.

## Test time, retries, queues, and background work by guarantee

Do not assert exact polling intervals, retry counts, cursor values, or queue scans unless those values are explicit product or protocol contracts.

Instead assert guarantees such as:

- the operation eventually succeeds within a required bound;
- one input causes at most one externally visible effect;
- retries preserve the same idempotency identity;
- an earlier failure prevents unsafe later acknowledgement;
- temporary failure does not permanently stop liveness;
- recovery work is bounded by a documented scale unit;
- one blocked item does not starve unrelated work.

Use fake time when needed to reach the behavior, but do not make the fake timer choreography the subject of the test.

## Maintain suites during refactors

Before a substantial refactor, classify affected tests:

- **Behavioral:** Contract and assertions remain valid unchanged.
- **Mixed:** Preserve outcome assertions; remove or rewrite choreography assertions.
- **Implementation-only:** Delete when the mechanism disappears. Do not port it to the replacement for the sake of retaining test count.
- **Missing:** Add a behavior-first characterization or acceptance test before changing the implementation when current behavior must be preserved.

Do not make a correct refactor imitate obsolete internals to keep old tests green. Test count is not a quality metric. Every test is code and maintenance liability; retain the smallest suite that protects distinct, valuable guarantees.

When fixing a bug:

1. Write a regression scenario in user, caller, security, durability, or operational terms.
2. Make it fail for the actual broken outcome.
3. Fix the root cause.
4. Verify the regression test and the surrounding behavioral suite.
5. Remove any old test that requires the broken implementation behavior.

## Verify features, not proxies

A green unit suite proves only the tested units. Before claiming the feature works, trace the real path from initiating action to final outcome and select tests or direct verification that cover the meaningful boundaries.

Do not claim:

- a UI works because its model parser passed;
- delivery works because enqueueing passed;
- recovery works because a cursor advanced;
- authorization works because the happy path returned 200.

Cover the actual behavior and the important negative path.

## Review checklist

For every added or modified test, ask:

- What requirement or real failure does this protect?
- Is the assertion observable at this abstraction level?
- Does the name describe behavior rather than machinery?
- Are forbidden side effects explicit and justified?
- Could a valid internal rewrite keep this test green?
- Does the test duplicate another guarantee?
- Is a mock hiding the boundary that actually needs verification?
- Would deleting this test remove meaningful confidence, or only reduce the test count?

If the answer to the last question is “only reduce the count,” delete the test.
