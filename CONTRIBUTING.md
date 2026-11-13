# Contributing

How Mnemosyne is laid out, built, tested, released and protected. Mnemosyne is a
WoW Forever addon that shows the nickname of the player behind a character (see
[README.md](README.md)); its words are in [CONTEXT.md](CONTEXT.md) and its design in
[docs/decisions/](docs/decisions/). Agents also follow [AGENTS.md](AGENTS.md).

## Contents

- [Setup](#setup)
- [Project layout](#project-layout)
- [Development](#development)
  - [Checks](#checks)
  - [Tests](#tests)
  - [Trying it in the game](#trying-it-in-the-game)
  - [Linting and pre-commit](#linting-and-pre-commit)
  - [Skills worth using](#skills-worth-using)
- [Releases](#releases)
  - [Publishing to CurseForge, Wago and WoWUp](#publishing-to-curseforge-wago-and-wowup)
- [Dependency updates](#dependency-updates)
- [Repository protection](#repository-protection)

## Setup

```sh
uv sync                        # pre-commit and hererocks, at the locked versions
scripts/setup-lua.sh           # Lua 5.1, LuaRocks, busted and luacheck, in .lua/
uv run pre-commit install      # once per clone; all its worktrees share it
```

`scripts/setup-lua.sh` builds Lua from source, so it needs a C compiler (`gcc`,
`make`), not a system Lua. Everything lands in `.lua/` (git-ignored); run the
script again after a version in it changes. StyLua comes from its pre-commit
hook, which downloads the release binary.

## Project layout

| Path | Purpose |
| --- | --- |
| `Mnemosyne.toc` | The addon's manifest: `## Interface: 16001` (WoW Forever), the saved variables, and the files in load order. No flavor suffix ([decision 0006](docs/decisions/0006-forever-only-with-a-plain-toc.md)) |
| `src/` | The addon's Lua, one file per module: the pure modules `Memory`, `Self`, `Protocol` and `Sync`, and the adapters `Client` and `Interface` ([decision 0004](docs/decisions/0004-a-pure-core-two-adapters-no-libraries.md)). Not written yet |
| `spec/` | The busted tests of the pure modules, and the multi-peer simulation |
| `.pkgmeta` | The packager's manifest: what the release zip leaves out |
| `.luacheckrc`, `stylua.toml`, `.busted` | luacheck (Lua 5.1, the WoW globals the addon may use), StyLua and busted |
| `scripts/setup-lua.sh` | Builds the project-local Lua and installs busted and luacheck at pinned versions |
| `pyproject.toml`, `uv.lock` | The dev tools uv installs: pre-commit and hererocks. Not the addon's version |
| `docs/` | `decisions/` (decisions that are hard to reverse, surprising and a real trade-off), `agents/` (rules for agents) |
| `CONTEXT.md` | The glossary |
| `AGENTS.md`, `CLAUDE.md`, `.claude/` | Rules for agents, the Claude Code settings, the stacking hook and the graphify skill |

Configuration and automation:

| Path | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | CI on pull requests (not on push to `main`), see [Checks](#checks) |
| `.github/workflows/pr-meta.yml` | One job per new pull request: assigns it to its author and labels it from its title, falling back to `chore` |
| `.github/workflows/release.yml`, `.github/configs/draft-release.yml` | Release notes drafted on every merge to `main` that changes the addon; a manual run builds, uploads and publishes, see [Releases](#releases) |
| `.github/workflows/cache-warm.yml`, `.github/actions/setup/` | The shared setup (uv, and the Lua build cached by the hash of `scripts/setup-lua.sh`), and its caches refilled on `main` so pull requests start warm |
| `.github/workflows/trivy.yml`, `trivy.yaml` | Weekly Trivy scan of `main`, the same as the CI `trivy` job |
| `.github/dependabot.yml` | Weekly updates of the dev tools, the actions and the pre-commit hooks, with a 7-day cooldown |
| `.github/ISSUE_TEMPLATE/` | The bug report form, which asks for the in-game debug report |
| `.pre-commit-config.yaml` | Local hooks that mirror CI |
| `.gitleaks.toml`, `.markdownlint-cli2.yaml`, `.editorconfig`, `.gitattributes` | gitleaks config, Markdown rules, editor whitespace (tabs in Lua), LF line endings |

## Development

### Checks

```sh
.lua/bin/luacheck .              # lint, against .luacheckrc
.lua/bin/busted                  # the tests in spec/
uv run pre-commit run --all-files
```

CI runs on pull requests. The `changes` job filters by path: a job is skipped when
a pull request touches none of its files (docs only, for example), except
`gitleaks`. A skipped job counts as passing for the required checks.

| Job | What it does |
| --- | --- |
| `lint` | luacheck, StyLua, shellcheck, zizmor (GitHub Actions) and markdownlint |
| `test` | busted, over `spec/` |
| `package` | Builds the release zip with the packager, without uploading, checks that it holds `Mnemosyne/Mnemosyne.toc` and no development files, and keeps it 7 days as an artifact to try in the game |
| `trivy` | Vulnerabilities in the dev tools (`uv.lock`), misconfigurations and secrets |
| `gitleaks` | Secret scan of the history |

### Tests

Two seams ([docs/agents/testing.md](docs/agents/testing.md)): the pure modules,
with busted, outside the game, and the adapters, by hand in the game. busted
runs every `spec/*_spec.lua`; a spec loads the pure files the way the client does,
each with the addon name and the shared namespace table as its `...`.

### Trying it in the game

Link the checkout into the game's AddOns folder once, then `/reload` after each
change:

```sh
# WSL, with the game on Windows: adjust the path to your installation
ln -s "$PWD" "/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/Mnemosyne"
```

On Windows itself, use `mklink /D` from an administrator prompt. A pull request's
`package` artifact is the zip a release would ship, for testing what players get.
`/mnemosyne debug` logs every addon message sent and received; testing a sync takes
two clients, or a friend.

### Linting and pre-commit

luacheck checks Lua 5.1 with every WoW global the addon uses declared in
`.luacheckrc`: an undeclared one is a typo or an API missing on Forever. StyLua
formats (tabs, 120 columns).

**Pre-commit hooks** catch locally what CI would. On commit they run luacheck,
StyLua, gitleaks (staged changes), zizmor, shellcheck, markdownlint and file
hygiene (whitespace, line endings, YAML and TOML syntax, merge markers, large
files, private keys, executable bits); on push, busted.

### Skills worth using

| When | Skill |
| --- | --- |
| Settling terms and decisions | `mattpocock-skills:grilling`, `mattpocock-skills:domain-modeling` |
| Shaping a module's interface | `mattpocock-skills:codebase-design` |
| Planning a slice | `mattpocock-skills:to-spec`, `mattpocock-skills:to-tickets` |
| Building it | `mattpocock-skills:tdd`, `caveman:lean-build`, `ponytail:ponytail` |
| Restructuring, migrating saved variables or the protocol | `caveman:safe-refactor`, `caveman:migration` |
| Before merging | `code-review`, `security-review`, `ponytail:ponytail-review`, `caveman:verify-and-stop` |
| Something fails | `mattpocock-skills:diagnosing-bugs`, `caveman:investigate-first` |
| The prompt, the panel | `ui-ux-pro-max:ui-ux-pro-max`, `mattpocock-skills:prototype` |
| Player-facing text | `humanizer:humanizer` |

## Releases

Every merge to `main` that changes the addon (`Mnemosyne.toc`, `src/`, `.pkgmeta`:
the `paths` of `.github/workflows/release.yml`, the same list as the `pre-include`
category of `.github/configs/draft-release.yml`) updates a draft release with
[cloudposse/github-action-auto-release](https://github.com/cloudposse/github-action-auto-release)
(release-drafter). Its notes list the merged pull requests by label, and the next
version is the highest bump among their labels: `major` is a major bump, `minor`,
`enhancement` or `feature` a minor one, anything else a patch. Tests, docs, CI and
tooling never reach the notes or bump the version.

**Labels.** `.github/workflows/pr-meta.yml` sets them from the first word of the
pull request's title (the words are in [AGENTS.md](AGENTS.md)); Dependabot labels
its own.

**Version.** The release tag (`v1.2.3`) is the only place the version is set: the
packager writes it into the .toc's `## Version: @project-version@`. Releases start
at `0.1.0`, once the first slice is playable, and every `0.x` is a normal release
(WoWUp ignores prereleases while a stable release exists); `1.0.0` ships when the
version 1 scope is complete. README.md says "early version" until then.

**Cutting a release.** Run the **Release** workflow from the Actions tab, on `main`
(a run from another branch fails), with `publish` ticked
([decision 0005](docs/decisions/0005-distribution.md)):

1. the draft's version is resolved;
2. the packager builds `Mnemosyne-v<version>-forever.zip`, with the tag only local,
   and uploads it to CurseForge and Wago when their projects are set up (below);
3. the workflow writes `release.json` (what WoWUp reads to pick the zip for
   Forever) and attaches both files to the draft;
4. the draft is published, which creates the tag.

A failed step leaves a draft, never a published release without its download. A
release made with the workflow's `GITHUB_TOKEN` does not trigger other workflows.

### Publishing to CurseForge, Wago and WoWUp

These steps need accounts, so they are done by hand, once. Until they are, the
Release workflow only builds the zip for GitHub.

1. **Before the first release, make the repository public**
   (Settings, General, Danger Zone). WoWUp installs from GitHub only from a public
   repository. Check the history first: `gitleaks` runs on every pull request, and
   `gitleaks git` scans it locally.
2. **CurseForge.** On [authors.curseforge.com](https://authors.curseforge.com),
   create a project: game World of Warcraft, the WoW Forever flavor, license "All
   Rights Reserved" (the same as [LICENSE](LICENSE)). Create an API token under
   your account's API tokens. In the repository settings, add the secret
   `CF_API_TOKEN` and the variable `CF_PROJECT_ID` (the project's number). New
   files wait for CurseForge's moderation (8:00 to 15:00 CET).
3. **Wago.** On [addons.wago.io](https://addons.wago.io), create the project for
   WoW Forever and a developer API token. Add the secret `WAGO_API_TOKEN` and the
   variable `WAGO_PROJECT_ID`. Wago is what makes Mnemosyne searchable in WoWUp.
4. **WoWUp hub** (after the first public release): ask on WoWUp's Discord to list
   `Llyth/mnemosyne` on the hub, saying that the flavor is in `release.json`
   (`forever`), since the .toc has no `_Forever` suffix. Without a listing, WoWUp
   users install from Wago or from the GitHub URL.

## Dependency updates

Dependabot (`.github/dependabot.yml`) opens weekly pull requests, with a 7-day
cooldown, for the dev tools in `uv.lock` (grouped as `dev-tools`, labeled
`no-release`), the GitHub Actions (pinned by commit SHA) and the pre-commit hooks.
busted and luacheck are pinned in `scripts/setup-lua.sh` and bumped by hand; the
cache key follows the script, so CI rebuilds them on the next run. The packager
(`BigWigsMods/packager`) is an action, so Dependabot bumps it; read its changelog
for Forever changes before merging. The addon itself embeds no library.

## Repository protection

Modeled on [wowf](https://github.com/Llyth/WoWF)'s, minus what only makes sense for
more than one contributor. Rulesets only take effect on a private repository with a
paid plan, so they are set up when the repository goes public:

- **`main` ruleset** (no bypass actors): no deletion, no force pushes, linear
  history, and changes only through a pull request that is squash-merged with
  every review thread resolved, with these status checks required (a check
  skipped by its path filter counts as passing): `changes`, `lint`, `test`,
  `package`, `trivy` and `gitleaks`. `changes` is required because a failed
  `changes` skips every job that needs it, and those skipped checks would pass.
  Add a new job to the ruleset when it is added to `ci.yml`.
- **`pr-branches` ruleset**: force pushes allowed on pull request branches, for
  rebases and `git push --force-with-lease`.
- **Repository settings:** squash merging only, branches deleted after merge,
  Dependabot security updates and vulnerability alerts on, private vulnerability
  reporting on (see [SECURITY.md](SECURITY.md)).
- **Code owners:** `.github/CODEOWNERS` makes `@Llyth` the owner of everything and
  lists the sensitive paths on their own.
- **CI hardening:** a read-only `GITHUB_TOKEN` by default, actions pinned by commit
  SHA, `persist-credentials: false`, and concurrent runs cancelled.
