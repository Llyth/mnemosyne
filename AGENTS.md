# AGENTS.md

Rules for agents working in this repository.

- **Work in a worktree and ship through a pull request.** Create one worktree
  per task under `.claude/worktrees/`
  (`git worktree add .claude/worktrees/<topic> -b <topic> origin/main`, a
  git-ignored directory), never edit or commit in the main checkout, and push
  only that branch, never `main` (a pull request is required, merged by squash).
  The pull request's CI (the required checks listed in
  [CONTRIBUTING.md](CONTRIBUTING.md#repository-protection); a check skipped by its
  path filter counts as passing) must pass before the work counts as done.
- **Assign yourself to the pull request.** Open it with `--assignee @me`
  (`gh pr create --assignee @me ...`), so the person who owns the work is the
  assignee from the start.
- **Start the pull request title (and commit subject) with the right word.**
  The autolabeler (`.github/workflows/pr-meta.yml`) labels the pull request
  from its title, and the label sets the release version bump and the section
  of the release notes (`.github/configs/draft-release.yml`). Use an imperative
  verb ("Add ...") or a conventional commit prefix ("feat: ...", "fix(sync): ...");
  both work:

  | Label | Starts with | Bump |
  | --- | --- | --- |
  | `major` | `type!:` (e.g. `feat!:`) or "BREAKING" anywhere | major |
  | `enhancement` | `feat`, `perf`; Add, Implement, Introduce, Support, Enable, Allow, Create, Expose, Provide, Extend, Improve, Enhance, Optimize, Show, Display, Render | minor |
  | `bug` | `fix`, `bugfix`, `hotfix`; Fix, Correct, Repair, Resolve, Prevent, Revert | patch |
  | `documentation` | `docs`; Document, Docs, Readme | patch |
  | `chore` | `chore`, `refactor`, `ci`, `build`, `test`, `style`, `deps`; Refactor, Simplify, Clean, Rename, Move, Remove, Drop, Replace, Switch, Migrate, Update, Upgrade, Bump, Pin, Use, Harden, Group, Skip, Scan, Check, Lint, Run, Configure, Tighten, ... | patch |

  Whatever the label, a pull request that only touches tests, docs, CI or
  tooling is left out of the release notes and the version bump: only
  `Mnemosyne.toc`, `src/` and `.pkgmeta` count (the `pre-include` paths in
  `.github/configs/draft-release.yml`, the same as the Release workflow's
  `paths`).

  Pick the first word for what the change means to players: a new capability is
  "Add"/"feat", a bug is "Fix", CI or tooling is "Skip"/"ci"/"Harden"... A
  title that matches nothing gets `chore` (a patch, under Maintenance) and a
  warning on the `meta` job: if that is wrong for the change, set the label by
  hand or start the title with a word from the table. Labels are only added, so
  after editing a title fix a stale label by hand. `no-release` keeps a pull
  request out of the release notes and the version bump (Dependabot's
  `dev-tools` group gets it automatically); add `major` by hand for a breaking
  change the title doesn't announce.
- **Never set the version by hand.** The .toc says `## Version: @project-version@`:
  the packager replaces it with the release tag, the only place the version is
  set (see CONTRIBUTING.md, Releases).
- **Keep README.md true for players.** A pull request that changes what players
  see or do (a command, a setting, where nicknames show, what is shared,
  installing) updates README.md in the same pull request. README.md describes
  what is released, or says plainly what is not yet: keep its status line in step
  (in design, then the version of the first release).
- **Run the pre-commit hooks before pushing.** `uv run pre-commit run --all-files`
  (luacheck, StyLua, gitleaks, zizmor, shellcheck, markdownlint, whitespace and
  file hygiene) catches locally what review would otherwise ask for.
  - The luacheck hook, and busted on push, run `.lua/bin/`, which is git-ignored
    and so missing from a new worktree. Link it to the main checkout's build once
    per worktree (`ln -s ../../../.lua .lua` from the worktree's root; the main
    checkout must have run `scripts/setup-lua.sh` first), or build it in the
    worktree with `scripts/setup-lua.sh` (needs `gcc` and `make`).
  - With neither possible, run `SKIP=luacheck,busted uv run pre-commit run --all-files`,
    push with `SKIP=busted git push`, and let CI run luacheck and busted.
