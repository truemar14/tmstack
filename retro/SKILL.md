---
name: retro
description: Look back at a coding session and propose changes to the agent's environment, approved before any is made.
disable-model-invocation: true
license: Complete terms in LICENSE.txt
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Retro

A **retrospective** on a coding session. The output is changes to the
agent's **environment**, not to the code: what would make the next run go
right the first time. Each **finding** is one change, tied to the moment in
the session that shows it is needed.

## 1. Read the session

The session is the one the user names, or this one. Read its transcript,
not your memory of it.

- Claude Code: `~/.claude/projects/<slug>/<session-id>.jsonl`, where
  `<slug>` is the working directory with every character that is not a
  letter or digit turned into `-`.
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, keeping the files
  whose first line has `payload.cwd` equal to the working directory.

Stay in this workspace's sessions; other projects' transcripts are private
to them. Confirm the file by finding the session's opening prompt in its
first user message. Done when the transcript is open, or you say which
session you could not find and work from the conversation instead.

## 2. Find candidates

Call the Skill tool with `writing-for-agents` first: any finding that edits a
skill, `AGENTS.md` or `CLAUDE.md` follows it. Then look for moments where the
agent was slow, wrong, or corrected by the user, and sort each into one of
these:

- **Navigation.** The agent took long to find a file or fact. Fix with a
  pointer in the nearest `AGENTS.md`.
- **Automated checks.** The agent made a mistake a lint rule, type, test,
  hook or CI job would have caught. Read the repo's own check scripts and CI
  first: an existing check that is not wired up is the finding. A repo with
  no check at all is a finding by itself.
- **Mechanical rules.** A rule broken in the session that a tool could
  enforce (a banned API, an import shape, a file location) becomes that
  check. Prose rules are for judgement calls only.
- **Skills.** A skill misfired, failed to fire, or was missing. Name the
  skill and the edit. A new skill comes only from a pattern the user has
  corrected more than once.
- **Steering files.** An `AGENTS.md` line the agent ignored, or one that
  changes nothing versus the default (a **no-op**). Move it, sharpen it, or
  cut it.
- **Tool economy.** A tool call that was expensive for what it returned.
- **Information access.** A fact the agent needed and could not reach: logs,
  a read-only service, a dev server's output.

Done when every correction the user made in the session is either a finding
or set aside as a one-off with a reason.

## 3. Present and wait

List the findings worst first. Each one gives the moment in the session, the
change, and the file it touches. Wait for the user to pick which to apply;
skill and steering changes affect every future session. Done when the user
has picked.

## 4. Apply

Make the picked changes and nothing else. A change to a skill in a shared
repo goes through that repo's usual review. Report one line per change and
one line per finding the user turned down.
