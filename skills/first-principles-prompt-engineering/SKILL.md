---
name: first-principles-prompt-engineering
description: Review, create, and refactor persistent instructions for capable frontier models, especially CLAUDE.md, AGENTS.md, system prompts, agent policies, and long-lived prompt files. Use when a model failure tempts you to append another rule, when instructions have accumulated into a checklist, when a newer model interprets old prompt wording too strongly, or when you need to preserve model intelligence while improving how it expresses and applies that understanding.
---

# First-Principles Prompt Engineering

## Overview

Use this skill when creating or modifying persistent instructions for a capable model.

The core idea is simple:

> **Do not respond to every failure by reducing the model's freedom. Improve the abstraction under which it exercises that freedom.**

Frontier models can often generalize from a few strong principles better than from a large pile of narrow rules. When a model fails, do not automatically add another prohibition, checklist item, or special case. First determine whether the prompt teaches the wrong abstraction, contains conflicting instructions, overfits an old model's failure mode, or describes symptoms instead of the underlying problem.

Treat prompt files like software: diagnose, refactor, remove contradictions, and prefer a small coherent system over patch accumulation.

## Default Workflow

When asked to create, review, or update a persistent prompt:

1. Identify the observed failure in plain language.
2. Identify what the model already understood correctly.
3. Decide whether the failure is in reasoning, expression, prioritization, or instruction interpretation.
4. Search the existing prompt for instructions that may cause or amplify the failure.
5. Look for a deeper principle that explains several symptoms at once.
6. Prefer rewriting, generalizing, merging, or deleting instructions before adding new ones.
7. Add examples only when they clarify the principle.
8. Preserve stable high-value wording across the main instruction and any reminders.
9. Check whether the proposed fix could be followed literally in a harmful or absurd way.
10. Return the smallest coherent change that solves the actual problem.

Do not treat “add a rule” as the default action.

## Diagnose the Failure Beneath the Example

Do not overfit to the exact output that failed.

If a model writes confusing action such as:

> “Both hands out. One caught the frame. One went for the floor.”

a weak prompt patch would be:

> “Always describe hand positions clearly during wake-up scenes.”

That solves almost nothing.

A stronger diagnosis is:

> **The model understood the complete physical event internally, but omitted information the reader needed because that information was already obvious to the model.**

That same failure can appear as:

- confusing physical action;
- unexplained causal jumps;
- ambiguous references;
- jargon introduced without explanation;
- old details treated as though they are still salient;
- internal analysis dumped into dialogue;
- code or architecture explained through labels rather than visible reasoning.

Fix the general failure, not the example's costume.

## Separate Understanding From Rendering

A capable model may understand substantially more than should appear directly in its output.

Preserve that.

Do not make the model think less merely because it communicates badly.

Use this distinction:

> **UNDERSTANDING THE TASK IS NOT THE SAME AS RENDERING THE ANSWER.**

The model may internally understand:

- deep causal structure;
- emotional relationships;
- hidden dependencies;
- architectural tradeoffs;
- implications spread across a large context;
- several plausible next steps;
- the complete state of a fictional or technical system.

Good. That understanding should improve its decisions.

It does not need to be surfaced in full.

A useful general rule is:

> **Understand as much as possible. Surface only what the task needs, in a form the recipient can actually follow.**

Do not reward the model for proving that it understood something. Reward it for using that understanding to produce the right result.

## Do Not Confuse Context With Communication

A fact being available to the model does not mean it is active in the recipient's mind.

> **Availability in context is not the same as salience to the recipient.**

Before relying on earlier information, consider how it was actually presented:

- Was it emphasized or merely mentioned?
- Was it buried inside a long exchange?
- Was terminology explicitly established?
- Is it reasonable for a human reader to remember it?
- Is it shared knowledge between the relevant participants?
- Has enough time or context passed that it should be re-established?

Do not make users, readers, or collaborators reconstruct missing context merely because the model can retrieve it perfectly.

This principle applies to long conversations, codebases, technical explanations, agent workflows, fiction, and document editing.

## Preserve Intelligence; Constrain Expression

When a model is excellent at reasoning, world modeling, emotional understanding, architecture, planning, or inference, preserve those strengths.

Do not solve poor output by suppressing the underlying intelligence.

Examples:

If the model understands ten implications of a design decision:

Bad fix:

> “Do not think about so many implications.”

