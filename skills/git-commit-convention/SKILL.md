---
name: git-commit-convention
description: >-
  INVOKE/LOAD WHEN USING GIT! WHY: Prepare and create git commits using a
  standardized commit message format. Use when the user asks to commit (e.g.,
  “ok please commit our changes”) and you must stage changes intentionally, keep
  commits atomic, and format messages as [type][name] details. If invoked with
  little or no scope/context, treat the entire working tree as in-scope and
  clean it by producing multiple relevant atomic commits.
---

# Git Commit Conventions

## Objective

Create high-signal, atomic commits and finish with a clean working tree.

## Commit Message Format

- Format: `[<commit-type>][<name>] <more details>`
- One-line summary; no body, no trailers, no `Co-Authored-By`, no `Signed-off-by`.
- `<name>` is the author handle/name - `ben`.

## Commit Types

- Use the commit type conventions seen in recent history.
- Common types observed: `feat`, `fix`, `refactor`, `chore`, `misc`, `adjust`, `wip`.
- If unsure about casing or type, ask the user or mirror the most recent similar commit type.

## Operating Modes

1. Scoped mode (user provided clear scope):
   - Commit only the requested scope.
   - Leave unrelated files unstaged unless the user expands scope.
2. Low-context cleanup mode (user asked to commit, but gave little/no scope):
   - Treat all non-ignored changes in the working tree as in-scope by default.
   - Produce multiple relevant atomic commits as needed.
   - Do not stop at a partial commit unless the user explicitly says to.

## Workflow

1. Inspect the working tree:
   - `git status -sb`
   - `git diff --stat`
   - `git diff` (and `git diff --staged` if needed)
2. Partition changes into atomic groups:
   - Cluster files by concern/feature/fix, not by convenience.
   - Prefer explicit file-path staging per group.
   - If one file contains mixed concerns, split hunks with `git add -p`.
   - If hunk-level separation is impossible, keep the smallest coherent combined unit.
3. Stage intentionally for one group at a time:
   - Use explicit file paths and/or `git add -p`.
   - Avoid broad staging commands when they would blur commit boundaries.
4. Confirm staged content:
   - Review `git diff --staged`.
   - Verify staged files/hunks represent one coherent change.
5. Compose the commit message:
   - Ensure `[type][name] details` format.
   - Ask for missing/ambiguous `<name>` only when truly unknown; otherwise use `ben`.
6. Commit without trailers:
   - `git commit -m "[type][name] summary"`
7. Repeat grouping and committing until target scope is complete:
   - In scoped mode: stop when scoped files are committed.
   - In low-context cleanup mode: continue until `git status -sb` is clean (no remaining non-ignored changes).

## Safety & Discipline

- If you detect unexpected changes you did not make, stop and ask the user how to proceed.
- Never amend commits unless explicitly requested.
- Never collapse unrelated work into one commit just to clean the tree quickly.
- In low-context cleanup mode, do not leave residual unstaged changes unless blocked by a safety concern you report to the user.
