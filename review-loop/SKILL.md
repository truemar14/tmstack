---
name: review-loop
description: Review a pull request with fresh eyes until a round comes back clean, then merge if asked. Use when the user asks to review and merge a PR, to review every open PR and merge what is ready, or for a second review pass.
metadata:
  harness: [claude, codex]
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
- Codex: a new `codex exec` run with the same brief.
- When the user names a reviewer (another harness, another model), use that
  one.

If none of these is available, say so, then review the diff alone without
reopening the work's history.

## 1. Scope

One PR, or with "all open PRs", every open non-draft PR in the repo. For a
batch, order the PRs so a PR comes after the PR its branch is based on, and
work them one at a time in that order. Done when the list and its order are
written down.

## 2. Round

1. Send the current head to a fresh reviewer. Ask for findings that would
   block a merge: correctness, a broken contract, a missing test for changed
   behaviour, a regression in code the diff touches.
2. Verify each finding against the source. Fix the real ones and reply on the
   PR to the false ones with the reason.
3. Push, then check CI on the new head.

A round is **clean** when a fresh reviewer, looking at the current head,
returns no real findings and CI is green. A round that needed fixes is never
clean, because the fixes themselves are unreviewed. Repeat rounds until one is
clean. Done when the latest round on the current head is clean.

## 3. Merge

Merge only when the user asked for a merge in this task; otherwise report the
PR as ready, with the number of rounds it took.

- Use the repo's merge method: the one recent merged PRs used.
- A stacked PR whose base just merged needs its base updated. On a branch you
  created, rebase and force-push with `--force-with-lease`, and say so in your
  reply before you push. On someone else's branch, merge the new base in
  instead.
- After the merge, run the post-merge step the user's instructions name for
  this project, such as redeploying a dev environment, and check it took.

Done when every PR in scope is merged, or reported ready, or reported blocked
with the finding that blocks it.

## Report

One line per PR: merged, ready, or blocked, and the round count. For a blocked
PR, the open finding in one sentence. CI and review bots after the merge
belong to the `babysit-pr` skill.