Better fix:

> “Use the full analysis internally, then surface only the implications that materially affect the current decision.”

If the model understands a fictional character's psychology deeply:

Bad fix:

> “Keep the character psychology simple.”

Better fix:

> “Use that understanding to choose behavior. Do not make the character recite the analysis.”

The same distinction generalizes well beyond writing.

## Prefer Principles Over Microinstructions

A persistent prompt should not become a graveyard of every mistake the model has ever made.

Avoid unbounded accumulation such as:

- never do X;
- also avoid Y;
- check Z;
- in situation A, remember B;
- except when C;
- before output, verify D;
- for one special class of cases, inspect E.

Each rule may sound reasonable in isolation while the whole prompt becomes less useful.

Large microinstruction lists create four common problems.

### Attention dilution

Important principles compete with dozens of minor rules.

### Literal compliance

The model obeys the wording instead of the intent.

For example:

> “Use only two or three beats per response.”

can produce artificial counting instead of coherent pacing.

### New failure modes

A narrow fix can create pathological behavior elsewhere.

For example:

> “Always establish every body's starting position before movement.”

can turn ordinary prose into positional bookkeeping.

### Contradictory attractors

An old instruction may pull strongly against a newer correction.

For example:

> “Write lean, muscular prose.”

may conflict with:

> “Use more words whenever clarity requires them.”

When this happens, remove or rewrite the old attractor instead of surrounding it with exceptions.

## Search for Conflicting Attractors

When a capable model repeatedly violates an instruction despite being explicitly told not to, inspect the rest of the prompt.

Strong descriptive words can become behavioral attractors:

- concise;
- terse;
- muscular;
- cinematic;
- rigorous;
- sophisticated;
- exhaustive;
- comprehensive;
- expert;
- formal.

None is inherently bad.

The problem is that a newer or more capable model may interpret an old phrase more aggressively than the model for which it was written.

Example:

> “Cinematic, lean, muscular prose”

may once have successfully prevented purple prose.

A later model may interpret it as:

> fragment aggressively, omit connective language, and write like a shot list.

Do not add five warnings against fragmentary prose while preserving the instruction that keeps causing it.

Rewrite the source instruction to state the actual goal.

Persistent prompts should evolve with model behavior.

## Describe Successful Output, Not a Compliance Ritual

Prefer instructions that define the desired result.

Use:

> “The reader should be able to follow the physical sequence without guessing.”

rather than:

> “Before output, identify every actor, initial body position, movement cause, final body position, and action order.”

Use:

> “Keep the response focused enough that important ideas have room to land.”

rather than:

> “Use exactly three beats.”

Unless the task genuinely requires a procedural workflow, avoid turning quality guidance into a preflight checklist.

Tell a capable model what successful output looks like and let it exercise judgment.

## Use Examples to Teach Principles

Examples are useful because they make an abstraction concrete.

They should illustrate the rule, not become the rule.

Bad:

> Never write “Both hands out. One caught the frame.”

Better:

> Clipped fragments are not automatically clear. “Both hands out. One caught the frame...” uses plain words but still makes the reader reconstruct the action. Keep connected actions together when that makes the event easier to understand.

The model should learn why the example failed.

Otherwise it may avoid the exact wording while reproducing the same failure elsewhere.

## Use Stable Anchors Across Prompt Layers

When an important principle appears in both a full instruction and a high-priority reminder, preserve a **stable, distinctive anchor verbatim**.

Do not assume the reminder should always paraphrase the source more compactly. Paraphrasing can weaken retrieval by turning one strong instruction into several approximate versions of the same idea.

Prefer:

Main instruction:

> **UNDERSTANDING THE TASK IS NOT THE SAME AS RENDERING THE ANSWER.**

Reminder:

> Remember: **UNDERSTANDING THE TASK IS NOT THE SAME AS RENDERING THE ANSWER.**

Then add only the minimum local application needed.

Stable anchors can be:

- a short exact sentence;
- a distinctive heading;
- an XML tag name;
- a deliberately repeated phrase;
- a concise named principle.

For structured prompts, explicitly point back to the same section or tag when useful:

> Apply `<transparent_prose>` strictly.

> Apply `<realistic_character_dialogue>` strictly.

This is often stronger than inventing a fresh summary of those rules at every prompt layer.

The purpose of the reminder is not to restate the whole section. It is to **reactivate the same instruction reliably**.

