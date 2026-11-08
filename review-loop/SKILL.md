---
name: review-loop
description: Review a pull request with fresh eyes until a round comes back clean, then merge when asked or when the repo's merge gate allows, and confirm the merge is live. Use when the user asks to review and merge a PR, to review every open PR and merge what is ready, or for a second review pass.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

# Review loop

A review by the agent that wrote the change sees what it meant to write, not
what it wrote. Every round here goes to a **fresh reviewer**: one that has the
diff and the PR's goal, and none of the conversation that produced it.

- Claude Code: a subagent through the Agent tool, given the PR number or the
  diff range, the goal in one line, and the repo's own review rules
  (`CLAUDE.md`, `REVIEW.md`, `CONTRIBUTING.md`) when they exist.
- When the user names a reviewer (another harness, another model), use that
  one.

If none of these is available, say so, then review the diff alone without
reopening the work's history.

## 1. Scope

One PR, or with "all open PRs", every open non-draft PR in the repo. For a
batch, order the PRs so a PR comes after the PR its branch is based on, and
work them one at a time in that order. A PR the user did not author gets
reviewed, but its fixes are pushed only when the user says so for that PR;
otherwise its findings go in the report. Done when the list and its order are
written down.

## 2. Round

1. Send the current head to a fresh reviewer. Ask for findings that would
   block a merge: correctness, a broken contract, a missing test for changed
   behaviour, a regression in code the diff touches.
2. Verify each finding against the source. Fix the real ones; the false ones
   go in the report with the reason, since the reviewer's findings never
   appear on the PR.
3. Push, then check CI on the new head, and work any new review-bot or human
   comments: check each against the source, fix the real ones, reply with
   the reason to the rest, and keep the PR to its original goal.

A round is **clean** when a fresh reviewer, looking at the current head,
returns no real findings, CI is green, and every review thread on the PR is
addressed. A round that needed fixes is never clean,
because the fixes themselves are unreviewed. Repeat rounds until one is clean.
After three rounds in a row that each needed fixes, stop and report the PR as
blocked with the findings that keep coming back. Done when the latest round
on the current head is clean, or the PR is reported blocked.

## 3. Merge

A PR merges on a clean round when the user asked for a merge in this task, or
when the repo's **merge gate** lets it merge on green. The gate is in the
repo's `AGENTS.md` or the user's instructions: what may merge on green, and
what waits for the owner's word. A PR the gate holds merges only when the
user asks in this task to merge that PR by name; a batch ask merges only what
the gate allows. A held PR without that ask is reported ready, with what it
waits for; section 4 covers its owner check. With no ask and no gate, report
it ready, with the number of rounds it took.

- Use the repo's merge method: the one recent merged PRs used.
- A stacked PR whose base just merged is retargeted with `gh pr edit --base
  <new base>` if GitHub did not, then brought up to date with the new base,
  merged in or rebased by the condition in file-pr's step 3. On someone
  else's branch, always merge. To rebase a branch you created, `git rebase
  --onto origin/<new base> <old base tip>` (a plain rebase replays the
  squashed commits and conflicts), then force-push with `--force-with-lease`.
  Say so in your reply before you push. After a rebase, relink any images
  the PR body takes from file-pr, as its Screenshots section says.

Done when every PR in scope is merged, or reported ready, or reported blocked
with the finding that blocks it.

## 4. Confirm it is live

Where the repo's rules or the user's instructions name a release step after a
merge, run it. Where they name a way to read the **live commit** (a header,
an endpoint, a tool), read it and check that it contains the merge, using
the commit the merge put on the base (the PR's merge commit, never the branch
head, which a squash leaves off the base): `git fetch origin <base> && git
merge-base --is-ancestor <merge commit> <live commit>`. A merge that lands
during another release goes out with the next one, so read again until it
is in or the wait runs out: the wait the rules give, or 20 minutes when they
give none. When it runs out, say the merge is not live yet, and leave the
cause to whoever can see the release, rather than guessing.

When the change touches what only the owner's own device shows, as the
repo's rules list it, hand that one check to the user the way those rules
say: once the merge is live, when a merge is not live in time, or when a PR
the gate holds is reported ready. Skip it when the PR's author already
opened the issue or card for it.

Done when each named release step has run and reported success, each merged
PR is confirmed live, reported not live in time, or the repo names no live
commit to read, and each owner check the changes need is handed over.

## Report

One line per PR: merged and live (or not live yet), ready, or blocked, and
the round count. For a blocked PR, the open finding in one sentence. Then
the false findings, one line each with the reason.
