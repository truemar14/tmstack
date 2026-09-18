---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR.
license: Complete terms in LICENSE.txt
metadata:
  harness: [claude, codex]
  platform: [win32, linux, darwin]
  scope: fleet
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is
the active discipline: challenging terms, inventing edge-case scenarios, and
writing the glossary and decisions down the moment they crystallise. Merely
reading `CONTEXT.md` for vocabulary is not this skill; that is a one-line habit
any skill can do. This skill is for when you are changing the model, not just
consuming it.

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The
map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          # system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 # context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily, only when you have something to write. If no
`CONTEXT.md` exists, create one when the first term is resolved. If no
`docs/adr/` exists, create it when the first ADR is needed.

The glossary is needed in every conversation about the project, so it loads
in every session rather than sitting behind a pointer. When you create a
`CONTEXT.md`, import it from the repo's `CLAUDE.md` with a line that reads
`@CONTEXT.md`; Codex has no import syntax, so the repo's `AGENTS.md` opens
with "Read `CONTEXT.md` before anything else." ADRs stay behind a pointer:
they matter only on the branch that touches their area.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in
`CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation'
as X, but you seem to mean Y. Which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical
term. "You're saying 'account'. Do you mean the Customer or the User? Those
are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific
scenarios. Invent scenarios that probe edge cases and force the user to be
precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If
you find a contradiction, surface it: "Your code cancels entire Orders, but
you just said partial cancellation is possible. Which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Do not batch these
up; capture them as they happen. Use the format in
[CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` is a glossary and nothing else. Keep implementation details,
specs, scratch notes and implementation decisions out of it.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse.** The cost of changing your mind later is meaningful.
2. **Surprising without context.** A future reader will wonder "why did they
   do it this way?"
3. **The result of a real trade-off.** There were genuine alternatives and you
   picked one for specific reasons.

If any of the three is missing, skip the ADR. Use the format in
[ADR-FORMAT.md](./ADR-FORMAT.md).
