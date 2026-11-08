# Claude project

The layer around the repo when the user works on it in a Claude project: the
cloud environment, project memory and routines that keep work moving while
the user is away. `AGENTS.md` stays the rulebook; nothing here restates it.
Where this session cannot do an item itself, giving the user the step with
its text counts as done.

## Before the PR

### Environment

- One Claude project and one cloud environment per product. Read the
  existing environment first, and extend its setup script and network list
  rather than replace them; in a team repo, ask before widening the network.
- The setup script installs the user's skills repo, as that repo's README
  says, plus what the repo's own checks need (a browser, a database).
- Secrets are environment variables or network secrets in the environment's
  settings, which the user sets. A secret added later reaches new sessions
  only.
- The network allows the hosts the work needs, including the path an agent
  uses to confirm the live commit.

Done when this session, or the user's next one, has the skills installed,
can run the repo's checks, and finds each secret by presence.

### Memory

Project memory is the project's shared memory folder. Agents in the project
add and update its files. During setup, delete no memory file and leave
existing rule lines in place; they become pointers after the merge.

- `MEMORY.md` is an index: one line per topic file, and pointers to
  `AGENTS.md` for the rules. Memory keeps only what the repo cannot hold: the
  user's working preferences, where things live, a choice the repo does not
  record. Status lives in GitHub issues and milestones, with one exception,
  `open-decisions.md`.
- One file per subject.
- `open-decisions.md` is the one list of what waits on the user: one line per
  item with the question, the recommended answer and the owning thread. A
  thread adds its line when it needs a pick and removes it once answered.
- Memory never holds secrets (they live in the environment), customer data,
  or material an employer keeps internal. For a team repo, point to where a
  system is documented instead of describing it.

Done when `MEMORY.md` exists and points to every topic file, and
`open-decisions.md` exists if the user wants routine 1.

### Routines

Two modes. **Report only**: the routine reads, posts in the project's threads
and chat, and writes only its own memory lines and its own shared files; it
never branches, pushes, opens a PR or merges. **Opens PRs**: it also
branches and opens PRs; in a solo repo it merges a PR the merge gate in
`AGENTS.md` calls safe, once its checks and review pass. In a team repo only report-only routines
run. Every routine prompt says to treat each run as fresh, read `AGENTS.md`
first and never release to production, and states its mode.

Offer these to the user in order, by name and purpose:

1. **Morning decisions list**, weekdays, report only. Reads
   `open-decisions.md`, blocked threads and, in a solo repo, `needs-owner`
   issues. An item that needs no choice goes back to its owning thread as a
   chore, or to the project chat when it has no thread. The rest is one
   numbered list, each item with a recommendation, saved in the project's
   shared files so a later answer maps to its numbers. When the user answers
   in its thread, it sends each answer to the owning thread.
2. **Bug fixes**, weekdays, opens PRs, solo repo only. Takes `bug` issues the
   user filed, oldest first, two a run at most. Claims each as `AGENTS.md`
   says, proves the bug with a failing test, fixes it, gets the fresh review,
   opens a PR. An issue it cannot fix with confidence gets `needs-owner` and
   a note on what it needs.
3. **Upkeep**, weekly, opens PRs (report only in a team repo): failing and
   missing tests, a security audit, duplicate code cleanup; and monthly, a
   report on what hosting and paid services cost.
4. **Bottleneck review**, weekly, report only, when the `bottleneck-review`
   skill is installed: where work got stuck, CI minutes, and what to
   automate.

Done when the user has said yes or no to routine 1, and each routine the user
wants has its row in `docs/operations.md`, which `AGENTS.md` points to.
Routines start after the merge, because their prompts read the merged
`AGENTS.md`.

## After the merge

The session that picks up once the rulebook PR has merged does these:

- Turn each rule line in project memory into a pointer to `AGENTS.md`.
- Create routine 1, if the user said yes, with its full prompt. Then give the
  user one more line for the project instructions: a pick waiting on the
  user goes as a line in `open-decisions.md`, not on a new card, and the
  owner check keeps its card.
- Create routines 2 to 4 one at a time, each when the user asks for it,
  once the one before has run cleanly, writing its prompt then.

Done when memory holds pointers instead of rules, and each routine the user
asked for exists.
