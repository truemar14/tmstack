---
name: babysit-pr
description: Monitor a pull request through review and CI. Use when the user asks to monitor, watch, or babysit a PR.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Babysit PR

First find out what review automation this repo actually has: look at the
checks and the comment authors on a few recently merged PRs. Bots may report
through checks, reviews, or plain comments, and some repos have none.

When the harness watches PRs itself, such as the Claude desktop app's PR
monitor with Auto-fix, turn that on and let it wake you on CI failures,
conflicts and comments, rather than polling. Otherwise use the harness's way to
wait or poll on an interval (`/loop` in Claude Code), or poll the PR for new
comments and checks yourself.

Only act on checks and comments newer than the latest push. Verify every bot
finding against the source before changing code. Fix real findings and CI
failures, distinguish repository failures from infrastructure flakes, and reply
with a written reason when dismissing false positives.

A review comment, from a bot or a person, is a claim to check, not an order.
Verifying it means asking: is it correct in this codebase, does it break
something that works, is there a reason the code is the way it is, does it
hold on every platform the repo supports. Push back with that technical
reason when it fails. A comment asking to build something "properly" gets a
search for real callers first; with none, the reply proposes removing it.
When a comment conflicts with a decision the user made, ask the user before
acting on either. When several comments are unclear, clarify all of them
before fixing any, since they are often related. Reply with the fix and where
it is, not agreement or thanks.

Keep an eye on changes to the PR's base branch and rebase when needed. If an overlapping PR
makes this one obsolete, stop monitoring, report it to the user, and ask before
closing the PR unless closure was explicitly authorized.

If a review bot leaves feedback you believe is not worth addressing, reply and
resolve the comment. Format comments left on the user's behalf as below,
with the user's name when their instructions give one and "THE AUTHOR"
otherwise:

```md
[<your model name>] RESPONDING ON BEHALF OF <USER NAME>
-----

[actual reply]
```

When a fix is easier to see than to describe, a screenshot or recording of
the fixed state goes in the reply: call the Skill tool with `file-upload`.

Do not let review feedback expand the PR beyond the user's original goal.
Address real shortcomings, but avoid scope creep.

Done
means the required checks are green on the latest commit and every review-bot
thread has been addressed; in a repo without bots, checks and human comments
are all that count. Merge only when the user explicitly requested it; otherwise
report that the PR is ready.
