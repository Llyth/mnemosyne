# Security policy

## Reporting a vulnerability

Report it privately through GitHub: open the repository's **Security** tab and
choose **Report a vulnerability**. Please do not open a public issue or pull
request for it.

The maintainer must have private vulnerability reporting turned on (Settings,
Code security) for that button to appear. If it is not there, open an issue that
only says you have a security report, without details, and the maintainer will
set up a private channel.

## Scope

In scope: the addon's code in this repository, above all what it does with
addon messages other players send (a message that crashes the addon, slows the
game, fills the memory, or makes a false identity pass for first-hand), what it
sends, and the workflows that build and publish it.

Out of scope: a player lying about their own nickname (Mnemosyne never verifies
a nickname, see [CONTEXT.md](CONTEXT.md)); a false second-hand identity, which
the design shows apart and lets first-hand override
([decision 0001](docs/decisions/0001-identities-spread-second-hand-first-hand-wins.md));
the game client and Blizzard's servers; copies of the addon not downloaded from
its GitHub releases, CurseForge or Wago.

## What to include

- What you found and why it matters (what an attacker gains).
- The version, and the steps or the addon messages that reproduce it.
- A proof of concept, if you have one. Do not include other players' real names
  or nicknames.

## What to expect

The maintainer will acknowledge the report and look into it as soon as they can,
then tell you what they decided and fix it in a release. No response time is
promised. Please give the maintainer time to fix the issue before you disclose it.

## Supported versions

Only the latest release is supported.

## Related reading

- [docs/agents/wow-api.md](docs/agents/wow-api.md): the rules for code that calls
  the game, addon messages included.
