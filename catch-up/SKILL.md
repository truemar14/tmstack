---
name: catch-up
description: Hand the current session back to a user who has lost the thread of it. Use when the user asks where things stand in this session, for example "where were we?" or "catch me up".
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

Write a **handoff** for this session: the note a colleague leaves at the end
of a shift, so the person picking up can act without rereading the log. The
user runs many sessions and has lost track of this one. The handoff is for
**quick re-entry**: after it, the user can say "continue". Depth comes later,
from their follow-up questions. The scope is this session only.

The whole catch-up is read only.

## 1. Recall

Walk the whole conversation from its first message, not only the recent turns.
Recall it as you hold it now: your context is the only source. Two things lead
the handoff:

- **The position.** What was started and where exactly it stopped.
- **The user's debts.** Every question or approval they still owe, oldest
  first. These scroll away mid-session and are what the last reply leaves out.

Done when you can name the exact stopping point and every debt the user still
owes.

When the session was compacted and the summary is silent on something the
handoff needs, say the handoff has a gap there. A guess presented as memory is
worse than the gap.

## 2. Check for drift

The session remembers the world as it was when the user left, and the user's
other sessions may have moved it since. **Drift** is any difference between
the two. Check only what this session touched, in one parallel pass:

- the branch, uncommitted changes and recent commits
- its pull request, if it has one: review state, CI, merge state
- anything it left running or waiting: a background task, a deploy, a reply

Keep it quick: a few cheap read only commands. Done when each item above is
either confirmed unchanged or has its change noted. Drift earns a mention in
the handoff only when there is some.

## 3. Write the handoff

The text uses this shape, in this order, short enough to take in at a glance:

```
**About.** What this session is for. One line.
**Stopped at.** Where exactly the work stopped.
**Waiting on you.** What the user owes, oldest first, or "Nothing."
**Next.** The one step you recommend taking now.
```

Finished work and past decisions appear under **Stopped at** only when they
bear on the next step. Drift joins **Stopped at**, because it changes where
things stand.

When voice mode is on, the user listens first and reads only when that was
not enough. The spoken part (the speak plugin's `Spoken:` paragraph) is then
the main output: exactly three sentences, in this order every time, so the
ear learns the pattern.

1. What the session is about and where it stopped, drift included.
2. What the user owes, or that nothing is waiting on them.
3. The next step you recommend.

When voice mode is off, the headings stand alone: the three sentences exist
only in the spoken part.

Then stop and let the user choose: the handoff ends with the recommendation,
not with the step taken.
