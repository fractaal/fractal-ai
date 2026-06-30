---
name: story-first-planmaking
description: >-
  INVOKE/LOAD WHEN drafting a North Star, architecture plan, implementation plan,
  multi-service design, or goal reference doc where Ben needs the plan to explain
  WHY system pieces exist before naming schemas/endpoints. Use when the user asks
  for "user story first", "story-first", "pseudocode-level plan", "behavior-level
  plan", "not a wall of schemas", "not too vague", "not so low-level we're just
  writing the thing", "surface work surfaces", "zero to hero plan", or when a
  plan would otherwise start with data shapes, services, endpoints, or task
  decomposition instead of the lived user/system flow.
---

# Story-First Planmaking

Ben does **not** want architecture plans that start with “new schemas/endpoints/tasks.”
That hides the why. The correct shape starts with the lived user/system story, then
lets each required service, schema, endpoint, state field, and invariant appear as
a consequence of that story.

The target altitude is:

> **Behavior/pseudocode level**: concrete enough to expose work surfaces and
> integration seams; high-level enough that the plan is not already the code and
> does not micromanage an implementer.

## When to use this

Use this for North Stars, implementation-alignment docs, multi-repo plans,
architecture specs, and large `/goal` reference docs.

Especially use it when the plan would otherwise begin with:

- schema fields
- API endpoints
- “Service A does X, Service B does Y”
- task lists / subagent decomposition
- generic principles without concrete flow

Those can appear later. They do **not** lead.

## Mandatory preparation

Before writing the plan:

1. **Do due diligence against the real system.** Read current code/docs/logs enough
   to know the existing seams. Do not invent architecture from vibes.
2. **Name the source grounding.** The plan should say what repos/files/sessions/docs
   it was grounded in.
3. **Know the product tension.** Identify the few requirements that make the design
   necessary. Example from Local Aria: “it must feel local immediately, while still
   being a cloud-visible Aria session.”

If you have not checked the system, say so and keep researching. A story-first plan
with unverified premises is still theater.

## The shape

A good story-first North Star usually follows this order:

1. **Status / scope / source grounding**
   - What this document is and is not.
   - Which repos/files/sessions/docs were actually read.
   - Any known unverified assumptions.

2. **Product thesis / core tension**
   - One plain-language paragraph saying what the feature *is*.
   - Name the design tension that forces the architecture.

3. **Vocabulary, only as needed**
   - Define terms that the stories need.
   - Do not front-load a whole ontology before the reader has a reason to care.
   - Let the story correct misleading nouns and legacy fields. If the flow exposes
     that an old term is now compatibility-only, say so plainly instead of letting
     the old vocabulary steer the architecture.

4. **User/system stories as scenes**
   - Start from what the human does or what the system must experience.
   - The scenes must eventually hit every required work surface; if a service,
     schema, endpoint, or state field appears later, some scene should have forced
     it.
   - Each scene should contain:
     - the action/event
     - why the existing system cannot simply do the old thing
     - what new concept/state/endpoint/behavior is forced, or what old concept is
       deliberately reused/rejected
     - pseudocode or behavior sketch
     - invariants / failure behavior

5. **Natural implications per service**
   - After the stories, summarize what each service owns.
   - Now it is okay to list work surfaces, files, endpoints, schemas, contracts.
   - The reader should already understand why each one exists — or why an obvious
     alternative does **not** exist.

6. **Execution checkpoints / acceptance contract**
   - If this will drive autonomous implementation, state what is actually testable.
   - Checkpoints are review boundaries, not fake product completion.
   - Define end-to-end acceptance in user-visible terms.

## Scene template

Use this pattern repeatedly:

~~~md
# User story N: <human/system event>

<Plain-language flow. Start with the user action or concrete event.>

This forces <requirement/tension> because <reason>.

## Consequence / reuse / non-consequence: <system piece or rejected alternative>

<Explain why this field/endpoint/service exists, why an existing path is reused,
or why an obvious alternative should not exist. Do not just name it.>

```ts
behaviorLevelPseudocode(input):
  if oldPathStillApplies:
    useExistingPath()
    return

  newRequirement = deriveFromStory(input)
  preserveInvariant(newRequirement)
```