Use paraphrase only when the new context genuinely requires a different explanation.

## Refactor Prompt Debt

Treat repeated prompt patching like technical debt.

When several instructions appear to address related failures:

1. identify what they have in common;
2. state the shared principle;
3. preserve one or two representative examples;
4. delete redundant special cases;
5. inspect nearby instructions for contradictions;
6. keep stable anchor wording where repeated reminders are useful.

A good refactor may make the prompt shorter.

The goal is not minimum token count.

The goal is:

> **the smallest coherent set of instructions that preserves the intended behavior.**

## Respect the Model's Capacity for Judgment

For sufficiently capable models, persistent instructions should primarily define:

- goals;
- boundaries;
- priorities;
- important distinctions;
- general failure principles;
- representative examples.

Do not try to precompute every future decision inside the prompt.

A useful mental model is:

> **Brief a capable collaborator; do not program a finite-state machine.**

Be precise about what matters and why.

Leave room for judgment where judgment is the point.

## Constrained Generativity

For generative tasks, distinguish useful creativity from random novelty.

A model can be coherent but inert:

> It faithfully repeats what the user already established.

A model can also be novel but arbitrary:

> It introduces surprising material with weak connection to the established situation.

The target is **constrained generativity**:

> **Generate new material that follows from what is already true.**

A model should not merely remember a premise. It should let the premise produce consequences.

If a fictional society uses magical transportation, transportation problems should arise from that system rather than defaulting to generic real-world traffic.

If a person is physically uncomfortable, that state should affect what they do rather than existing only as something they discuss.

In technical work, if an architectural constraint is established, proposed solutions should naturally reflect its consequences rather than merely mentioning the constraint again.

A strong generative contribution often creates this reaction:

> “I did not explicitly tell you that, but now that you have said it, it feels like it belongs.”

That is usually more valuable than raw surprise.

## Review Questions

When reviewing an existing persistent prompt, ask:

### What behavior is failing?

Describe it plainly.

### What did the model understand correctly?

Preserve it.

### Is this a reasoning failure or an expression failure?

Do not weaken reasoning to repair expression.

### What boundary did the model cross?

Common examples:

- internal understanding → unnecessary exposition;
- context availability → assumed recipient knowledge;
- stylistic concision → omitted connective information;
- deep analysis → jargon-heavy output;
- premise awareness → generic rather than premise-driven behavior.

### Is an existing instruction causing or amplifying the failure?

Search for conflicting attractors before adding anything.

### Can several rules be replaced by one principle?

Prefer the principle.

### Does the proposed instruction generalize?

If it only prevents the exact example that just failed, reconsider it.

### Could a capable model obey this literally and make the output worse?

If yes, describe the desired result instead of prescribing the mechanism.

### Is there already a strong anchor for this idea?

If yes, reuse it verbatim rather than inventing another nearby formulation.

## Editing Rules

When modifying an existing prompt:

- Preserve working behavior unless there is a reason to change it.
- Prefer local refactors over wholesale rewrites.
- Remove obsolete workarounds when the underlying model has changed.
- Do not silently turn stylistic preferences into hard numerical constraints.
- Do not add a permanent rule solely because one recent output was bad.
- Preserve important terminology and stable anchors unless the terminology itself is causing the problem.
- When adding a new principle, consider whether existing rules can now be deleted.
- If the prompt already expresses the correct principle but another instruction contradicts it, fix the contradiction instead of duplicating the principle more loudly.

## Output Expectations

When this skill is used to review or modify a prompt:

1. Explain the underlying failure briefly.
2. Identify conflicting or obsolete instructions when present.
3. State the smallest general principle that addresses the failure.
4. Prefer replacement or deletion over additive patching.
5. Show exact edits or produce the updated file when requested.
6. Call out any proposed rule that risks overfitting or maliciously literal compliance.
7. Keep the resulting prompt coherent enough that a capable model can reason from it.

Do not reward prompt complexity for its own sake.

## North Star

> **Do not respond to every failure by reducing the model's freedom. Improve the abstraction under which it exercises that freedom.**

A good persistent prompt does not contain an answer for every future situation.

It gives the model a coherent set of principles from which good behavior can be derived.

Preserve deep reasoning. Control what gets surfaced. Remove contradictory attractors. Use stable anchors. Refactor instead of endlessly appending.
