---
name: test-handoff
description: Check a change in the real app before handing it to the user, then hand over test scenarios and the steps only they can do. Use before saying a change is fixed, done or ready to test, and when the user asks how to test something or what they need to do by hand.
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
  requires: "for web changes, browser tools, or else the app's dev server and headless Playwright"
---

# Test handoff

The user is the last tester, not the first. Every handoff here passes through
two steps in order.

## 1. Check it in the real target

The **real target** is the closest non-production build of what the user
will open: the built extension in the browser it ships for, the packaged app,
the page in the browser and size they use.
A unit test, a harness page or a dev build in another browser is evidence, not
the check.

Start from the project's verify section, the `## Verify` heading in its
`AGENTS.md` or `CLAUDE.md`: it names the gate, the real target and each
check's precondition. A line there that turns out wrong gets fixed, but the
file is often shared with a team: leave that edit out of any commit and name
it in the handoff, so the user decides. When the project has no such section, say so once in the handoff and
point the user at the verify-setup skill.

- Rebuild and reload first, so the target runs the current code.
- Exercise the exact behaviour that changed, and one neighbour it could break.
- UI: look at it at desktop width, at phone width when the UI has one, and in
  light and dark if the app has both. Look at a screenshot of each, not only at logs.
- Visual variants or mocks: open every one; a broken variant never reaches the
  user.

With no browser tools (a headless box), a web app is still in
reach: start its dev server, wait until the port answers, run a short
headless Playwright script against it, then stop the server. The script
waits for the network to go idle before it reads the page, then saves a
screenshot and the console log. A browser extension needs the browser it
ships for, so this covers only its pages that also load on their own.
Without Playwright either, the app is out of reach, as below.

When the real target is out of reach (another machine, a signed-in account, a
device), say exactly which part you could not check and why. A precondition
from the verify section is the why.

Done when each changed behaviour was seen working in the real target, or is
named as unchecked with the reason.

### Evidence for each claim

A claim in the handoff needs a check run in this session, with its output
read. An earlier run, or a reason it should work, is not evidence.

| Claim | Needs | Does not count |
|---|---|---|
| Fixed | The original symptom, retried and gone | The code changed |
| Tests pass | The test command's output, zero failures | A run before the last edit |
| Builds | The build command, exit 0 | Lint or typecheck passing |
| Regression test works | Seen failing without the fix, passing with it | It passes once |
| A subagent did it | The diff, read | The subagent's report |

A claim the table cannot back goes in the handoff as unchecked, not as done.

## 2. Hand off

The handoff has three parts, in this order:

1. **Checked**: what you saw working, one line each, with a screenshot when
   the change is visual.
2. **Needs you**: the steps only the user can do (a physical device, a login,
   an approval, a purchase), numbered, each with the exact place to click or
   the exact command.
3. **Scenarios**: numbered test cases for the user, each one line of setup,
   one line of action, and the expected result. Cover what changed and the
   edge cases the change touched, nothing more.

End with the single thing you are waiting on. When nothing needs the user,
say so and carry on with the task instead of waiting.
