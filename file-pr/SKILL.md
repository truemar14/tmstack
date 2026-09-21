---
name: file-pr
description: File a concise pull request. Use when the user asks to file, open, or create a PR.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# File PR

Filing stops at the first step whose done condition is out of reach. Report
the blocker to the user with its output.

## Steps

1. **Branch.** Work on the base branch moves to a branch named for the change
   first. Commit the work that serves the goal; unrelated edits stay out of the
   commits. Done: `git log <base>..HEAD` holds only commits for the change.
2. **Existing PR.** `gh pr list --head <branch>` says whether this branch
   already has a PR. Done: you know whether step 8 creates or updates.
3. **Rebase.** Fetch, then rebase onto the base branch, usually `main` unless
   the user's instructions name another. Resolve conflicts on the way. A stale branch conflicts and
   wastes a review round. Done: the branch replays cleanly on the base tip.
4. **Review the diff** against the base branch. Every hunk serves the goal;
   anything else comes out before filing. Done: every hunk accounted for.
5. **Verify.** Run whichever of typecheck, lint and tests focused on the
   change the repo has. Fix what the change broke; a failure outside the
   change blocks the filing. Done: every check the repo has is green on the
   rebased branch.
6. **Show it.** A change with a visible result, a UI state, a rendered page,
   CLI output, gets a screenshot, and a flow gets a short recording. Capture
   it from the app, already running or started with the harness's `run`
   skill or browser tools when it has them; otherwise ask the user for the
   file. When the `file-upload` skill and its token are present, upload with
   it and embed as it describes; otherwise keep the file locally and put its
   path in the description so the user can drop it in themselves. Done: the
   reader can see the result without checking out the branch, the description
   says the media is pending, or the change has nothing visible to show.
7. **Title and description.** Written by the rules below. Done: both pass the
   `unslop` skill's rules.
8. **Create or update.** Push with `git push -u origin HEAD`, adding
   `--force-with-lease` when the branch was pushed before the rebase. New PR:
   `gh pr create --base <base> --title <title> --body-file <file>` without
   `--draft`, so review automation runs. Existing PR: `gh pr edit --title
   <title> --body-file <file>`. Write the body file in the harness's scratch
   or temp directory, never inside the repo; a multi-line `--body` argument
   breaks on PowerShell quoting. Done:
   `gh pr view` shows the PR open against the right base with the new title
   and body.
9. **Report** the PR URL to the user. When they also asked to babysit it,
   continue with the `babysit-pr` skill.

## Title

PR titles usually become commit messages, so follow the repository's title
conventions. Look at recently merged PRs and Git history for examples. Prefer a
concise, human-readable title that explains why the change matters:

BAD
> ❌ perf(server): negotiate permessage-deflate on the websocket

GOOD
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

## Description

Open with a simple explanation of the problem based on the user's original
prompt, then briefly explain the solution. The reader wants the why and the
outcome, so an implementation inventory stays out of the opening:

BAD
> ❌ Removed implicit workspace carry-over from every "new thread" entry point (cmd+n / cmd+shift+o, sidebar v1/v2 buttons, command palette). New threads inherit only the project from context; branch, worktree, and env mode always come from the configured defaults. Deleted buildContextualThreadOptions, startNewThreadInProjectFromContext, and the v1 sidebar's seed-context machinery.

GOOD (illustrative; match the repo's usual tone, not these)
> ✅ My "new worktree" default was ignored when starting new threads on existing worktrees. Super unintuitive. Now your preferences always apply.

> ✅ Uploads over 2 GB failed silently and left a spinner forever. They now stream in chunks and show an error with a retry when they fail.

Place the screenshot or recording from step 6 right after the solution, where
the reader wants proof.

When the change is easier to see than to describe, sketch it instead of
narrating it. Pick the smallest view that makes the point, keep only the files,
calls or states the reader needs, and use the diff shape when the surrounding
structure already exists:

```diff
 src/
 ├── commands/
+│   └── explain.ts       # expands the slash command
 └── transport/
+    ├── client.ts
+    └── stream.ts
```

```diff
 submitForm
   createSession
+    expandSkillMention
     launchAgent
```

A shallow file tree explains a layout change, a call tree explains a flow
change, pseudocode explains a rule change, and GitHub renders a Mermaid
`sequenceDiagram` when three or more parties talk to each other.

End the description with a short blurb naming the model and harness that made
the changes.
