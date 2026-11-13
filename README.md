# Mnemosyne

[![CI](https://github.com/Llyth/mnemosyne/actions/workflows/ci.yml/badge.svg)](https://github.com/Llyth/mnemosyne/actions/workflows/ci.yml)
![WoW Forever](https://img.shields.io/badge/WoW-Forever%201.60.1-blue)
![Lua 5.1](https://img.shields.io/badge/Lua-5.1-2C2D72?logo=lua&logoColor=white)
![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=precommit&logoColor=white)
![License: all rights reserved](https://img.shields.io/badge/license-all%20rights%20reserved-lightgrey)

On WoW Forever every character has a first and a last name, and most players
pick a word play or a role-play name instead of the nickname their friends know
them by. Mnemosyne, named after the Greek goddess of memory, puts the nickname
back: when you hover a character or read its chat line, you see who plays it.

> **Status: in design.** Nothing is playable yet. This page describes what
> version 1 will do; the plan is in [docs/decisions/](docs/decisions/) and the
> words in [CONTEXT.md](CONTEXT.md).

## Contents

- [How it works](#how-it-works)
- [Installing](#installing)
- [Using it](#using-it)
- [Privacy](#privacy)
- [Reporting a problem](#reporting-a-problem)
- [More documentation](#more-documentation)

## How it works

The first time you log in on a character, Mnemosyne asks who plays it, a few
seconds after you enter the world, never in combat, during a loading screen or
in an instance. You can register it with your nickname, keep it anonymous, or
ask to be asked again at your next login on it. The nickname is filled in from
your other registered characters, or else from what other players say about this
one, and nothing is registered until you click Register. Only a character's own
player can register it, and an anonymous character is never linked to your
other characters. Trial accounts are not asked: they cannot send addon
messages.

There is no server. Copies of Mnemosyne talk to each other in the background
with the game's addon messages, over your guild and group channels and by
whisper. You learn your guildmates' nicknames when you log in, your group's when
you join it, and a stranger's when you hover them. Other players also pass along
what they learned before you, second-hand.

Anyone can pass along something false, so a nickname heard from the character
itself always wins and shows plainly, `Hugh Jass (Tony)`. One heard second-hand
shows in grey, `Hugh Jass (~Tony)`, with the name of the player who passed it on.

Nicknames show on tooltips and in chat: every chat type except emotes
(channels and Communities included), in the Communities window too, and when
you hover a name in a chat line. Nameplates and unit frames come later.

## Installing

Mnemosyne is for **WoW Forever** only (client 1.60.1). No release exists yet; once
it does:

- WoWUp: search for Mnemosyne (it comes from Wago), or add it from its GitHub
  URL, `https://github.com/Llyth/mnemosyne`.
- CurseForge app: search for Mnemosyne under WoW Forever.
- By hand: download the zip from the
  [latest release](https://github.com/Llyth/mnemosyne/releases/latest) and
  unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so that you get
  `AddOns\Mnemosyne\Mnemosyne.toc`.

## Using it

Everything has a place in the settings panel (Options, AddOns, Mnemosyne, also
in the addon drawer next to the minimap). The same actions as commands:

| Command | What it does |
| --- | --- |
| `/mnemosyne register <nickname>` | Register the character you are playing |
| `/mnemosyne unregister` | Withdraw its registration; peers forget it |
| `/mnemosyne lookup <text>` | Find characters by name or by nickname, ignoring case and accents |
| `/mnemosyne sync` | Sync with the peers you can reach now (coming) |
| `/mnemosyne status` | How many identities you know, how many of your characters are registered or anonymous, and this character's registration |
| `/mnemosyne report` | A debug report to paste in a bug report |
| `/mnemosyne debug` | Log every message sent and received in the chat frame, or stop |
| `/mnemosyne help` | The list of commands |

## Privacy

Mnemosyne keeps everything on your computer, in the game's saved variables, and
sends nothing outside the game.

When you hover or target a character Mnemosyne doesn't know, it whispers that
character an ask, invisible in chat, at most once a day per character. Turn off
**Ask strangers** in the settings to send nothing when you just hover people.

When you register a character, its nickname spreads to every Mnemosyne user,
through other players too. Characters you don't register are never shared: an
anonymous character only tells other Mnemosyne users that it is anonymous, so
they forget any nickname they held for it. Unregistering spreads the same way,
but more slowly than the nickname did.

Forgetting a character removes it from your own memory and keeps it out until
you undo it. Nobody else is told.

## Reporting a problem

Type `/mnemosyne report` in the game. It shows a link to copy (Ctrl+C) and open
in your browser: a [bug report](https://github.com/Llyth/mnemosyne/issues/new?template=bug_report.yml)
already filled in with the debug report, where you only add what you did. If the
link does not open, copy the full report from the same window and paste it in the
form. When Mnemosyne hits one of its own errors, it offers the same report once
per session, until you click **Don't ask again**. Nothing is sent by itself.

The report holds the Mnemosyne version, the game's build and locale, your
settings, how many identities and characters you have, the last errors and the
last 200 messages sent, received or dropped (kept across a `/reload`). It never
holds a nickname or a message's text, and it replaces other players' names with
short codes. For a
security problem, follow [SECURITY.md](SECURITY.md) instead.

## More documentation

- [CONTEXT.md](CONTEXT.md): the project's words
- [docs/decisions/](docs/decisions/): the design decisions and why
- [CONTRIBUTING.md](CONTRIBUTING.md): development, tests, releases and
  repository protection
- [SECURITY.md](SECURITY.md): how to report a vulnerability
- [LICENSE](LICENSE): all rights reserved; you may read the code and install
  the addon, not reuse it