Invariants:
- <what must never break>
- <what happens on failure/offline/unauthorized cases>
~~~

The key phrases are: **“This is why X exists,”** **“This is why we reuse Y,”**
and **“This is why Z does not exist.”** If you cannot write one of those sentences
for a schema/endpoint/component/rejected alternative, it probably does not belong
in the plan yet.

## Pseudocode altitude rules

Good pseudocode:

```ts
onRemoteMessage(session, message):
  if session.executionMode === "local":
    enqueueForOwningHost(session.hostId, message)
    return

  wakeCloudWorker(session.backend)
```

Why good:

- names the decision point
- shows ownership and data flow
- reveals the seam an implementer must find
- does not prescribe exact classes, imports, retries, or storage calls

Too vague:

```txt
Handle local sessions correctly.
```

Too low-level / implementer-hostile:

```ts
// A full function body with exact imports, Firestore collection paths,
// serialization details, and line-by-line implementation choices.
```

Schemas are allowed, but only as **sketches** after the story forces them:

```ts
// Sketch, not final code:
execution_mode: "cloud" | "local"
local_host_id: string | null
local_paused_reason: "host_offline" | "sync_rejected" | null
```

## Anti-patterns

Do not write plans that begin like this:

```md
# New schemas
# New endpoints
# Gateway changes
# Aria Chat changes
```

That makes the reader ask: “Why do these exist? When are they used? What user
moment forced them?”

Other failures:

- **Schema soup** — fields appear before the user flow that requires them.
- **Service inventory** — every service gets a section, but no lived end-to-end path
  ties them together.
- **Wall of prose** — readable but not actionable; no pseudocode, invariants, or
  ownership seams.
- **Wall of code** — so specific it pre-decides implementation and removes the
  depth engineer’s judgment.
- **Task decomposition first** — “Subagent A builds schema, B builds broker” before
  proving those pieces form an end-to-end feature.
- **Fake deferrals** — marking essential integration as “future work” when the user
  asked for the complete product path.
- **Unverified grounding** — citing current architecture without reading it.

## Service implication section

Only after the stories, write something like:

~~~md
# What this naturally implies per service

## Gateway

Gateway owns <trust boundary / routing decision> because Story 3 and Story 6 need
<reason>.

Work surfaces:
- `path/to/existing-file.ts` — existing seam to extend
- `path/to/new-module.ts` — new owner if no existing seam fits

Behaviors:
```ts
createThing(...)
mirrorThing(...)
dispatchThing(...)
```

Invariants:
- <contract with other services>
~~~

Each service section must tie back to the stories. If it cannot, it is probably
premature architecture.

## Acceptance contract guidance

A story-first plan is often a **North Star**, not automatically an autonomous
execution contract. For actual `/goal` text, pair this skill with `writing-goals`;
this skill shapes the reference/North Star, while `writing-goals` handles bounded,
statically auditable goal phrasing and blocker exits.

Before handing the plan to a `/goal` loop or Mission Control, add:

- the full end-to-end user-testable outcome
- checkpoint list with behavior-level acceptance for each checkpoint
- required tests/verification evidence
- explicit non-goals or V1 simplifications
- rollback / pause behavior if relevant

For large vertical slices, do not treat intermediate infrastructure as shippable.
Schemas compiling or broker routes existing are not completion unless the user can
exercise the promised story.

## Final self-check before handing over

Ask:

1. Does the plan start with a lived user/system flow rather than data shapes?
2. Does every later schema/endpoint/service/work surface appear because a scene
   forced it?
3. For every schema/endpoint/component/rejected alternative, did I explain “this
   exists because…”, “we reuse this because…”, or “this does not exist because…”?
4. Did the stories correct misleading vocabulary instead of inheriting old nouns?
5. Is the pseudocode concrete enough to reveal implementation seams?
6. Is the pseudocode high-level enough to preserve implementer judgment?
7. Did I ground the plan in the actual current code/docs?
8. Did I name invariants and failure behavior, not just happy paths?
9. If this drives autonomous work, is the acceptance contract user-testable?

If any answer is no, revise before presenting it as a North Star.
