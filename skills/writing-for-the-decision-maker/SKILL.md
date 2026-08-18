---
name: writing-for-the-decision-maker
description: Write reports, findings, plans, and status updates for a person
  who makes the decision but did not do the work. Use when you report work to
  Ben, when you explain a system that he gave to agents, when many agents
  report to one person, or when he says "I lost the plot", "catch me up",
  "explain this simply", "give me tables", "story first", or "STE". Do not use
  for product text, user interface text, release notes, commit messages, code
  comments, or messages to other agents.
---

# Writing for the Decision Maker

Write all reports in ASD-STE100. Do not write "near STE" or "STE adjacent".
Those words let you keep your usual style.

## The problem

You know all of the details. The reader knows some of the details. You write
as if the reader knows all of the details. The reader must then read all of
your text to find one fact.

Two conditions make the problem larger:

- The reader gave the work to agents many days ago. The reader forgot the
  details.
- Many agents report to the same person at the same time.

Use these two rules from `first-principles-prompt-engineering`:

> **UNDERSTANDING THE TASK IS NOT THE SAME AS RENDERING THE ANSWER.**

> **Availability in context is not the same as salience to the recipient.**

Those rules tell you what to do. This skill tells you how to write it.

## How this skill agrees with Directive 0

`DEPLOYED-INSTRUCTIONS.md` Directive 0 says "Do not optimize for shortness."
That instruction and this skill agree. Read them together in this way:

- Keep every step of the cause. Do not delete a step to make the text short.
- Do not put two steps in one long sentence. Write two short sentences.
- Add sentences to make the text clear. Do not add clauses.

Directive 0 controls the content. This skill controls the sentences.

If you must choose, keep the fact and write one more sentence.

## Rule 1. Write for a reader who returns to the topic

The reader last read about this topic many days ago. The reader read about
other topics after that.

Do these things:

- Give the meaning of each special word before you use the word.
- Give the sequence of causes before you give the new facts.
- Tell the reader what changed since the last report.
- Repeat context in one sentence when the reader needs it.

Do not do these things:

- Do not assume that the reader saw your tool output.
- Do not assume that the reader remembers an earlier message in this thread.

You can read all of the earlier text. The reader cannot.

## Rule 2. Sentences show cause. Tables show lists.

Write a sentence when:

- one thing causes a different thing
- you give a reason
- you correct an error

Write a table when many items have the same fields. Examples: measurements,
faults, choices, status, the condition before a change and after a change.

Do not put all of the report in a table. A table cannot show cause. If you
put a cause in a table, the reader must build the explanation again. That is
the same problem as a wall of text.

Write one sentence that holds the most important fact. Tell the reader which
sentence it is.

## Rule 3. Make the sentences simple. Keep all of the facts.

The reader is an engineer. The reader has little time. The reader is not a
beginner.

Keep these:

- the numbers that you measured
- the calculations
- the note that tells if a fact is verified or not verified
- the names of the parts
- your errors

Change these:

- Write one idea in one sentence.
- Write in the active voice.
- Use the same word for the same thing each time.
- Use a number in place of an adjective.

Use this test. Remove a fact. Can the reader still disagree with you? If the
reader cannot, put the fact back.

## Rule 4. Give the decision to the reader

The report must let the reader decide. The reader must not need to ask a
second question.

Include these four items:

- The errors that you made. Write them before the reader finds them.
- The facts that you did not verify.
- The result that the work does not give.
- The items that wait for the reader's decision.

The reader gave the work to you. The reader can only check your work if you
show these four items.

## Rule 5. Tell the reader which parts to skip

Length is part of the problem. Count the parts of the report. If 3 parts of
10 hold the decision, name those 3 parts. Put the supporting facts in
separate parts.

## Rule 6. Do not use this skill as a form

Some reports need three sentences. Some questions need one number.

- Do not start with a template.
- Do not make a table with two rows.
- Do not write 10 parts for a small result.

If one paragraph gives the reader the decision, write one paragraph.

## Discord

Discord does not show markdown tables. Use bold headings with lists. You can
also use a code block. Do not change the other rules.

## Language limits

Do not use these:

- metaphors
- idioms
- a word with more than one meaning
- more than three nouns together
- a long sentence with many clauses

Sentence length: maximum 20 words for an instruction. Maximum 25 words for a
description.

Paragraph length: maximum 6 sentences.
