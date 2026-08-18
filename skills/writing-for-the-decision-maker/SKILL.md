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

STE controls meaning. STE does not control length. The approved word list
exists so that one word has one meaning. When a longer word or a longer
phrase removes doubt, STE uses the longer one.

Do not read this skill as an instruction to write less.

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

## Directive 0 says the same thing

`DEPLOYED-INSTRUCTIONS.md` Directive 0 says "Do not optimize for shortness."
STE says do not remove words to make the text short. These are one rule.

There is no conflict between them. If you think that you found a conflict,
you have read this skill as a brevity rule. It is not one.

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
- Add a sentence when the reader needs one more step of the cause.

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

A long report is not a fault. A long report with no map is a fault.

Count the parts of the report. If 3 parts of 10 hold the decision, name
those 3 parts. Put the supporting facts in their own parts. The reader can
then read the evidence, or trust it, and the reader chooses which.

## Rule 6. Do not use this skill as a form

Some reports need three sentences. Some questions need one number.

- Do not start with a template.
- Do not make a table with two rows.
- Do not write 10 parts for a small result.

If one paragraph gives the reader the decision, write one paragraph.

## Discord

Discord does not show markdown tables. Use bold headings with lists. You can
also use a code block. Do not change the other rules.

## Language

The rule is one meaning for one word. The rule is not a word count.

Do these things:

- Give one meaning to each word. Give one word to each meaning.
- Use the same word for the same thing every time. Do not vary the word to
  make the text pleasant.
- Keep the small words: "the", "a", "that", "which".
- Keep the technical name of a part, however long the name is.
- Break a group of more than 3 nouns into a phrase. Do this even when the
  phrase is longer.

Do not use these:

- metaphors
- idioms
- a word that has more than one meaning
- a word that names an idea when a word that names a thing will do

Do not do these things:

- Do not remove a word to make the text short.
- Do not remove "that" or "which" from a sentence.
- Do not put two ideas in one sentence with many clauses.

Examples. The STE form is longer in each case.

| Usual English | STE |
|---|---|
| fuel pressure switch | the switch for the fuel pressure |
| ensure | make sure that |
| don't | do not |
| the value you set | the value that you set |

Sentence length is a warning sign, not a limit. A sentence of 40 words
usually holds two ideas. Split the ideas into two sentences. Do not cut the
words.
