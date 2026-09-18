---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any "grill" trigger phrase.
license: Complete terms in LICENSE.txt
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

Interview the user relentlessly until you reach a shared understanding. Map
this as a **design tree**: every decision branches into the decisions that hang
off it.

Work the tree in **rounds**. The **frontier** is every decision whose
prerequisites are already settled: the questions you can ask now without
guessing at answers you have not heard yet. Ask the whole frontier in one
round: number each question and give your recommended answer. Then wait for
the user's answers before the next round.

Ask in plain numbered text, never through a question-picker tool. A picker
pushes the user toward a predefined answer, and the point of a round is the
context they add in their own words. Format each question like so:

```
**Q1. <question title>**
<question body, possibly several paragraphs, including options when they help>
Recommended: <your recommended answer>
```

When voice mode is on, keep a round to four questions at most and put the
recommendations in the spoken part, so the user can answer from what they heard.

Each round the user answers reshapes the tree: settled decisions push the
frontier outward and unblock questions that depended on them. Recompute the
frontier and ask the next round. A question whose answer depends on another
question still open in this round belongs to a later round, not this one.

Finding facts is your job, never the user's. When a frontier question needs a
fact from the environment (filesystem, tools, and so on), dispatch a sub-agent
to find it; never ask the user for anything you could look up yourself. Do not
block on it: a running exploration is an unsettled prerequisite, so only the
questions downstream of it wait for the sub-agent to report; ask the rest of
the frontier now. The decisions are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design
tree visited, nothing left silently assumed. Do not act on it until the user
confirms you have reached a shared understanding.

When the plan touches a project's domain, load the `domain-modeling` skill
alongside and write terms into `CONTEXT.md` and decisions into `docs/adr/` as
each round settles them, so the interview leaves a record in the repo, not
only a shared understanding in the conversation.
