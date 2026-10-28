# TMStack

Skills for Claude Code, shared across every machine I work on. Each top-level directory with a `SKILL.md` is one
skill. The files inside are the skill's own scripts.

The repo holds only the general skills. Personal instructions (`AGENTS.md`),
machine inventories and anything that names a specific host live in a private
repo with the same layout, installed next to this one by this repo's
installer. The installer links instruction files only from a checkout that
has them, so it serves both repos.

## Install

```bash
git clone https://github.com/truemar14/tmstack ~/projects/tmstack
~/projects/tmstack/install.sh          # add --dry-run to preview
```

On Windows, from PowerShell:

```powershell
git clone https://github.com/truemar14/tmstack $HOME\Work\tmstack
powershell -NoProfile -ExecutionPolicy Bypass -File $HOME\Work\tmstack\install.ps1    # add -DryRun to preview
```

The installer symlinks every skill allowed on this platform into
`~/.claude/skills/`. Run it again after pulling. It re-points its own links,
removes its links to skills that no longer exist, and never overwrites a real
skill directory or a link it did not make. `install.ps1` does the same on
Windows with junctions.

Give either installer a path to install another repo with the same layout,
such as a private one:

```bash
~/projects/tmstack/install.sh ~/projects/my-private-skills
```

The installer does not set up the speak plugin for voice mode. It lives in
its own repo, [speak-mod](https://github.com/truemar14/speak-mod), with its
own marketplace; its README has the setup.

## Skills

| Skill | What it does |
|---|---|
| `file-pr/` | File a concise PR in nine steps with done conditions: branch, rebase, diff review, verify, screenshots embedded from a throwaway commit (works in private repos), title and description conventions with bad/good examples. |
| `html-communication/` | Plans, specs, findings, and UI mock variants as one self-contained HTML page, published as a private Artifact. |
| `grilling/` | Interview the user in numbered rounds until every branch of a plan is settled. |
| `catch-up/` | Answer "where were we?" in a session you lost track of: where it stopped, what is waiting on you, and the next step. Read only. |
| `domain-modeling/` | Maintain a project's glossary (`CONTEXT.md`) and decision records (ADRs) while designing. |
| `writing-for-agents/` | The rules for writing skills, `AGENTS.md` and any other document an agent reads. Every skill here follows them. |
| `unslop/` | Cut AI tells from prose people read: PR descriptions, docs, pages, posts. |
| `review-loop/` | Review a PR with a fresh reviewer each round, fix, and repeat until a round is clean; merge only when asked. Works through every open PR in dependency order. |
| `test-handoff/` | Check a change in the real app before handing it over, then give the user numbered test scenarios and the steps only they can do. |
| `wait-what/` | Restate the last reply in plain words: what happened, what it means, the next step. |

The skills call each other. file-pr sketches a change as a file tree or call
tree when that reads faster. file-pr and html-communication run their prose
through unslop before it ships. Where one skill runs another, it says "Call
the Skill tool with" and the name, the convention in
`writing-for-agents/SKILL-MECHANICS.md`.

grilling, domain-modeling and writing-for-agents are adapted from Matt
Pocock's skills (MIT; the version is in each `LICENSE.txt`). unslop is adapted
from backnotprop/pstack (MIT). Some sections borrow ideas in new words:
test-handoff's evidence table from obra/superpowers, and its headless
fallback from anthropics/skills' webapp-testing. Each adapted skill keeps the
source notice in its `LICENSE.txt`. Everything else is MIT, see `LICENSE`.

## Cloud sessions

A cloud session runs on a fresh container that never sees your machine's
`~/.claude`, but it reads the container's own, and the environment's setup
script runs before Claude Code starts. So the install is the same as on a
machine, done by the setup script:

```bash
mkdir -p ~/.claude ~/projects
git clone --depth 1 https://github.com/truemar14/tmstack ~/projects/tmstack
~/projects/tmstack/install.sh
```

The environment cache keeps the clone for about a week, so a skill change
reaches the cloud at the next cache rebuild, or when a session pulls and
reruns the installer.

The cloud GitHub proxy blocks the GraphQL API, so `gh pr` and `gh issue` fail
there. file-pr and review-loop call `gh pr`, so they need a local session.

The `metadata` block in each frontmatter (`platform`, `scope`, `requires`)
is this repo's own convention, not standard skill frontmatter. The installer
reads `platform`. The rest is documentation.

## Principles behind the skills

`writing-for-agents/` holds the rules. Descriptions are trigger words, not
documentation. Split skills that trigger separately. Prune no-ops and stale
lines. Three habits come from outside it:

- **Bad/good example pairs.** They steer agents better than abstract rules.
- **Audit your agent history with agents.** Mine session logs for failure
  modes and write rules against the ones that happened.
- **Give agents a stop point.** "Make your changes. Don't commit or push yet.
  I'll tell you when."
