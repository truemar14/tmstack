---
name: file-pr
description: File a concise pull request. Use when the user asks to file, open, or create a PR.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

# File PR

Filing stops at the first step whose done condition is out of reach. Report
the blocker to the user with its output.

The `gh` commands below need a signed-in `gh`. Where it is not signed in and
the harness has GitHub tools, take the same step through those.

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
   CLI output, gets screenshots, and a flow gets a short recording as a GIF.
   Capture, commit and link them as [Screenshots](#screenshots) describes.
   Done: the image commit is on the branch and the drafted description links
   every image at its SHA, the description says the media is pending and
   why, or the change has nothing visible to show.
7. **Title and description.** Written by the rules below, then call the
   Skill tool with `unslop` and apply it to both. Done: both pass its rules.
8. **Create or update.** Push with `git push -u origin HEAD`, adding
   `--force-with-lease` when the branch was pushed before the rebase. New PR:
   `gh pr create --base <base> --title <title> --body-file <file>` without
   `--draft`, so review automation runs. Existing PR: `gh pr edit --title
   <title> --body-file <file>`. Write the body file in the harness's scratch
   or temp directory, never inside the repo; a multi-line `--body` argument
   breaks on PowerShell quoting. Done:
   `gh pr view` shows the PR open against the right base with the new title
   and body, and every image from step 6 passes the
   [Screenshots](#screenshots) check.
9. **Report** the PR URL to the user.

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

Place the `## Screenshots` section from step 6 right after the solution,
where the reader wants proof. A block the repo requires at the top of every
PR body, such as an attribution marker, stays first.

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

When the merge is a one-way door, hard to walk back once it lands (a
migration, a removed API, data written in a new format), say so in one line
with what it reaches beyond the diff.

End the description with a short blurb naming the model and harness that made
the changes. When the harness gives its own attribution line for pull
requests, that line is the blurb.

## Screenshots

**Capture.** Run the app on the branch, already running or started with the
harness's `run` skill or browser tools; with neither, ask the user for the
files. Sign in as a test account with made-up data, so no real person's data
lands in the PR; when there is none, ask the user for one. A changed screen
gets a before (base branch) and an after. When layout matters, capture each
at phone width (390px) and desktop width (1440px). Save a PNG per screenshot
and a GIF per recording in the harness's scratch or temp directory.

**Host on GitHub.** The images live in the repo itself, in a commit that the
next commit undoes, so the merged tree carries none of them. This works in a
private repo, where only people with access see them; a third-party image
host would publish a private app's screens.

1. Copy the files to `.github/pr-images/<name>.<ext>` on the PR branch and
   commit them. Note the commit's full SHA.
2. `git rm` those files in the next commit. Push nothing here; step 8's
   push sends both commits.
3. Link each image at that SHA, 400 pixels wide so a pair fits side by side:

   ```markdown
   ## Screenshots

   | Before | After |
   |---|---|
   | <img src="https://github.com/<owner>/<repo>/blob/<SHA>/.github/pr-images/before.png?raw=true" width="400" alt="Before: <what it shows>"> | <img src="https://github.com/<owner>/<repo>/blob/<SHA>/.github/pr-images/after.png?raw=true" width="400" alt="After: <what it shows>"> |
   ```

**After a rebase**, in step 3 of a later run or in another skill, the image
commit has a new SHA. Before the next push, find it with
`git log --diff-filter=A --format=%H -1 -- .github/pr-images/` and relink
the body to it. Add a new pair of commits only when the screenshots
themselves change.

**Check**, once the PR exists:
`gh api "repos/<owner>/<repo>/contents/.github/pr-images/<name>.<ext>?ref=<SHA>"`
succeeds for every image, and when the harness has browser tools, the PR page
shows each one. A broken image gets fixed before step 9.
