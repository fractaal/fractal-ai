---
name: pre-implementation-checklist
description: "🚨 INVOKE/LOAD BEFORE WRITING A SINGLE LINE OF CODE ON ANY NON-TRIVIAL TASK. Due diligence: research the system, verify assumptions, check dependencies, confirm design alignment, understand what exists. This is not optional. Skipping this is how you ship features that don't work because you assumed instead of checked. Every catastrophic implementation failure traces back to skipping this step."
---

# Pre-Implementation Checklist

You are about to write code. STOP. You do not yet know enough to write code. You think you do. You are wrong. Every catastrophic implementation failure in the history of this collaboration traces back to one moment: someone started building before they understood what they were building on top of.

This skill exists because of a specific, real failure: a model routing feature was decomposed into "build the alias module" and "wire the provider" — but nobody checked whether pi-ai even supported OpenRouter before spawning three parallel agents. One grep of the README would have answered the question. Instead, three agents ran for 20 minutes, produced 150+ tests, got code-reviewed, got merged, got deployed — and the feature didn't work because the provider was never wired. The decomposition was wrong because the research wasn't done.

That is the class of failure this checklist prevents.

---

## Phase 1: Understand the Task

Before anything else, make sure you actually understand what you're being asked to do. Not what you THINK you're being asked. What you're ACTUALLY being asked.

### Restate the task

In your own words, state:
1. What is the user asking for?
2. What does "done" look like? What would the user see/experience when this works?
3. What are the boundaries? What's in scope and what isn't?

If you can't answer #2 concretely ("the user sends /gpt-5.4 and gets a response from GPT-5.4 via OpenRouter"), you don't understand the task well enough to implement it. Ask clarifying questions.

### Identify the end-to-end path

Before writing code, trace the ENTIRE path the feature will take through the system:
- Where does user input enter?
- What processes it?
- What external dependencies does it need? (APIs, providers, secrets, services)
- What does the output look like?
- Who/what consumes the output?

Write this path down. You will verify each link exists (or needs to be built) in the next phases.

---

## Phase 2: Research the System

You are about to build on top of an existing system. DO NOT ASSUME YOU KNOW HOW IT WORKS. Read it. Grep it. Trace it.

### Check what already exists

Before building ANYTHING:

```
# Does this capability already exist somewhere?
grep -r "the thing you're about to build" src/

# Is there an adjacent implementation you should follow?
ls src/hooks/  # or src/tools/ or wherever the pattern lives

# What does the existing system look like at the integration point?
# READ the actual function you'll be calling/extending. Not from memory. From the file.
```

The CLAUDE.md for the project lists existing systems. READ IT. The pattern of "I didn't know this existed" is the failure mode to avoid. If the project has a section called "Check Existing Systems Before Building" — that section exists because someone built something that already existed. Don't be that someone.

### Check dependencies and providers

If the feature depends on an external service, API, library, or provider:

1. **Does the dependency support what you need?** READ THE DOCS. Don't assume. `pi-ai` supports OpenRouter — one grep of the README would have shown this. But you have to actually grep it.

2. **Is the dependency already configured?** Is the API key in the environment? Is the provider wired in the config? Is the endpoint reachable? Check the ACTUAL config files, Cloud Build secrets, and environment setup.

3. **What's the integration surface?** What function do you call? What does it expect? What does it return? READ THE ACTUAL API, not your memory of it.

```bash
# Is this API key in the environment/secrets?
gcloud secrets list --project=PROJECT --format="value(name)" | grep -i "the key"

# Is it in the Cloud Build config?
grep -r "THE_KEY" cloudbuild/

# What does the library's API actually look like?
grep -r "getModel\|createProvider" node_modules/@lib/README.md
```

### Check cross-service contracts

If the feature writes data that other services read:
- What services read this data?
- What shape do they expect?
- Will your change break their expectations?

If the feature consumes data from other services:
- Where does that data come from?
- Is the field you're reading actually populated?
- What happens if it's missing/null?

---

## Phase 3: Confirm Design Alignment

Verify your planned approach fits the system's architecture and prior decisions.

### Contract check

- Does your approach conflict with any existing system contract? (async behavior, state ownership, data flow direction)
- Does the project CLAUDE.md or AGENTS.md document architectural decisions that constrain your approach?
- Are you about to put policy in the kernel? Business logic in the transport layer? Domain vocabulary where it doesn't belong?

### Prior art check

- Has this been attempted before? Check git history, engineering logs, scratchpads.
- Is there a design spec or plan document? Check `docs/`, `.ai/`, engineering logs.
- Did a previous session make decisions about this that you should honor?

### If anything is misaligned

STOP. Surface the mismatch to the user BEFORE writing code:
- What you assumed vs what the system actually does
- What the conflict is
- What the options are
- What you recommend and why

Do not smooth over mismatches by implementing anyway. Explicit alignment before code.

---

## Phase 4: Plan the Decomposition

If the task is large enough to decompose into subtasks or subagents:

### Verify each subtask is END-TO-END

Every subtask must produce something that WORKS, not something that exists in isolation. "Build the alias module" is not a complete subtask if the module can't function without a provider that nobody is wiring. The subtask is "implement OpenRouter model routing" — which includes the module AND the wiring AND the provider config AND the Cloud Build secret.

### Verify no gaps between subtasks

If subtask A produces a module and subtask B wires it, what happens if B doesn't get done? You have dead code. The decomposition must be gap-free — every output of A is consumed by B, and if B depends on A, they're either the same subtask or there's explicit tracking that B exists.

### If spawning subagents

Each subagent gets:
- FULL system context (architecture, what exists, what the feature needs end-to-end)
- The ability to flag integration gaps
- An understanding of what OTHER subtasks exist and how their work connects

DO NOT tell subagents "don't touch X" or "wiring is a separate task." That is how half-built features ship. The subagent sees the whole picture or it CANNOT DO ITS JOB.

---

## Phase 5: State Your Assumptions

Before writing code, explicitly list every assumption you're making:

- "I assume pi-ai supports OpenRouter" → VERIFY THIS
- "I assume the API key is in Secret Manager" → VERIFY THIS
- "I assume the orchestrator can accept a per-turn model override" → VERIFY THIS
- "I assume the gateway reads resolved_model from the session doc" → VERIFY THIS

For EVERY assumption: either verify it RIGHT NOW (grep, read, check), or flag it as unverified and tell the user "I'm assuming X but haven't confirmed it."

An unverified assumption is a bomb in your implementation. It might be fine. It might blow up 3 hours from now when you discover the thing you assumed doesn't exist. Verify now. It takes 30 seconds. The alternative takes hours.

---

## The Gate

You may proceed to implementation ONLY when:

1. You can state what "done" looks like concretely
2. You've traced the end-to-end path and every link either exists or is explicitly in your build plan
3. You've checked what already exists and aren't rebuilding it
4. You've verified every external dependency is available and configured
5. You've confirmed your approach aligns with the system's architecture
6. You've listed your assumptions and verified each one
7. If decomposing, every subtask is end-to-end and there are no gaps

If ANY of these are incomplete, you are not ready to write code. Do the research. It's faster than debugging a wrong assumption 3 hours into implementation.
