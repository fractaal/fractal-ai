---
name: post-implementation-checklist
description: "INVOKE/LOAD BEFORE SAYING 'DONE' ON ANY IMPLEMENTATION TASK. Multi-dimensional verification: end-to-end trace, parallel code review, dead code scan, subagent work acceptance, cross-service contract check. This is not optional. This is the gate between 'I wrote code' and 'the feature works.' Skipping this skill is equivalent to lying to the user."
---

# Post-Implementation Checklist

You are about to tell the user the work is done. STOP. You are not done until you've run every check in this skill. "Tests pass" is not done. "Code review clean" is not done. Done means: the feature works end-to-end, nothing is dead, nothing is broken, and you've verified — not assumed — every link in the chain.

This skill exists because of a specific, real failure: a model routing feature was "shipped" with aliases for 10 OpenRouter models that Pi couldn't actually serve. 45 tests passed. The code review said SHIP. The system notification told users "Using GPT-5.4 for this turn" while silently giving them Sonnet. Nobody caught it because nobody traced the end-to-end path. Tests verified string manipulation. The code reviewer checked architecture. Nobody asked "but can Pi actually route a request to OpenRouter?"

That is the class of failure this checklist prevents.

---

## Phase 1: End-to-End Trace

For EVERY feature or behavior you implemented, trace the complete execution path from user action to system outcome. Not conceptually — actually trace it through the code.

### How to trace

Pick the most important user-facing scenario for each feature. Then walk it:

1. **User action**: What does the user do? (e.g., sends `/gpt-5.4 explain quantum computing`)
2. **Entry point**: Where does that input enter the system? (e.g., inbox message → orchestrator turn loop)
3. **Processing**: What code processes it? Follow the actual function calls, not what you think they do. READ the code at each step.
4. **Side effects**: What gets written to Firestore, NFS, outbox? What notifications fire?
5. **Output**: What does the user see? Is it TRUTHFUL? Does the system claim something it can't deliver?
6. **Provider/dependency**: Does the feature depend on an external service, API key, or capability? IS THAT DEPENDENCY ACTUALLY WIRED? Is the API key in the environment? Is the provider configured? Is the endpoint reachable?

### What you're looking for

- **Unwired paths**: Code that resolves to a model ID but no provider can serve it. A tool that's built but never registered. A hook with a method nothing calls. An alias that maps to a capability that doesn't exist.
- **Silent fallbacks**: A function that falls back to a default when it gets an unrecognized input, WITHOUT telling the user. This is the most dangerous failure mode — the system silently does something different from what it claimed.
- **Truthfulness**: Every user-facing message (notifications, status, confirmations) must be TRUE at the moment it's displayed. "Using GPT-5.4 for this turn" when the system can't route to GPT-5.4 is a lie. If you can't guarantee the message is true, don't emit it.

### The question that catches everything

Ask yourself: **"If the user is watching the system's behavior right now, would they see what they expect to see?"**

If you can't answer yes with certainty, you haven't verified. Go back and trace until you can.

---

## Phase 2: Dead Code Scan

Search for code you wrote (or that subagents wrote) that nothing reaches:

- **Methods with no callers**: `markSensitive()` that nothing calls. `buildWorkspaceTools()` that's never concatenated into the tool list. Grep for every exported function and verify at least one live code path calls it.
- **Exports with no importers**: Modules that export functions, but no file imports them.
- **Config that's never read**: Environment variables added to the config schema but never passed to the code that needs them. API keys in the config that no `getApiKey` callback returns.
- **Aliases/mappings for unimplemented capabilities**: An alias map that lists models the system can't serve. A routing table with entries for providers that aren't wired. A feature flag for a feature that doesn't exist.

### How to check

For every new function, class, or export you created:
```
grep -r "functionName" --include="*.ts" --include="*.py" src/
```

If a function only appears at its definition and in its test file, it's dead code. Dead code that was supposed to be wired is a feature that doesn't work.

---

## Phase 3: Multi-Dimensional Code Review

Spawn MULTIPLE code review agents IN PARALLEL, each with a DIFFERENT mandate. A single reviewer checking one dimension found clean architecture around a broken feature. That must never happen again.

### Reviewer 1: Architecture

Dispatch the `code-reviewer` skill in an isolated subagent. It checks:
- Layering violations, import cycles, kernel policy leaks
- Naming that lies about structure
- Defensive handler pileups
- "This whole approach is wrong" moments

### Reviewer 2: Functional Completeness

Spawn a SEPARATE subagent (NOT the architecture reviewer) with this specific mandate:

> "Verify that every feature in this diff ACTUALLY WORKS end-to-end. For each feature: trace the user action through every function call to the final system output. Check for: aliases that map to unservable capabilities, methods that nothing calls, providers that aren't wired, config that isn't plumbed to the code that reads it, notifications that claim something the system can't deliver. If you find a feature that is 'implemented' but has an unwired dependency, that is a BLOCKING finding."

This is the reviewer that would have caught the OpenRouter failure. It doesn't care about architecture — it cares about "does this actually work."

### Reviewer 3: Regression / Cross-Service Contracts

Spawn a THIRD subagent:

> "Check that this diff doesn't break anything that already works. Specifically: Firestore fields that other services read (gateway, dashboard, scheduler) — were any removed or renamed? API contracts between services — were any request/response shapes changed? Environment variables or secrets — were any removed that other code paths depend on? If the diff touches a shared data structure, verify every reader still gets what it expects."

### Why three reviewers

Each reviewer has a different failure mode they catch:
- Architecture catches "this is structured wrong"
- Functional completeness catches "this doesn't actually work"
- Regression catches "this breaks something else"