- **One feature, one pull request.** Don't aggregate: a new setting, a refactor, a
  CI change and a dependency bump each get their own branch, worktree and pull
  request, even when they come from the same request.
- **Fix a change in the pull request it belongs to.** While that pull request
  isn't merged, amend its branch (and its description) instead of opening
  another pull request on top or patching it in a later one; update branches
  with a rebase and `git push --force-with-lease`. Once it is merged, further
  changes need a new pull request.
- **Stack pull requests, as much as possible.** Each pull request holds one
  change, but related pull requests form a GitHub stack. Pull requests are
  related when any of these holds:
  - they touch the same module (one file of `src/core/`, `src/client/` or
    `src/interface/`, such as `Memory`, `Sync` or `Client`), CI or the same files;
  - they share a label (`enhancement`, `bug`, `chore`, `documentation`, ...; the
    list is not exhaustive), so a batch of enhancements, of bug fixes or of chores
    counts as related;
  - one needs the other (it edits or needs what the other adds: tests that go
    with a feature, a CI change that needs a code fix);
  - they come from the same request: an agent that opens several pull requests
    for one task stacks all of them.

  Only unrelated changes (a dependency bump and a feature, say) go in separate,
  standalone pull requests; so does one that must ship alone (a hotfix, a change a
  revert would need to undo by itself).
  - A `PreToolUse` hook (`.claude/hooks/require-stack.sh`) refuses `gh pr create`
    while you have other open pull requests, unless the command has `--base` set to
    a branch other than `main` (a stacked pull request) or ends with
    `# standalone: <why>` (it is unrelated to every open one).
  - Branch each pull request from the previous one's branch, order the stack so
    every level passes CI on its own, then run `gh stack link <pr> <pr> ...`
    (bottom to top: it sets each base and creates the stack; `gh stack submit`
    does the same from a locally tracked stack). Put "Stacked on #N" in each
    description.
  - Merge the whole stack at once, since each single merge puts every pull request
    above it behind `main` and costs a rebase and a CI run:
    `gh stack merge <stack-number> --yes --squash` (`gh pr merge` is refused for a
    stacked pull request). To merge several pull requests or stacks, go from the
    biggest stack to a single pull request last, so the cost of the rebases falls
    on the smallest.
  - After a pull request outside the stack merges, rebase the stack onto `main`,
    bottom branch first (`git rebase --onto origin/main <old base tip>`, then each
    branch onto the one below it), or run `gh stack rebase` on a stack tracked
    locally with `gh stack init`; then `git push --force-with-lease` each branch and
    fix whatever the rebase breaks.
- **Use the project's words.** Open [CONTEXT.md](CONTEXT.md) before naming a
  concept in code, tests, UI or docs (identity, first-hand, second-hand, peer,
  memory, revision, anonymous character).
- **Check the decision records before changing a settled design.** Read the
  matching file in [docs/decisions/](docs/decisions/) before reopening how
  identities spread, the sync, the key, the module shape, the target client or
  distribution.
- **Test at a seam, red first.** Read [docs/agents/testing.md](docs/agents/testing.md)
  before writing a test: tracer bullets through the pure modules, and the game by
  hand for the adapters.
- **Read the WoW API rules before calling the game.**
  [docs/agents/wow-api.md](docs/agents/wow-api.md) covers Forever's API, secret
  values, addon messages (untrusted input) and the saved variables.
- **Review each pull request, and recheck `main`.** Read
  [docs/agents/review-pr.md](docs/agents/review-pr.md) for every pull request you
  open or update, and [docs/agents/review-codebase.md](docs/agents/review-codebase.md)
  to audit the whole codebase after a stack merges or before a release.
- **Graphify first.** Understand the code through graphify (queries, wiki,
  report; see CLAUDE.md) before you grep or open files, and brief every agent
  you spawn the same. Only the main checkout has the graph: use it from there.
- **Shape modules deep.** Put much behavior behind a small interface (a deep
  module) and test through that interface
  ([decision 0004](docs/decisions/0004-a-pure-core-two-adapters-no-libraries.md)).
