---
name: blast-radius
description: Find what a change could break outside its diff, and prove the one fact it is safe because of by running real code.
disable-model-invocation: true
license: Complete terms in LICENSE.txt
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

# Blast radius

Find what a change breaks somewhere else, before it ships. Listing the
callers is not the job; grep does that in a second. The job is the breakage
grep will not show.

## The proof ladder

A writeup that sounds right reads as convincing whether or not it is true.
So the deliverable is not the writeup: it is the one or two facts the
change's safety rests on, each taken as far down this ladder as is cheap,
with the rung it stopped on named.

1. **Said so.** Worthless on its own.
2. **Pointed at the line.** A real `file:line`, or the library's own source.
3. **Walked the bad case.** Followed the failure step by step and showed it
   does not reach.
4. **Ran it.** A script or test that calls the real code and fails loud if
   the fact is wrong.
5. **Reproduced it** in the running app.

Rung 4 is usually one small script that imports the same library the app
ships and calls the exact function in question.

## Steps

1. **Read the change.** The diff, the symbols it adds, changes and deletes,
   and what it now does differently, including what the diff does not spell
   out. Read the PR and the commits that last touched these lines
   (`git log -L`, `git blame`) for why they were shaped that way.
2. **Find the one fact.** Most changes that look risky are safe because of a
   single fact, such as "this call only drops cache entries that are already
   dead". Find it. When it holds, most risky cases clear at once. Spend the
   time here, not on a long list of maybes.
3. **Look where grep stops.** The source of the library you call, at its
   pinned version and with any local patch. When things run: microtasks,
   unmount and teardown, the framework's lifecycle. What a symbol search
   misses: JSON an API returns, a database column, a wire format, another
   language reading the same bytes, a feature flag, code three hops
   downstream.
4. **Weigh each risk.** Give it a real chance of happening and a real cost if
   it does. Every claim cites a real `file:line`; a search that finds nothing
   is an answer too. Done when every risk is either confirmed or cleared with
   its reason.
5. **Prove the one fact.** Write the script or test, run it, and keep its
   output. Done when the fact reached rung 4 or 5, or is marked unproven with
   what blocked it.

## Hand back

- **What it does.** What changed, including the part that is not obvious.
- **The one fact.** Stated, with its rung and the proof. Unproven if it did
  not get past rung 3.
- **Risks.** Each: how it breaks, the `file:line`, how likely and how bad,
  and how to check.
- **Cleared.** What you checked and why it is fine.
- **Before you merge.** The cheapest test or repro that would catch the real
  bug, including the script you wrote.