One reviewer checking all three does a shallow job on each. Three reviewers each going deep on one dimension is how you catch the thing that ships broken.

---

## Phase 4: Subagent Work Acceptance

If subagents did any of the implementation work, DO NOT accept their summary at face value. Subagent summaries describe what the agent INTENDED to do, not necessarily what it DID.

### What to check

1. **Read the actual diff**, not the summary. Open the files the subagent modified. Read the code. Does it do what the summary claims?

2. **Ask "what did you NOT do?"** The subagent will tell you what it built. It won't tell you what it skipped, forgot, or deferred. Look at the original task scope and compare against the actual deliverables. If the task said "implement X + Y" and the subagent only mentions X in its summary, Y is probably missing.

3. **Check the wiring.** The most common subagent failure: building a module that works in isolation but isn't connected to the system. The module is tested. The tests pass. The module does nothing in production because nothing calls it. Check: is the module imported somewhere? Is the function called? Is the tool registered? Is the hook in the registry? Is the config plumbed?

4. **Run the tests yourself.** Don't trust "all tests pass" in the subagent's summary. Run them yourself and read the output. Test counts don't mean the right things are tested. A module with 45 passing tests that verify string manipulation while the underlying provider isn't wired has 45 tests that prove nothing about whether the feature works.

### The telephone game

Every layer of delegation introduces information loss. You told the subagent what to build. The subagent built something and described it back to you. You read the description and decided it was done. At every hop, detail gets lost and assumptions get introduced. The only way to break the telephone game is to GO BACK TO THE SOURCE — read the code, run the tests, trace the path.

---

## Phase 5: Cross-Service Contract Check

If your changes touch data that flows between services (Firestore documents, NFS files, HTTP request/response shapes, environment variables), verify the contract is intact.

### Firestore fields

For every Firestore field you added, removed, or changed:
- What other services READ this field? (gateway, dashboard, scheduler, other workers)
- Do those readers handle the new shape? The missing field? The renamed field?
- If you added a new field, do readers that enumerate fields (like a status display) need updating?

### Environment variables and secrets

For every env var or secret you added:
- Is it in the Cloud Build config (`cloudbuild/*.yaml`) for the service?
- Is it in Secret Manager (if it's a secret)?
- If you added it to one service's Cloud Build, does another service also need it?

### HTTP contracts

For every HTTP endpoint or payload you changed:
- What clients call this endpoint?
- Do they send/expect the new shape?
- Is there a version mismatch window during rolling deploys?

---

## Phase 6: Confidence Statement

After completing all phases, state your confidence level honestly:

- **"The feature works end-to-end. I traced it. I verified the dependencies. I read the subagent code. All three reviewers are clean."** → You can say done.
- **"Tests pass and architecture looks clean, but I haven't traced the end-to-end path for [specific feature]."** → You are NOT done. Go trace it.
- **"I'm not sure if [dependency/provider/config] is actually wired."** → You are NOT done. Go check.
- **"The subagent said it's done and I trust the summary."** → You are NOT done. You haven't verified. Go read the code.

If your confidence statement has ANY hedge ("I think," "it should," "the subagent reported"), you are not done. The user deserves certainty, not hedges. Go back and close the gap.

---

## The Standard

The bar is not "I believe it works." The bar is "I have personally verified every link in the chain and can explain exactly what happens when a user exercises this feature." That is done. Everything else is in-progress.

---

## Code Writing Discipline (Reference)

These are the implementation standards that apply DURING the work, before this checklist runs. They're here so you don't have to context-switch to find them.

### DO NOT
- Insert `TODO`s, `// fill later`, or leave functions unimplemented
- Write inline `import()` types — import and name types properly at the top
- Leave untyped parameters, ambiguous `any`s, or magic strings where types belong
- Mix concerns (business logic in controllers, DB logic in DTOs)
- Write temporary hacks unless LOUDLY documented with removal criteria
- Produce code that assumes context or leaves implementation to "later" — always provide end-to-end usable code

### DO
- Treat every implementation as production-grade
- Prefer clarity over cleverness
- Follow consistent naming conventions and imports
- Handle edge cases and input validation unless explicitly told not to
- Maintain architectural discipline (controllers → orchestration, services → logic, repositories → data)
- Explain WHY in comments, not WHAT

### Pattern-Matching Rule

The most common failure mode: you know an API conceptually but get its exact signature wrong. A decorator that takes 3 positional args, you pass 2. A function that returns a dict with a specific shape, you return a bare string.

These are ALWAYS preventable:
- **Before writing**: Read the nearest existing usage of the same API in the codebase
- **After writing**: Verify your call signature matches the reference — arg count, arg types, return type, keyword vs positional

If a working example exists 3 files over, there is zero excuse for getting the signature wrong.

### Verification Basics

Before considering any code change ready for this checklist:

1. **Read existing implementations first.** When creating a new file that follows an existing pattern, ALWAYS read an adjacent existing implementation and match its signatures and conventions exactly. The reference file is the source of truth — not your training data.

2. **Run basic sanity checks.** At minimum, verify the code can be loaded without crashing:
   - Python: `python -c "from module import thing"`
   - TypeScript/Node: `npx tsc --noEmit` or `node -e "require('./module')"`
   - If a build command exists, run it.

3. **Run the tests.** Every time. Before every commit. This is a hard gate. If tests don't run (missing env vars, broken fakes), that is YOUR problem to solve — not an excuse to skip. If you changed code and didn't run the tests, you didn't finish.

4. **Cross-check at module boundaries.** Verify exports, imports, and function signatures match across all callers. Silent mismatches are worse than crashes.
