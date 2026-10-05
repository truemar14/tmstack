---
name: test-handoff
description: Check a change in the real app before handing it to the user, then hand over test scenarios and the steps only they can do. Use before saying a change is fixed, done or ready to test, and when the user asks how to test something or what they need to do by hand.
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
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

- Rebuild and reload first, so the target runs the current code.
- Exercise the exact behaviour that changed, and one neighbour it could break.
- UI: look at it at desktop width, at phone width when the UI has one, and in
  light and dark if the app has both. Look at a screenshot of each, not only at logs.
- Visual variants or mocks: open every one; a broken variant never reaches the
  user.

When the real target is out of reach (another machine, a signed-in account, a
device), say exactly which part you could not check and why.

Done when each changed behaviour was seen working in the real target, or is
named as unchecked with the reason.

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
