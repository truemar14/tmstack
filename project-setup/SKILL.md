---
name: project-setup
description: Set up a repo so every coding agent works by the same written rules, and so a Claude project for it needs only a short pointer. Use when starting a new project or repo, onboarding another agent (Cursor, Copilot, Codex) to an existing one, or when house rules live only in one tool's settings.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

Put the **house rules** in the repo, where every agent reads them, and keep
each tool's own settings down to a pointer plus what only that tool needs. One
rulebook means Claude, Cursor and Copilot can each pick up an issue or a branch
where another stopped.

Work on a branch and finish with a pull request. Change only the files named
here, and read each one before you change it: an existing file is extended,
never replaced.

## 1. Find what exists

Read the repo's `AGENTS.md`, `CLAUDE.md`, `.cursor/` rules,
`.github/copilot-instructions.md`, `.github/pull_request_template.md`,
`.github/workflows/`, and any `docs/` page on releases or operations. Then ask
the user where else rules live today: a Claude project's instructions, memory
notes, a tool's settings page. Ask for those rules as text.

Done when you hold every rule the user works by, each with where it lives now.

## 2. Write the files

Each meaning gets a **single source of truth**. Follow
`writing-for-agents/SKILL.md` for every file an agent reads.

1. **`AGENTS.md`**, a "Working here" section with one bullet per rule:
   - who works here: the agents by name, and that the same rules hold for each
   - claiming work: how an issue is marked taken (a label such as
     `in-progress`, or an open PR that names it)
   - branch names that say who wrote the work: `<agent>/<issue>-<few-words>`
   - CI budget: how many runs a PR may use, and which checks run locally first
   - shared files that take one PR at a time, and to merge main in, not rebase
   - the review: who reviews, with which file, before merge
   - the **merge gate**: what may merge on green checks, and what waits for
     the owner's word (money, deleting people's data, deploy machinery are the
     usual three); name the deploy machinery by path
   - the release step after a merge, and that production goes out only on the
     owner's word
   - secrets: each agent reads its own environment, checks a secret by
     presence only, and never asks for one in chat
2. **`CLAUDE.md`** holds `@AGENTS.md` and nothing else. A `.cursor/` rule or
   `.github/copilot-instructions.md`, where the user has one, becomes a
   one-line pointer to `AGENTS.md`.
3. **`REVIEW.md`**: what a fresh reviewer checks in this codebase, the rules a
   diff can break that a linter cannot see.
4. **`docs/verify.md`**: the proof an agent gives before it says done: what CI
   runs, run locally; its own diff read as a reviewer; screens for a visible
   change; what it could not check, named.
5. **`.github/pull_request_template.md`** with the sections What changed,
   Screenshots, How I verified, Not checked, Merge gate.
6. **`docs/operations.md`**, only when scheduled agent runs exist: one table
   row per run, with when and what it does.

Done when every rule from step 1 has exactly one home in these files, and
`AGENTS.md` points to each of the others.

## 3. Shrink the tool settings

Write the replacement text for each tool's own settings, for the user to
paste: a line that says to follow `AGENTS.md` and that `AGENTS.md` wins when
they differ, plus only what that one tool needs (for a Claude project: where
it posts, which cloud environment holds its secrets). Give the user the text.
Settings pages and memory are the user's to change.

Done when the user has the replacement text for every place a rule lived
outside the repo.

## 4. Hand over

Open the pull request with the repo's own PR skill (`file-pr` here). In the
reply, list the paste steps from step 3 and any label the claiming rule needs
that does not exist yet.
