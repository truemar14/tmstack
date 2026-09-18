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
through checks, reviews, or plain comments, and some repos have none. They are
helpful when present, even if not always right.

If your harness offers a way to wait on a PR or poll on an interval, use it so
you can respond when comments arrive. Otherwise, poll the PR for new comments
and checks yourself.

Only act on checks and comments newer than the latest push. Verify every bot
finding against the source before changing code. Fix real findings and CI
failures, distinguish repository failures from infrastructure flakes, and reply
with a written reason when dismissing false positives.

Keep an eye on changes to the PR's base branch and rebase when needed. If an overlapping PR
makes this one obsolete, stop monitoring, report it to the user, and ask before
closing the PR unless closure was explicitly authorized.

If a review bot leaves feedback you believe is not worth addressing, reply and
resolve the comment. Format comments left on the user's behalf as, with
the user's name from their instructions:

```md
[MODEL-SLUG] RESPONDING ON BEHALF OF <USER NAME>
-----

[actual reply]
```

Screenshots and videos help as well. Use the `file-upload` skill when needed.

Do not let review feedback expand the PR beyond the user's original goal.
Address real shortcomings, but avoid scope creep.

If nothing has changed, stay quiet rather than posting filler comments. Done
means the required checks are green on the latest commit and every review-bot
thread has been addressed; in a repo without bots, checks and human comments
are all that count. Merge only when the user explicitly requested it; otherwise
report that the PR is ready.
