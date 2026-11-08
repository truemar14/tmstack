---
name: project-setup
description: Set up a repo so every coding agent works by the same written rules, and a Claude project around it with its environment, memory and routines. Use when starting a new project or repo, bringing one project's setup to another, onboarding another agent (Cursor, Copilot, Codex) to an existing one, or when house rules live only in one tool's settings.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

Put the **house rules** in the repo, where every agent reads them, and keep
each tool's own settings down to a pointer plus what only that tool needs. One
rulebook means Claude, Cursor and Copilot can each pick up an issue or a branch
where another stopped.

Work on a branch and finish with a pull request. Change only the files named
here, and read each one before you change it. An existing file is extended,
with one exception: a tool's own rule file becomes a pointer in step 2, once
every rule in it has moved to `AGENTS.md`.

## 1. Find what exists

Read the repo's `AGENTS.md`, `CLAUDE.md`, `.cursor/` rules,
`.github/copilot-instructions.md`, `.github/pull_request_template.md`,
`.github/workflows/`, and any `docs/` page on releases or operations. Then ask
the user where else rules live today: a Claude project's instructions, memory
notes, a tool's settings page. Ask for those rules as text.

Then ask the user who owns the repo; the account it sits under does not
tell you. A **solo repo** is the user's alone. A **team repo** is shared with
other people or owned by an employer: its team's own rules, review and
release process win, step 2 writes the team form of each rule, and the
rulebook goes to the team as a proposal in step 5's PR. In a team repo, ask
too whether the employer allows its code in a cloud environment; step 4 runs
only on a yes.

Done when you hold every rule the user works by, each with where it lives
now, and you know whether the repo is solo or team.

## 2. Write the files

Each meaning gets a **single source of truth**. Call the Skill tool with
`writing-for-agents` before you write, and follow it for every file an agent
reads.

1. **`AGENTS.md`**, a "Working here" section with one bullet per rule:
   - who works here: the agents by name, and that the same rules hold for each
   - claiming work: how an issue is marked taken (a label such as
     `in-progress`, or an open PR that names it). Team form: an open PR that
     names it, so no new label
   - branch names that say who wrote the work: `<agent>/<issue>-<few-words>`
   - CI budget: how many runs a PR may use, and which checks run locally first
   - shared files that take one PR at a time, and to merge main in, not rebase
   - the review: who reviews, with which file, before merge
   - the **merge gate**: what may merge on green checks, and what waits for
     the owner's word (money, deleting people's data, deploy machinery are the
     usual three); name the deploy machinery by path. Team form: agents open
     PRs and the team merges
   - where the repo releases: the release step after a merge, how an agent
     confirms it is live (an endpoint or header that names the live commit,
     and how a cloud session reaches it), and that production goes out only
     on the owner's word. Team form: the team's release process, by pointer
   - the **owner check**, solo repo only: what only the owner's own device
     shows (an installed phone app, the camera, push, a payment form on the
     phone), checked once per change once it is live. A Claude thread that
     merged its own safe PR asks with one card once the merge is live. In
     every other case (a PR that waits for the owner's merge, an agent
     without cards, a merge not live in time) the PR's author opens an issue
     titled "Check on your phone: <what>", labelled `needs-owner`, when the
     PR is ready. "Something's off" becomes a `bug` issue with what the owner
     describes. Every other check is the agent's
   - secrets: each agent reads its own environment, checks a secret by
     presence only, and never asks for one in chat; `AGENTS.md` names each
     secret by name, never by value
2. **`CLAUDE.md`** holds `@AGENTS.md` and nothing else. A `.cursor/` rule or
   `.github/copilot-instructions.md`, where the user has one, becomes a
   one-line pointer to `AGENTS.md`. Move each rule such a file holds into
   `AGENTS.md` first, so nothing is lost when it shrinks.
3. **`REVIEW.md`**: what a fresh reviewer checks in this codebase, the rules a
   diff can break that a linter cannot see.
4. **`docs/verify.md`**: the proof an agent gives before it says done: what CI
   runs, run locally; its own diff read as a reviewer; screens for a visible
   change; what it could not check, named.
5. **`.github/pull_request_template.md`** with the sections What changed,
   Screenshots, How I verified, Not checked, Merge gate.
6. **`docs/operations.md`**, when scheduled agent runs exist or step 4 plans
   one: one table row per run, with when and what it does.

Done when every rule from step 1 has exactly one home in these files, and
`AGENTS.md` points to each of the others.

## 3. Shrink the tool settings

Write the replacement text for each tool's own settings, for the user to
paste: a line that says to follow `AGENTS.md` and that `AGENTS.md` wins when
they differ, plus only what that one tool needs (for a Claude project: where
it posts, and which cloud environment holds its secrets). Give the user the
text. Settings pages are the user's to change.

Done when the user has the replacement text for every place a rule lived
outside the repo.

## 4. Set up the Claude project

When the user works on this repo in a Claude project, read
[`CLAUDE-PROJECT.md`](CLAUDE-PROJECT.md) and follow its "Before the PR"
sections: the cloud environment, project memory, and the routines the user
wants. Skip this step for a repo worked on only from a terminal or an editor.

Done when every Done line in those sections holds.

## 5. Hand over

Call the Skill tool with `file-pr` and open the pull request with it, then
stop: the user, or in a team repo the team, merges it. In the reply, list the
paste steps from steps 3 and 4, and any label the solo rules need that does
not exist yet (the claiming label, `needs-owner`, `bug`). When step 4 ran,
also list the "After the merge" items from `CLAUDE-PROJECT.md` for the
session that picks up once the PR has merged, and state whether the repo is
solo or team and that the employer allowed cloud work, so that session has
both answers.
