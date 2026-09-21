# Contributing

This repo holds only general skills: nothing in it may name a machine, a
person or a company. The owner keeps those in a private repo with the same
layout, installed side by side; the installer links `AGENTS.md` and `CLAUDE.md`
only from a checkout that has them. If you adapt this repo, do the same: fork
it for the skills, and keep your own instructions and machine skills next to
it.

Every skill follows `writing-for-agents/SKILL.md`. Before opening a PR, run
`npm test` in `speak-mod/` and `./install.sh --dry-run`.
