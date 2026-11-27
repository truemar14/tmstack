---
name: panel-review
description: Review a document or plan with fresh reviewers on two different models, check their findings against the source, and revise. Use when the user asks for a second opinion, a panel or council review, a two-model review, or a review on several models; or to score candidates against fixed criteria.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
  requires: "a way to start a fresh reviewer on a chosen model: subagents with a model setting, or separate threads"
---

# Panel review

A **panel** is two or more fresh reviewers, each on a different model, each
given the same brief and none of the conversation that wrote the document.
Two models disagree in useful places: one catches what the other reads past.
This skill is for documents, plans, reports and designs. A pull request goes
through review-loop instead.

A **finding** is a claim that something in the document is wrong, missing or
unsupported, with the passage it is about. A finding is **real** only once
you have checked it against the source the document relies on (the code, the
data, the record), not against the reviewer's say-so.

## 1. Brief

Write one brief, the same for every reviewer:

- The document, whole, or its path or link and how to read it.
- Its goal in one line, and who reads it.
- What counts as a real finding here: a wrong fact, a missing case, a step
  that would fail, a claim with no evidence. Wording taste is not one, unless
  the user asked for it.
- The sources a reviewer may read to check a claim, and that it changes
  nothing.
- The answer's shape: one line per finding, with the passage, why it is
  wrong, and the evidence. Then one line per passage the reviewer checked
  and found sound, so a finding from another reviewer can be disputed.

Leave out the conversation, your own view of the document and what an earlier
reviewer said: a reviewer handed a conclusion tends to return it confirmed.
Done when the brief would let a stranger review the document cold.

## 2. Reviewers

Start one fresh reviewer per model, two different models unless the user names
others or more. Use the models the user's instructions name for this; with
none named, two from different families or sizes. In Claude Code, a subagent
each, with its model set. In a project with threads, one thread each, through
whoever starts threads there. Send them at the same time, so neither waits on
the other. Done when every reviewer has returned, or one has failed twice and
you say so in the report.

## 3. Check

Take each finding to the source and give it a verdict:

- **Real**: the source shows the document is wrong or missing something.
- **False**: the source shows the document is right. Keep the reason.
- **Unclear**: the source cannot settle it. It goes to the user.

Done when every finding has a verdict with its evidence.

## 4. Merge

Sort the real and unclear findings into three groups:

- **Agreed**: raised by more than one reviewer, and disputed by none.
- **Disputed**: another reviewer found the same passage sound, or asked for
  the opposite change to it. Give each side in one line and your verdict from
  the source.
- **One reviewer only**: raised by one, and disputed by none.

A finding raised by one reviewer is not weaker for it: the check decides, not
the count. Done when each real or unclear finding sits in one group.

## 5. Revise

When the document is your own, or the user asked for a revision, fix it for
each real finding. Otherwise, such as a second opinion on the user's own
document, list the fixes in the report and change nothing. Leave unclear
findings as questions for the user. Run another round, with the same brief on the revised document and fresh reviewers, only
when a fix changed a claim, a number or a recommendation; a wording fix does
not need one. Stop after three rounds and report what is still open. Done
when no fix is left unreviewed that changed a claim.

## Scores mode

When the user wants candidates ranked (names, logos, designs, options), each
reviewer scores every candidate on fixed criteria instead of listing
findings. Steps 1 and 2 apply, with these changes; steps 3 to 5 do not:

- The brief names the candidates, the criteria, the scale and what each end
  means, and the user's fixed picks and taste first, since a criterion can
  work against them. It asks for one score per candidate and criterion with a
  one-line reason, in place of findings.
- Each reviewer scores alone. Average the scores per candidate and criterion,
  and show where reviewers differ by more than a quarter of the scale.
- Rank by the mean of a candidate's criterion averages, unless the user
  weighted the criteria; then use their weights.
- Reviewers grade relative to what they see, so when new candidates join,
  score the current leader again beside them.

Done when the table holds every candidate's average and the spread.

## Report

Lead with what changed in the document, or the ranking in scores mode. Then
the three groups, one line per finding with its verdict. Then the false
findings, one line each with the reason. Name the models only where the
user's instructions name them.
