# Claude project

The layer around the repo when the user works on it in a Claude project: the
cloud environment, project memory and routines that keep work moving while
the user is away. `AGENTS.md` stays the rulebook; nothing here restates it.

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

Agents in the project write and prune its memory; the user reads it.

- `MEMORY.md` is an index: one line per topic file, and pointers to
  `AGENTS.md` for the rules. Rules about the repo live in the repo; memory
  keeps only what the repo cannot hold, such as the user's preferences and
  where things are. Status lives in GitHub issues and milestones.
- One file per subject: a system, the user's working preferences, a decision
  with its reason.
- `open-decisions` is the one list of what waits on the user: one line per
  item with the question, the recommended answer and the owning thread. A
  thread adds its line when it needs a pick and removes it once answered.
- In a team repo, memory and the project's shared files hold rules and
  pointers only: no secrets, customer data or confidential facts.

Done when `MEMORY.md` and `open-decisions` exist and `MEMORY.md` points to
every topic file.

## Routines

Offer these in order, each with its prompt text. Create routine 1 on the
user's word. The others start later, one at a time, once the one before has
run cleanly: the user asks for each when ready. Every routine prompt says to
treat each run as fresh and read `AGENTS.md` first, says whether the routine
only reports or may open PRs, and never releases to production. In a solo
repo a routine merges only under the merge gate. In a team repo every
routine only reports, unless the team agrees otherwise. A routine gets its
row in `docs/operations.md`, when it runs and what it does, once it is
created.

1. **Morning decisions list**, weekdays. Reads `open-decisions`, blocked
   threads and `needs-owner` issues. An item that needs no choice goes back
   to its owning thread as a chore. The rest is one numbered list, each item
   with a recommendation, and the user's reply goes to each owning thread.
2. **Bug fixes**, weekdays. Takes the user's own `bug` issues, oldest first,
   two a run at most. Claims each with `in-progress`, proves the bug with a
   failing test, fixes it, gets the fresh review, opens a PR. An issue it
   cannot fix with confidence gets `needs-owner` and a note on what it needs.
3. **Upkeep**, weekly: failing and missing tests, a security audit, duplicate
   code cleanup; and monthly, a cost review of CI minutes and hosting.
4. **Bottleneck review**, weekly, when the `bottleneck-review` skill is
   installed: where work got stuck and what to automate. Report only.

Done when routine 1 is created or declined, the others are listed for the
user with their prompt text, and each routine created has its row in
`docs/operations.md`.
