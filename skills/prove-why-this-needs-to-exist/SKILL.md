---
name: prove-why-this-needs-to-exist
description: >-
  INVOKE/LOAD when proposing, designing, implementing, or reviewing any new
  feature, field, flag, metadata property, abstraction, helper, dependency,
  service, endpoint, schema, migration, status enum, config knob, or line of
  code whose necessity is not already proven. Use when the question is "can this
  be simpler?", "why does this exist?", "is this taxonomy/wrapper/field real or
  AI architecture cosplay?", or Ben says "yo what the hell is this?".
---

# Prove Why This Needs To Exist

The burden of proof is on complexity.

Treat every proposed unit of implementation like an early NASA launch decision:
**prove why we can launch today** becomes **prove why this thing needs to exist**.
Not because delay is virtuous. Because unearned structure is a liability the
user will pay for forever.

This skill is not a request for elegant-sounding architecture. It is a brake on
AI-agent overbuilding: fields that restate each other, wrappers that wrap
nothing, flags nobody needs, categories that describe obvious facts, and
"safety/UX metadata" that never changes a real decision.

## The Gate

Before adding the thing, answer these in plain language:

1. **What is the thing?**
   Name the exact feature/field/type/helper/flag/line/abstraction being proposed.

2. **What decision or behavior does it enable?**
   If no user-visible or system-critical behavior changes because this exists,
   it probably should not exist.

3. **What is the simpler version?**
   Describe the dumb, direct implementation: one field instead of three, inline
   code instead of a helper, a string note instead of a taxonomy, no new storage,
   no new service, no new enum.

4. **Why is the simpler version insufficient?**
   This must be concrete: a real failure, ambiguity, operational need, query
   shape, migration requirement, security boundary, or maintenance burden that
   the simpler version cannot handle.

5. **What does this cost forever?**
   Every added thing creates read paths, write paths, tests, migrations,
   docs, UI states, stale-data risk, and future confusion. Say which of those
   costs apply.

If the answer is vague, aesthetic, taxonomic, or merely "for safety/UX" without
an actual decision path, do not add it.

## Fast Rejection Patterns

Delete or avoid the thing when:

- It only describes an obvious fact.
- Its value is implied by another field.
- It is mutually exclusive with another field that could simply be one field.
- It predicts a future need the current system does not have.
- It exists because the design feels more complete with a category name.
- It turns one concrete caveat into a broad taxonomy.
- It is only used by tests, not by a live path.
- It makes the reader ask: "yo, what the hell is this for?"

## Good Outcomes

The output of this skill should be one of:

- **Delete it.** The thing does not earn its existence.
- **Inline it.** The behavior is real, but the abstraction is not.
- **Collapse it.** Multiple fields/categories become one concrete field or note.
- **Rename it.** The thing is real, but its name lies about its purpose.
- **Keep it, proven.** The thing enables a necessary behavior that the simpler
  version cannot.

When keeping it, state the proof in one sentence:

> We need `<thing>` because `<specific live behavior/failure>` cannot be handled
> by `<simpler version>` without `<concrete consequence>`.

If you cannot write that sentence honestly, you have not proven it.
