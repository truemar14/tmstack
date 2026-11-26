# Contributing

This repo holds only general skills: nothing in it may name a machine, a
person or a company. The owner keeps those in a private repo with the same
layout, installed side by side by passing its path to this repo's installer;
the installer links `AGENTS.md` and `CLAUDE.md` only from a checkout that has
them. If you adapt this repo, do the same: fork
it for the skills, and keep your own instructions and machine skills next to
it.

Every skill follows `writing-for-agents/SKILL.md`. Before opening a PR, run
`./install.sh --dry-run` and `./check-skills.sh`.

`check-skills.sh` lints each skill's frontmatter, in this checkout or in the
repo whose path you give it, as the installer does. It also fails on any term
from the `PRIVATE_NAMES` environment variable, one term per line, found in a
tracked file, matched as whole words in any case. CI reads that list from a
repository secret of the same name, so the names never land in the repo.
Without the variable the check is skipped.

## Rules for a skill here

- Every skill carries the `metadata` block the installer reads: `platform`
  (`win32`, `linux`, `darwin`; a general skill lists all three), `scope`
  (`fleet` here; a private repo with the same layout uses it to mark skills
  bound to one machine), and `requires` when the skill needs something the
  installer does not set up.
- A skill adapted from elsewhere keeps a `license:` line in its frontmatter
  and the source's notice in `LICENSE.txt` next to it.
- Two house rules apply inside every skill here: no em dashes, en dashes or
  arrows, and no destructive action the user did not ask for.
- A skill here names no machine, person or company. Those belong in
  the user's private instructions; a skill says "the user" and reads the
  rest from there.
