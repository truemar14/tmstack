# Contributing

This repo holds only general skills: nothing in it may name a machine, a
person or a company. The owner keeps those in a private repo with the same
layout, installed side by side by passing its path to this repo's installer;
the installer links `AGENTS.md` and `CLAUDE.md` only from a checkout that has
them. If you adapt this repo, do the same: fork
it for the skills, and keep your own instructions and machine skills next to
it.

Every skill follows `writing-for-agents/SKILL.md`. Before opening a PR, run
`npm test` in `speak-mod/`, `./install.sh --dry-run` and `./check-skills.sh`.

`check-skills.sh` lints each skill's frontmatter. It also fails on any term
from the `PRIVATE_NAMES` environment variable, one term per line, found in a
tracked file, matched as whole words in any case. CI reads that list from a
repository secret of the same name, so the names never land in the repo.
Without the variable the check is skipped.
