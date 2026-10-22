---
name: handoff
description: Compact this session into a handoff document another agent can pick up, on this machine or another.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
license: Complete terms in LICENSE.txt
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

# Handoff

Write a document a fresh agent can continue the work from. The reader is an
agent with none of this conversation. For a person catching up, the
`catch-up` skill fits instead.

## Contents

- The goal, where the work stands, and the next step.
- Decisions made and the reason for each, and approaches already tried and
  dropped, so the next agent does not retry them.
- The branch, worktree and uncommitted state.
- A **suggested skills** section naming the skills the next agent should
  call the Skill tool with.
- What the arguments say the next session is for, when the user gave any.
  Tailor the rest to it.

Point at material that already lives somewhere (specs, plans, ADRs, issues,
commits, diffs, PRs) by path or URL instead of copying it. Replace every
secret and every piece of personal data with `<REDACTED>`.

## Where it goes

The next agent has to be able to read it.

- Same machine: the OS temp directory (`$TMPDIR`, else `/tmp`; `%TEMP%` on
  Windows), outside the workspace.
- Another machine: a path that machine reads, such as a shared folder or the
  repo's branch when the user wants it committed. When neither exists and
  the `file-upload` skill and its token are present, call the Skill tool
  with `file-upload` and hand over the URL. Its rules on what may never go
  up apply to the whole document.

Done when the document is written and you have given the user its path or
URL, plus a one-line prompt to start the next session with.
