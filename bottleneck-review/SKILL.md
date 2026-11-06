---
name: bottleneck-review
description: Find where agentic development got stuck and which processes are easy to automate, measured from the project's own record. Use when asked for a bottleneck, friction or automation review, what slows the work down, or a recurring process retro.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
  requires: "GitHub access for CI runs and PRs; a subagent tool for the two reviews"
---

# Bottleneck review

A **bottleneck** is a place where work waits: on the user, on a budget, on a
manual step an agent repeats, on a rule that makes one PR wait for another.
This review measures each one from the record, ranks them by what they cost,
and names the smallest fix. It is **report only**: the run's outputs are the
report, the reply and the saved baseline. Building a fix is a new task the
user starts by picking it.

Every claim carries **evidence**: a number, a date, a link, a quote. A claim
without one is a guess, and the report says so where it keeps one.

## 1. Window and baseline

Read the **baseline**: the previous report's link and headline numbers, kept
in project memory. With no memory, it sits at the end of the previous report:
look where the user's instructions say documents go, or else among the user's
published artifacts for the latest one titled "Bottleneck review". The
window runs from that report's date to today, or the last 14 days when there
is none. Read the previous report in full. Its fixes are numbered; the user
picks by commenting on one or by saying so in chat. Collect those picks and
what was built since.

Done when you have the window's two dates, and either the previous report with
its picks (possibly none) or a note that this is the first run.

## 2. Gather

Read every source below for the window. A source the project does not have
gets "none" in the report's "How this was measured"; a source you cannot
reach gets the reason, and its rows stay out.

- **Conversations** where the work happened: project chat, threads, PR
  comments. Count the times the user asked what is left or where things
  stand. For each thread blocked on the user, note since when and on what.
  Note approval cards and prompts that sat unanswered, with how long.
- **The decision queue**, wherever open picks are listed: each item's age,
  and whether it is a real decision or a chore an agent could do.
- **CI**: every workflow run in the window, with runner minutes per job and
  per event (pull request, push to the main branch, re-run). Give the pace
  against the monthly budget when the instructions name one. When billing is
  not readable, give minutes and say where the user reads the money.
- **PRs**: open to merge time, split into those that merge on green checks
  and those that wait for the user's word. Open PRs and their age.
- **Git history** of the main branch and the commits of every PR merged in
  the window, since a squash merge keeps branch commits off main: commits
  that repeat a manual step (screenshot commits, merges of main into
  branches, release pushes), and the shared files that change most often.
- **Scheduled runs**: their prompts, recent results, and any rule copied into
  several prompts that should live in the repo once.
- **Releases**: failed, held or late releases, and how they were noticed.

Done when every source has its numbers in your notes, or a line saying "none"
or why it could not be read.

## 3. What got better

For each picked fix, check that it is live (a merged PR, a running job, a
changed file) and measure the change against the baseline's number. A fix
that is merged but shows no change is a finding, not a success. With no
picks, re-measure the previous report's top three bottlenecks instead. On a
first run there is nothing to compare: write "First run" in this section.

Done when every picked fix, or each of those three rows, has a status (live
and measured, live and not yet measurable, not done, or better or worse by a
number) with its evidence, or the section says "First run".

## 4. Rank

Write two tables, numbering every fix across both so the user can pick by
number.

1. **Where work got stuck.** One row per bottleneck: what it is, the
   evidence, what it costs (user minutes or days waited, agent hours, runner
   minutes), the smallest fix. Rank by the user's time first, then by agent
   time and budget. Merge rows that share one cause.
2. **Easy to automate.** One row per process that repeats: what happens by
   hand today, what it becomes, the effort, and who must approve it. When the
   user's instructions name a merge gate, say whether the fix falls under it;
   otherwise mark each fix "needs the user's pick". Rank by value for effort.
   Close the table with one line on what is not worth automating and why,
   such as decisions only the user can make.

Then a **recommended order**: up to three fixes to do first, split by whether
they need the user's word.

Done when every row carries evidence from step 2, every fix is small enough
to be one PR or one prompt change, and the recommended order names up to
three fixes.

## 5. Two fresh reviews

Send the draft to two fresh reviewers, as `review-loop` defines them, in
parallel, on two different models when the harness offers more than one, at
high effort. Each brief holds the draft, the sources from step 2 with how to
reach them, and the merge gate if there is one, and says read only: report
findings, change nothing. Ask each to:

- recheck every number against its source;
- find a bottleneck the draft missed, or one ranked too high or too low;
- challenge each fix: too big, unsafe, or solving the wrong cause.

Verify each finding against the source yourself. Fix the draft for the real
ones. Where the two reviewers disagree with each other or with the draft and
the source does not settle it, keep both views in a "Where the reviews
disagree" section for the user to pick.

Done when every reviewer finding is fixed in the draft, rejected with a
reason, or listed as a disagreement.

## 6. Publish and report

Sections, in order: Summary (three bullets and the recommended order), What
got better, Where work got stuck, Easy to automate, Recommended order, Where
the reviews disagree, How this was measured (the sources, and each review's
verdict with what it changed). Title it "Bottleneck review" and the date.
Call the Skill tool with `unslop` on the report. Publish it where the user's
instructions say documents go, as a document the user can comment on; with no
such place, call the Skill tool with `html-communication`.

Then reply to the user in a few lines: the top bottleneck with its number,
the recommended fixes by number with which need their word, and the link.
Save the new baseline where step 1 reads it.

Done when the report is published, the reply is sent, and the baseline is
saved.
