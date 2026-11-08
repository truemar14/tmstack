# Claude project

The layer around the repo when the user works on it in a Claude project: the
cloud environment, project memory and routines that keep work moving while
the user is away. `AGENTS.md` stays the rulebook; nothing here restates it.
Each section ends on a Done line; where this session cannot do an item
itself, giving the user the step with its text counts as done.

## Environment

- One Claude project and one cloud environment per product.
- The environment's setup script installs the user's skills repo, as that
  repo's README says, plus what the repo's own checks need (a browser, a
  database).
- Secrets are environment variables or network secrets in the environment's
  settings, which the user sets. A secret added later reaches new sessions
  only.
- The network allows the hosts the work needs, including the path an agent
  uses to confirm the live commit.

Done when a fresh session in the environment has the skills installed, can
run the repo's checks, and finds each secret by presence.

## Memory

Project memory is the project's shared memory folder. Agents in the project
add and update its files. During setup, delete no memory file, and turn a
rule's memory line into a pointer to `AGENTS.md` only once the rulebook PR
has merged.

- `MEMORY.md` is an index: one line per topic file, and pointers to
  `AGENTS.md` for the rules. Memory keeps only what the repo cannot hold: the
  user's working preferences, where things live, a choice the repo does not
  record. Status lives in GitHub issues and milestones.
- One file per subject.
- `open-decisions.md` is the one list of what waits on the user: one line per
  item with the question, the recommended answer and the owning thread. A
  thread adds its line when it needs a pick and removes it once answered.
- Memory holds only what the user could paste in the team's chat. Secrets
  live in the environment, never in memory. For a team repo, point to where
  a system is documented instead of describing it.

Done when `MEMORY.md` and `open-decisions.md` exist and `MEMORY.md` points to
every topic file.

## Routines

Every routine prompt says to treat each run as fresh and read `AGENTS.md`
first, states its mode below, and never releases to production. A routine
that opens PRs leaves merging to the merge gate in `AGENTS.md`. In a team
repo only report-only routines run, unless the user says the team agreed to
more.

Offer these in order, each with its prompt text. Create routine 1 on the
user's word. The others start later, one at a time, once the one before has
run cleanly: the user asks for each when ready. A routine gets its row in
`docs/operations.md`, when it runs and what it does, once it is created.

1. **Morning decisions list**, weekdays, report only. Reads
   `open-decisions.md`, blocked threads and `needs-owner` issues. An item that
   needs no choice goes back to its owning thread as a chore. The rest is one
   numbered list, each item with a recommendation. The routine keeps one
   thread: when the user answers there, it sends each answer to its owning
   thread and removes the answered lines.
2. **Bug fixes**, weekdays, opens PRs, solo repo only. Takes the user's own
   `bug` issues, oldest first, two a run at most. Claims each as `AGENTS.md`
   says, proves the bug with a failing test, fixes it, gets the fresh review,
   opens a PR. An issue it cannot fix with confidence gets `needs-owner` and
   a note on what it needs.
3. **Upkeep**, weekly; opens PRs in a solo repo and reports in a team repo:
   failing and missing tests, a security audit, duplicate code cleanup; and
   monthly, a report on what hosting and paid services cost.
4. **Bottleneck review**, weekly, report only, when the `bottleneck-review`
   skill is installed: where work got stuck, CI minutes, and what to
   automate.

Done when routine 1 is created or declined, the others are listed for the
user with their prompt text, and each routine created has its row in
`docs/operations.md`.
