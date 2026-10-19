# TMStack

Skills for Claude Code and Codex, plus two Claude Code plugins, shared across
every machine I work on. Each top-level directory with a `SKILL.md` is one
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
`~/.claude/skills/` and `~/.codex/skills/`, for each of the two harnesses
present on the machine. Run it again after pulling. It re-points its own
links, removes its links to skills that no longer exist, and never overwrites
a real skill directory or a link it did not make. `install.ps1` does the same
on Windows with junctions.

Give either installer a path to install another repo with the same layout,
such as a private one:

```bash
~/projects/tmstack/install.sh ~/projects/my-private-skills
```

The installer does not set up:

- `FILE_HOST_URL` and `FILE_HOST_TOKEN` in the shell environment, used by
  file-upload and html-communication. The host is your own deployment of
  `file-upload/worker/`, a Cloudflare Worker backed by R2. Its README has the
  four deploy steps. `FILE_HOST_TOKEN` holds the same value as the worker's
  `UPLOAD_TOKEN` secret.
- The speak plugin for voice mode. It needs function hooks turned on, the
  repo added as the `tmstack` marketplace, `speak@tmstack` installed, and an
  engine key. See `speak-mod/README.md`.

## Skills

| Skill | What it does |
|---|---|
| `file-pr/` | File a concise PR in nine steps with done conditions: branch, rebase, diff review, verify, screenshot or recording, title and description conventions with bad/good examples. |
| `babysit-pr/` | Monitor a PR through review bots and CI until green, without scope creep. |
| `file-upload/` | Upload a file to your file host and get a link-only, unindexed URL; delete with the same token. HTML updates in place; media is immutable. Worker source in `worker/`. |
| `html-communication/` | Plans, specs, findings, and UI mock variants as one self-contained HTML page. A private Artifact by default, the file host when the link must open without a login or from Codex. |
| `frontend-design/` | Guidance for the visual design of new or reshaped UI. |
| `grilling/` | Interview the user in numbered rounds until every branch of a plan is settled. |
| `catch-up/` | Answer "where were we?" in a session you lost track of: where it stopped, what is waiting on you, and the next step. Read only. |
| `domain-modeling/` | Maintain a project's glossary (`CONTEXT.md`) and decision records (ADRs) while designing. |
| `writing-for-agents/` | The rules for writing skills, `AGENTS.md` and any other document an agent reads. Every skill here follows them. |
| `unslop/` | Cut AI tells from prose people read: PR descriptions, docs, pages, posts. |
| `diagnosing-bugs/` | Six-phase discipline for hard bugs: a red feedback loop before any theory, minimise, ranked hypotheses, one probe at a time, regression test, cleanup. |
| `review-loop/` | Review a PR with a fresh reviewer each round, fix, and repeat until a round is clean; merge only when asked. Works through every open PR in dependency order. |
| `test-handoff/` | Check a change in the real app before handing it over, then give the user numbered test scenarios and the steps only they can do. |
| `wait-what/` | Restate the last reply in plain words: what happened, what it means, the next step. |

The skills call each other. html-communication publishes an Artifact, or goes
through file-upload when the link must open without a login. file-pr and
babysit-pr use file-upload for screenshots. file-pr sketches a change as a
file tree or call tree when that reads faster, and hands off to babysit-pr.
file-pr and html-communication run their prose through unslop before it
ships. review-loop holds each round to babysit-pr's done bar.

grilling, domain-modeling, writing-for-agents and diagnosing-bugs are adapted
from Matt Pocock's skills (1.2.3, MIT). unslop is adapted from
backnotprop/pstack (MIT). frontend-design is a verbatim copy from
anthropics/skills (Apache 2.0), and it keeps upstream's dashes, so it is the
one file exempt from the house style in `writing-for-agents`. Each adapted
skill keeps the source notice in its `LICENSE.txt`. Everything else is MIT,
see `LICENSE`.

## Plugins

### Skills in cloud sessions and Projects

A cloud session, or a cloud thread in a Claude Project, never reads
`~/.claude`, so the installer's links do not reach it. The `tmstack` plugin
carries the same skills there. Add it in a Project's settings under Plugins,
from the GitHub marketplace `truemar14/tmstack`. In a session that takes
plugin commands:

```sh
claude plugin marketplace add truemar14/tmstack
claude plugin install tmstack@tmstack
```

Its skills are named `tmstack:<skill>`, such as `/tmstack:file-pr`. Do not
install it on a machine that runs the installer, or each skill loads twice.
Install it from GitHub, not from a checkout's path: a path install copies the
whole folder, ignored files included, while a GitHub install has only what is
committed. A new skill goes into the plugin's `skills` list in
`.claude-plugin/marketplace.json`, and `check-skills.sh` fails until it does.

What the skills need from the machine does not come with them. Set these on
the cloud environment:

- `FILE_HOST_URL` as an environment variable, and the file host's domain in a
  custom network allowlist.
- `FILE_HOST_TOKEN` stays out of environment variables, since anyone who uses
  the environment can read those. Keep file-upload to local sessions until
  the token can come from a network secret.

The cloud GitHub proxy blocks the GraphQL API, so `gh pr` and `gh issue` fail
there. file-pr and review-loop call `gh pr`, so they need a local session or
a Project thread on your own computer.

### speak

`speak-mod/` is a Claude Code plugin of function hooks ("Claude Mods"). It
reads replies aloud with a Fish Audio or ElevenLabs voice, adds `/speak`, and
puts playback controls above the prompt. A box without speakers plays through
the machine you connected from, over SSH. The repo root's
`.claude-plugin/marketplace.json` makes the checkout a directory marketplace
named `tmstack`, so the plugin runs in place and `git pull` updates it:

```sh
claude plugin marketplace add /path/to/tmstack
claude plugin install speak@tmstack
```

The `metadata` block in each frontmatter (`harness`, `platform`, `scope`,
`requires`) is this repo's own convention, not standard skill frontmatter. The
installer reads `platform` and `harness`. The rest is documentation.

## Principles behind the skills

`writing-for-agents/` holds the rules. Descriptions are trigger words, not
documentation. Split skills that trigger separately. Prune no-ops and stale
lines. Three habits come from outside it:

- **Bad/good example pairs.** They steer agents better than abstract rules.
- **Audit your agent history with agents.** Mine session logs for failure
  modes and write rules against the ones that happened.
- **Give agents a stop point.** "Make your changes. Don't commit or push yet.
  I'll tell you when."
