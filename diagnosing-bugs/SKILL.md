---
name: diagnosing-bugs
description: >-
  Diagnose a hard bug, one reported by a user or a feedback document, a
  screenshot of something broken, a failure that only happens sometimes, or a
  performance regression. Use when the user says "diagnose" or "debug", or
  describes a symptom without a cause. A failure whose cause the error already
  shows is fixed directly, without this skill.
license: Complete terms in LICENSE.txt
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Diagnosing Bugs

A discipline for hard bugs. Skip a phase only when you can say why. Check the
ADRs for the area you are about to touch.

## Bugs that arrive from elsewhere

Most bugs reach the user second-hand: a feedback document, a screenshot, a
message from a teammate or a user. Before building anything, pull out the one
item they asked about and restate the symptom in one sentence. When the source
holds several items and their ask does not single one out, get their
confirmation first. The reporter is not in the conversation, so a question about the
symptom goes to the user to relay.

## Redact

This skill has you show commands, outputs and captured artifacts. Replace
every secret with `<REDACTED>` before it appears. Build loops against
environment variables, so the credential stays in the environment rather than
in what you show. Captured artifacts carry auth headers: quote only the lines
that carry the signal. If the redacted output is not enough to diagnose the
bug, say so and ask.

## Phase 1: build a feedback loop

This is the skill. Everything else is mechanical. A tight pass-or-fail signal
that goes red on this bug is what bisection, hypothesis testing and
instrumentation consume; without one, reading code produces theories, not
causes. Spend disproportionate effort here.

### Ways to construct one, in roughly this order

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Curl or HTTP script** against a running dev server. Check whether one is
   already running before starting another.
3. **CLI invocation** with a fixture input, diffing stdout against a
   known-good snapshot.
4. **Headless browser script** (Playwright, Puppeteer) that drives the UI and
   asserts on DOM, console or network.
5. **Replay a captured trace.** Save a real request, payload or event log to
   disk; replay it through the code path in isolation.
6. **Throwaway harness.** A minimal subset of the system (one service, mocked
   dependencies) that exercises the bug's code path with a single call.
7. **Property or fuzz loop.** If the bug is "sometimes wrong output", run a
   thousand random inputs and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states
   (commit, dataset, version), automate "boot at state X, check, repeat" so
   `git bisect run` can drive it.
9. **Differential loop.** The same input through the old version and the new
   one, or two configs, with the outputs diffed.
10. **A person at the screen.** Last resort, for a bug only a human can
    trigger. Write the steps as a numbered list and say exactly what to
    capture at each one (a screenshot, a log line, a timestamp). In voice
    mode, keep the list short and put it in the spoken part.

### Tighten the loop

Treat the loop as a product. Once you have one, tighten it:

- Faster: cache setup, skip unrelated init, narrow the test scope.
- Sharper: assert on the specific symptom, not "didn't crash".
- Deterministic: pin time, seed the RNG, isolate the filesystem, freeze the
  network.

A thirty-second flaky loop is barely better than no loop; a two-second
deterministic one is tight.

### Non-deterministic bugs

The goal is not a clean repro but a higher reproduction rate. Loop the trigger
a hundred times, parallelise, add stress, narrow timing windows, inject
sleeps. A bug that shows one time in two is debuggable; one in a hundred is
not. Keep raising the rate until it is.

### When you genuinely cannot build a loop

Stop and say so. List what you tried. Ask for one of: access to the
environment that reproduces it, a redacted captured artifact (HAR file, log
dump, core dump, screen recording with timestamps), or, last and named before
touching anything, permission to add temporary instrumentation to a live
environment. Do not hypothesise without a loop.

### Completion criterion: a tight loop that goes red

Phase 1 is done when you can name one command, a script path, a test
invocation or a curl, that you have already run at least once (show the
invocation and its redacted output), and that is:

- **Red-capable**: it drives the actual bug code path and asserts the user's
  exact symptom, so it goes red on this bug and green once fixed. "Runs
  without erroring" does not count.
- **Deterministic**: the same verdict every run, or a pinned high
  reproduction rate for a flaky bug.
- **Fast**: seconds, not minutes.
- **Runnable on demand**: unattended by you, or, for a bug only a person can
  trigger (way 10), a numbered list the user can walk through in a minute with
  a defined thing to capture at each step.

If you catch yourself reading code to build a theory before this command
exists, stop: jumping to a hypothesis is the failure this skill prevents. No
red-capable command, no Phase 2.

## Phase 2: reproduce and minimise

Run the loop and watch it go red. Confirm:

- The loop produces the failure the user described, not a different failure
  that happens to be nearby. Wrong bug, wrong fix.
- The failure reproduces across several runs, or at a high enough rate for a
  flaky bug.
- The exact symptom is captured (error message, wrong output, timing) so
  later phases can verify the fix addresses it.

### Minimise

Once it is red, shrink the repro to the smallest scenario that still goes
red. Cut inputs, callers, config, data and steps one at a time, re-running the
loop after each cut, and keep only what the failure needs. A minimal repro
shrinks the hypothesis space in Phase 3 and becomes the regression test in
Phase 5.

Done when every remaining element is load-bearing: removing any one makes the
loop go green. Do not proceed until you have reproduced and minimised.

## Phase 3: hypothesise

Generate three to five ranked hypotheses before testing any of them. A single
hypothesis anchors on the first plausible idea.

Each hypothesis must be falsifiable: state the prediction it makes. "If X is
the cause, then changing Y makes the bug disappear, or changing Z makes it
worse." If you cannot state the prediction, the hypothesis is a hunch;
discard or sharpen it.

Show the ranked list to the user before testing. They often have knowledge that
re-ranks it at once ("we just deployed a change to number three") or has
already ruled some out. In voice mode, the top two and the recommended first
probe go in the spoken part. Do not block on it: proceed with your ranking if
they are away.

## Phase 4: instrument

Each probe maps to a specific prediction from Phase 3. Change one variable at
a time. Tool preference:

1. Debugger or REPL inspection if the environment supports it. One breakpoint
   beats ten logs.
2. Targeted logs at the boundaries that distinguish hypotheses.
3. Never "log everything and grep".

Tag every debug log with a unique prefix, such as `[DEBUG-a4f2]`, so cleanup
is a single grep. Untagged logs survive; tagged logs die.

For performance regressions, logs are usually the wrong tool. Establish a
baseline measurement (timing harness, `performance.now()`, profiler, query
plan), then bisect. Measure first, fix second.

## Phase 5: fix with a regression test

Write the regression test before the fix, but only at a correct seam: one
where the test exercises the real bug pattern as it occurs at the call site.
If the only available seam is too shallow (a single-caller test when the bug
needs several callers, a unit test that cannot replicate the chain that
triggered it), a regression test there gives false confidence.

If no correct seam exists, that is itself the finding: the architecture is
preventing the bug from being locked down. Write it down and carry it to
Phase 6.

If a correct seam exists:

1. Turn the minimised repro into a failing test at that seam.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 loop against the original, un-minimised scenario.

## Phase 6: cleanup

Required before declaring done:

- The original repro no longer reproduces (re-run the Phase 1 loop).
- The regression test passes, or the missing seam is documented.
- All `[DEBUG-...]` instrumentation is removed (grep the prefix).
- Throwaway harnesses are deleted, or moved to a clearly marked debug
  location.
- The hypothesis that turned out correct is stated in the commit or PR
  message, so the next debugger learns.
