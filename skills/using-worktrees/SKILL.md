---
name: using-worktrees
description: >-
  INVOKE/LOAD BEFORE repo-changing work or before spawning repo workers,
  subagents, tmux workers, background agents, or parallel implementation agents.
  Establishes the convention that task work should happen in a git worktree under
  `.worktrees/` by default, with explicit exceptions for read-only work, already
  isolated worktrees, non-git directories, direct user overrides, and tiny global
  config edits.
---

# Using Worktrees

## Rule

For repository-changing work, create or reuse a task-specific git worktree under
the repository root's `.worktrees/` directory before editing files.

Default shape:

```bash
git worktree add .worktrees/<task-slug> -b <task-branch>
```

Use short, descriptive names. Prefer the same slug for the directory and branch
unless the repo's branch naming convention says otherwise.

## When This Applies

Use this workflow before:

- Editing code, tests, docs, config, prompts, agent instructions, or generated artifacts in a git repo.
- Spawning subagents, tmux workers, background agents, or parallel workers that may edit repo files.
- Running broad refactors, dependency upgrades, migrations, or multi-step verification that could leave local artifacts.

Each worker that edits files gets its own worktree unless the user explicitly asks several agents to collaborate in the same checkout — with one exception: sequential chunks of a single feature share one worktree (see below).

## Multi-Chunk Features Share One Worktree

The "each worker gets its own worktree" default above is correct for
*unrelated* parallel work. It is wrong for *sequential chunks of one
feature* — separate pieces of work that will land together in a single
merge to the main branch.

When one feature is decomposed into multiple chunks — handed to the same
or different workers, one after another — pick the location ONCE, before
the first chunk starts, and keep every chunk there.

The failure mode if you don't: chunk 1 lands in the primary checkout.
Chunk 2's worker, correctly following this skill, branches its own
worktree off the main branch — but the main branch does not have chunk
1's changes yet (they are still uncommitted in the primary checkout). So
chunk 2 is built on a base that is missing chunk 1. Merging chunk 2 then
lands it *without* chunk 1, and any coupling between them breaks: chunk 2
calls something chunk 1 introduced that is not on main yet. Untangling
that means an awkward, error-prone "commit chunk 1 first, then merge"
sequence that the right setup never creates.

Before the first chunk starts, ask: **will these chunks merge together
as one feature?** If yes:

- Create ONE worktree for the whole feature, up front, named for the
  feature: `.worktrees/<feature-name>/`.
- Brief every chunk — the first one included — to work in that exact
  path, on that one branch.
- Merge once, at the end.

If chunk 1 has already landed somewhere by the time you notice the
split, fix it before the next chunk starts — either commit chunk 1 and
branch the shared worktree off the new HEAD, or run every remaining
chunk in the same checkout chunk 1 used. Chunks drifting across
locations is the failure; do not let it stand and plan to "sort it out
at merge time."

## Exceptions

You may stay in the current checkout only when one of these is true:

- The task is read-only: inspection, explanation, review without edits, or command output only.
- The current directory is already a task worktree, especially under `.worktrees/`.
- The directory is not a git repository or cannot use `git worktree`.
- The user explicitly says to work in the current checkout.
- The task is a tiny edit to shared/global agent config where the user clearly wants the live config updated immediately, such as `~/.fractal-ai/DEPLOYED-INSTRUCTIONS.md`.
- Creating a worktree would be more dangerous than the edit, for example because the repo has unresolved user changes required for the task. State this before proceeding.

If you use an exception, say which exception applies.

## Before Creating A Worktree

1. Find the repository root:
   ```bash
   git rev-parse --show-toplevel
   ```
2. Check current state:
   ```bash
   git status --short
   git branch --show-current
   ```
3. If there are user changes, do not move, stash, reset, or overwrite them unless the user asks. Create the worktree from the current `HEAD` or ask if the dirty state is required.
4. Check existing worktrees:
   ```bash
   git worktree list
   ```

## Worker Instructions

The main session owns worktree orchestration. Do not assume spawned workers will
infer the convention from global instructions; create or select the worktree
first, then pass the path and branch explicitly in the worker prompt.

When briefing a repo-editing worker, include:

- The worktree path it must use.
- The branch name it owns.
- The end-to-end goal, relevant architecture context, and verification expectation.
- A reminder that other agents may be working nearby and it must not revert or overwrite unrelated changes.

Do not spawn a worker into the primary checkout for repo edits unless an exception applies.

## Finishing

Before saying the task is complete:

- Report the worktree path and branch used, or the exception used.
- Verify changes from inside the worktree that contains them.
- Leave cleanup to the user unless they explicitly ask you to remove the worktree.
