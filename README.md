# tmstack

Skills for Claude Code and Codex, plus one Claude Code plugin, shared across
every machine I work on. Each top-level directory with a `SKILL.md` is one
skill; the files inside are the skill's own scripts.

The repo holds only the general skills. Personal instructions (`AGENTS.md`),
machine inventories and anything that names a specific host live in a private
repo with the same layout, installed side by side with this one. The installer
links instruction files only when a checkout has them, so both repos can run
it. The private repo carries its own copy of the installer, so the two can
drift; this one is the reference.

## Install

```bash
git clone https://github.com/marians1d/tmstack ~/projects/tmstack
~/projects/tmstack/install.sh          # add --dry-run to preview
```

On Windows, from PowerShell:

```powershell
git clone https://github.com/marians1d/tmstack $HOME\Work\tmstack
powershell -File $HOME\Work\tmstack\install.ps1    # add -DryRun to preview
```

The installer symlinks every skill allowed on this platform into
`~/.claude/skills/` and `~/.codex/skills/` (whichever harnesses exist). Run it
again after pulling: it re-points its own links, removes its links to skills
that no longer exist, and never overwrites a real skill directory or a link it
did not make. `install.ps1` does the same on Windows with junctions.

Not done by the installer:

- `FILE_HOST_URL` and `FILE_HOST_TOKEN` in the shell environment (file-upload,
  html-communication). The host is your own deployment of
  `file-upload/worker/`, a Cloudflare Worker backed by R2; its README has the
  four deploy steps. The token is the worker's `UPLOAD_TOKEN` secret under
  its client name.
- The speak plugin (voice mode): function hooks on, the repo added as the
  `tmstack` marketplace, `speak@tmstack` installed, an engine key set. See
  `speak-mod/README.md`.

## Skills

| Skill | What it does |
|---|---|
| `file-pr/` | File a concise PR in nine steps with done conditions: branch, rebase, diff review, verify, screenshot or recording, title and description conventions with bad/good examples. |
| `babysit-pr/` | Monitor a PR through review bots and CI until green, without scope creep. |
| `file-upload/` | Upload a file to your file host and get a link-only, unindexed URL; delete with the same token. HTML updates in place; media is immutable. Worker source in `worker/`. |
| `html-communication/` | Plans, specs, findings, and UI mock variants as one self-contained HTML page, a private Artifact by default, the file host when the link must open without a login or from Codex. |
| `frontend-design/` | Distinctive, intentional visual design for new or reshaped UI. |
| `grilling/` | Interview the user in numbered rounds until every branch of a plan is settled. |
| `domain-modeling/` | Keep a project's glossary (`CONTEXT.md`) and decision records (ADRs) sharp while designing. |
| `writing-for-agents/` | The rules for writing skills, `AGENTS.md` and any other document an agent reads; every skill here follows them. |
| `unslop/` | Cut AI tells from prose people read: PR descriptions, docs, pages, posts. |
| `diagnosing-bugs/` | Six-phase discipline for hard bugs: a red feedback loop before any theory, minimise, ranked hypotheses, one probe at a time, regression test, cleanup. |

How the skills fit together: html-communication publishes an Artifact, or
goes through file-upload when the link must open without a login; file-pr and
babysit-pr use file-upload for screenshots; file-pr sketches a change as a
file tree or call tree when that reads faster, and hands off to babysit-pr.
file-pr and html-communication run their prose through unslop before it
ships.

grilling, domain-modeling, writing-for-agents and diagnosing-bugs are adapted
from Matt Pocock's skills (1.2.3, MIT), unslop from backnotprop/pstack (MIT)
and frontend-design is copied verbatim from anthropics/skills (Apache 2.0);
each keeps the source notice in its `LICENSE.txt`. Everything else is MIT, see
`LICENSE`. frontend-design is also the one file exempt from the house style
in `writing-for-agents` (it keeps upstream's dashes).

## Plugin

`speak-mod/` is not a skill but a Claude Code plugin of function hooks
("Claude Mods"): replies read aloud with a Fish Audio or ElevenLabs voice,
`/speak`, and playback controls above the prompt. A box without speakers
plays on the machine you connected from, over SSH. The repo root's
`.claude-plugin/marketplace.json` makes the checkout a directory marketplace
named `tmstack`, so the plugin runs in place and `git pull` updates it:

```sh
claude plugin marketplace add /path/to/tmstack
claude plugin install speak@tmstack
```

The `metadata` block in each frontmatter (`harness`, `platform`, `scope`,
`requires`) is this repo's own convention, not standard skill frontmatter. The
installer reads `platform` and `harness`; the rest is documentation.

## Principles behind the skills

`writing-for-agents/` holds the rules: descriptions are trigger words, not
documentation; split skills that trigger separately; prune no-ops and stale
lines. Three habits from outside it:

- **Bad/good example pairs** steer agents better than abstract rules.
- **Audit your agent history with agents**: mine session logs for failure modes
  and write rules against the ones that actually happened.
- **Give agents a stop point** ("Make your changes. Don't commit or push yet.
  I'll tell you when.").
