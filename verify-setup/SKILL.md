---
name: verify-setup
description: Find every way an agent can check a project works, run each one, and record what passed as a Verify section in the project's AGENTS.md.
disable-model-invocation: true
metadata:
  platform: [win32, linux, darwin]
  scope: fleet
---

# Verify setup

The **verify section** is a `## Verify` heading in the project's `AGENTS.md`,
or in `CLAUDE.md` when that is its only instruction file. It tells every later
session how to check its own work: which command is the gate, how to reach the
real target, and what each check needs. test-handoff starts from it.

The section is a cache of the environment. It earns its place only with what a
session cannot find by looking, and only with what was seen to work. Later
sessions trust it, so a stale or hopeful line does more harm than a missing
one.

## 1. Inventory

List every candidate check, one line each on what it would prove. Read every
source:

- Script files: `package.json`, `Makefile`, `justfile`, `pyproject.toml`, and
  their kin.
- CI workflows, the instruction files and the README.
- Test directories, seeds, fixtures, `.env.example`.
- Launch configs (`.claude/launch.json`, compose files) and how the real target
  is built: the extension, the app, the site the user opens.

Read a command before running it. One that writes to a shared, remote or live
resource (a deploy, a migration against a remote database, a publish, a real
email or payment, a production key) stays unrun and goes to the user in
step 4. Record names of env vars, accounts and services, never their values.

Done when every source above was read and every candidate has its line.

## 2. Run

Run every safe candidate on this machine. The real target counts: launch it
the way test-handoff would, and get a screenshot, log or response back.

- **Green**: keep it, with what it proved.
- **Red**: report it in step 4. It stays out of the section until it passes.
- **Out of reach**: write its **precondition**, the OS, machine, device,
  account or service it needs. The section is read on other machines and in
  cloud sessions, so a precondition is something any reader can test against
  itself.

Done when each candidate is green, red, or has a precondition.

## 3. Write the section

Rewrite the whole section from this run, replacing any old one. Keep a line
when it says what the environment does not: which command is the gate, what it
proves, the order, a gotcha, a precondition. A script whose name already says
what it does stays out. One screen at most:

```markdown
## Verify

Last run 2026-10-19 on Linux. If a line here is wrong, fix it in the same change.

- `npm run check`: types and lint. The gate before any commit.
- `npm test`: unit tests. Run `docker compose up -d db` first.
- Real target: `npm run dev`, then http://localhost:5173. Test user from `seed/users.json`.
- Safari extension: needs macOS with Xcode. `npm run build:safari`.
- Payments: no sandbox. Needs the user.
```

The repair line under the heading stays in every version. Sessions that never
load this skill read the section, and that line is how they keep it true.

Leave the edit uncommitted and show the diff. The instruction file is often
shared with a team, so the user decides whether it goes through file-pr.

Done when the section holds only green checks and preconditions, and the diff
is shown.

## 4. Report

One message, in this order:

1. **Red**: each failing check with its error line.
2. **Unrun**: each command held back in step 1, and what it would touch.
3. **Gaps**: at most three, one line each: what to add, what it would let an
   agent check, rough cost. Pick the ones that would most often move an item
   from test-handoff's **Needs you** to **Checked**.

Build a gap only when the user picks it.
