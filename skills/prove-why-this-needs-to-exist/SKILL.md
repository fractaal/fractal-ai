---
name: prove-why-this-needs-to-exist
description: >-
  INVOKE/LOAD at an architecture or product boundary when proposing or reviewing
  durable structure: a service, schema, dependency, persisted field or flag,
  endpoint, migration, config surface, lifecycle abstraction, or bespoke
  mechanism. Also use when such a thing's necessity is disputed or it may replace
  an ecosystem paved path (hand-rolled schedulers, queues, caches, retries,
  auth/crypto, parsers, packaging, or delivery). Do NOT use for ordinary coding,
  local helpers, routine refactors, or bug fixes whose requirement and architecture
  are already established; Ponytail handles minimal implementation. Trigger on
  "why does this exist?", "AI architecture cosplay", "why not do it the normal
  way?", "stop bodging", "paved path", or "pit of success".
---

# Prove Why This Needs To Exist

The burden of proof is on complexity.

Use this skill at the architecture or product boundary, when a proposal creates
something durable that future code and operators must carry. Once the requirement
and architecture are established, stop running this gate against routine code;
use Ponytail to implement it minimally.

Treat each durable proposal like an early NASA launch decision: **prove why we
can launch today** becomes **prove why this thing needs to exist**. Not because
delay is virtuous. Because unearned structure is a liability the user will pay
for forever.

This skill is not a request for elegant-sounding architecture. It is a brake on
AI-agent overbuilding: persisted fields that restate each other, durable wrappers
that wrap nothing, flags nobody needs, categories that describe obvious facts,
and "safety/UX metadata" that never changes a real decision.

## The Gate

Before adding the thing, answer these in plain language:

1. **What is the thing?**
   Name the exact service, schema, dependency, persisted field/flag, endpoint,
   migration, config surface, lifecycle abstraction, or bespoke mechanism.

2. **What decision or behavior does it enable?**
   If no user-visible or system-critical behavior changes because this exists,
   it probably should not exist.

   2b. **What is the boring, industry-standard way to do this — and why aren't
   you doing it?** If you cannot name the paved path, you have not done the
   research; go do it. If you can name it and are deviating anyway, the
   deviation is itself a thing that must pass this gate. "The bodge was faster
   today" is not proof. It is the confession.

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

## 🎸 DO NOT BE A ROCKSTAR — The Bodge Gate

Everything above polices unearned *structure*. This section polices unearned
*novelty*: the bespoke mechanism where a paved path exists. Same disease,
uglier strain — because a bodge always **works in the demo**, and that is
exactly what makes it metastasize.

Understand what you are when you bodge. You are not clever. The ecosystem
already solved this problem — packaging, versioning, building, publishing,
config, scheduling, retries — and solved it better than you will in one
session, because thousands of maintainers spent years paving that path and
every tool, every doc, and every agent's training data assumes it. When you
hand-roll a substitute, you are not engineering; you are declining engineering
that was already done for you, and billing the user for the privilege — forever.

**The demo passing proves nothing.** Every bodge in history passed its demo:

- The committed `dist/` and SHA-pinned tarball URLs that "just worked" — until
  two consumers were silently running divergent forks of the same code and a
  coworker's app crashed on a mechanism no tool on earth understood. (Ben's Pi
  extensions, July 2026 — the boring `npm publish` fix deleted every bodge at
  once and surfaced two latent runtime bugs the bodges had been hiding.)
- The `while true; sleep 60` loop standing in for cron or a systemd timer —
  until the reboot it doesn't survive, discovered a week later.
- The regex "parsing" HTML/JSON/YAML that has a real parser — until the first
  input it never imagined.
- The hand-rolled token/session/crypto scheme — until it's a security incident.
- The CSV-in-a-file standing in for a database table — until the second
  concurrent writer.
- The copy-pasted fork of a library function — until upstream fixes the bug
  you froze in time.
- The bespoke retry/backoff/queue — until it melts something downstream,
  because the boring one had jitter and yours didn't.

**You are an AI agent, which makes bodging strictly worse.** Your clever
mechanism outlives your context window. You will not be there to explain it.
The next agent inherits it as unexplained magic and either cargo-cults it or
gets destroyed by it — and their innocent, normal-looking code will *break*
against your abnormal structure, and they will not know why, because the trap
you set is invisible from inside a fresh context. Boring convention is the only
shared memory across agents that do not share memory. When you bodge, you are
defecting against every future session, including your own.

**Bodge tells — any of these means STOP and take the paved path:**

- Build artifacts committed to git, or a git SHA / tarball URL where a version
  number belongs.
- Hand-rolling what the platform or a standard dependency already provides:
  schedulers, queues, caches, retries, locks, auth, crypto, migrations,
  serialization.
- Parsing a structured format with regex or string-splitting when a real
  parser exists.
- Generating code at runtime that could have been an import.
- State encoded in filenames, comments, or sidecar files where a real store
  or schema exists.
- Shipping from a working tree that doesn't match the repo.
- A second mechanism doing what an existing mechanism already does.
- A checker, checklist, or doc paragraph whose job is to *remember what the
  structure forgot*. A guard that compensates for structure is the structure
  confessing. (Guards that defend a real platform boundary — a second
  filesystem, a trust boundary — are earned. Know the difference.)
- Any mechanism that needs a README section to survive one code review.
- The sentence "it works, we just have to remember to…" — the moment
  "remember" enters the design, the design has failed. Memory is not a
  component. Convention is.

**The standard is the pit of success:** leave the system in a state where the
laziest, most obvious next move — by you, another agent, or a coworker who has
never read your code — is also the correct move. If being correct requires
reading your mind, your session notes, or a compensating checklist, you did not
finish the job; you moved your work onto everyone who comes after you.

If Ben has to ask "yo what the hell is this?", the answer does not matter.
You already failed the review.
