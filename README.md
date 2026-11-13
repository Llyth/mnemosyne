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
what they learned before you, second-hand: two copies of Mnemosyne sync their
memories privately by whisper, in the background, at login with the first few
players who answer, with each new group member who has Mnemosyne, and when you
type `/mnemosyne sync`, at most once every 6 hours with the same player. When a
sync brings you a nickname that is new to you or newer, or an unregistration,
Mnemosyne posts it to your guild once, after a few seconds, unless a guildmate
posted it first, so the whole guild learns it at once.

Anyone can pass along something false, so a nickname heard from the character
itself always wins and shows plainly, `Hugh Jass (Tony)`. One heard second-hand
shows in grey, `Hugh Jass (~Tony)`, with the name of the player who passed it on
in its tooltip. When players pass along different nicknames for the same
character, it shows none until the character says who plays it. When a
character is deleted or renamed and another one takes its name, Mnemosyne
notices the new character in chat or in your group and stops showing the old
nickname until the new character says who plays it. You keep at
most 20,000 second-hand nicknames, and take at most 1,000 changes a day (new
nicknames, newer ones, removed ones and disputed ones) from any one player; a
sync passes on at most 1,000 too, the rest in later syncs.

Nicknames show on tooltips and in chat (the **Show on tooltips** and **Show in
chat** switches turn each off): every chat type except emotes (channels and
Communities included), in the Communities window too, and when you hover a name
in a chat line. Nameplates and unit frames come later.

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

Mnemosyne speaks English and French: it follows your game client's language,
and falls back to English for anything not translated. The slash commands stay
the same in every language (`/mnemosyne register`, `/mnemosyne lookup`...).

## Using it

The settings panel is in Options, AddOns, Mnemosyne; the addon drawer next to
the minimap and `/mnemosyne` alone open it too. It has:

- **This character**: its registration, the nickname to register or change,
  Unregister and Keep anonymous, working like the commands and the first-login
  question. A trial account sees why it cannot register.
- **Options**, the switches, all on until you turn them off: **Show on
  tooltips**, **Show in chat**, **Show second-hand**, **Pass on what I know**,
  **Ask strangers** and **Offer a report after an error** (see
  [Privacy](#privacy)). Each is saved for all your characters and applies at
  once.
- **Status**: what `/mnemosyne status` says, and a **Report a bug** button that
  opens the same window as `/mnemosyne report`.
- **Identities**: the characters you know, searched by name or nickname,
  ignoring case and accents, each with its nickname, whether you heard it
  first-hand or from whom, and when; disputed ones are listed as disputed. Forget
  drops one (as `/mnemosyne forget` does) and Undo takes the forgetting back.
  Second-hand ones are listed only while **Show second-hand** is on, and the
  first 50 found show.

| Command | What it does |
| --- | --- |
| `/mnemosyne` | Open the settings panel |
| `/mnemosyne register <nickname>` | Register the character you are playing |
| `/mnemosyne unregister` | Withdraw its registration; peers forget it |
| `/mnemosyne lookup <text>` | Find characters by name or by nickname, ignoring case and accents; a second-hand nickname shows with who passed it on |
| `/mnemosyne forget <character>` | Forget a character (its full name): drop its nickname from your memory and refuse what other players pass on about it; what the character says itself still counts. Without a name, lists the characters you forgot |
| `/mnemosyne unforget <character>` | Undo forget: learn about the character from other players again |
| `/mnemosyne sync` | Sync with the players heard this session who have Mnemosyne (at most once every 6 hours each) |
| `/mnemosyne status` | How many identities you know (second-hand ones only while **Show second-hand** is on), how many of your characters are registered or anonymous, how many players who have Mnemosyne you heard this session, whom you synced with in the last 6 hours, and this character's registration (registered, anonymous, unregistered, or not registered yet) |
| `/mnemosyne report` | A debug report to paste in a bug report |
| `/mnemosyne debug` | Log every message sent and received in the chat frame, or stop |
| `/mnemosyne echo` | A test peer, Echo Mnemosyne, that sends back what you send, to test alone, or stop |
| `/mnemosyne debug copy` | The session's debug log in a window, to copy |
| `/mnemosyne help` | The list of commands |

## Privacy

Mnemosyne keeps everything on your computer, in the game's saved variables, and
sends nothing outside the game.

When you hover or target a character Mnemosyne doesn't know, it whispers that
character an ask, invisible in chat, at most once a day per character. Turn
**Ask strangers** off in the settings panel to stop it.

Syncs and guild posts pass along every nickname you know, second-hand. Two
switches of the settings panel, both on by default, change that: **Pass on what
I know**, off to share only your own registrations, and **Show second-hand**, off
to see only what characters said about themselves. When a player with a newer Mnemosyne talks
to yours, it tells you once a session that a newer version exists.

When you register a character, its nickname spreads to every player who has
Mnemosyne, through other players too. Characters you don't register are never
shared: an anonymous character only tells other players who have Mnemosyne that
it is anonymous, so they forget any nickname they held for it. Unregistering
spreads the same way, but more slowly than the nickname did.

Forgetting a character (`/mnemosyne forget`) removes it from your own memory
and keeps what other players pass on about it out until you undo it, on all your
characters, without telling anyone. Your syncs stop passing it on too. If
the character itself tells you who plays it, that still counts, and is passed on
like anything you heard first-hand.

## Reporting a problem

Type `/mnemosyne report` in the game, or click **Report a bug** in the settings
panel's Status. Either opens a window with a link to copy (Ctrl+C) and open in
your browser: a [bug report](https://github.com/Llyth/mnemosyne/issues/new?template=bug_report.yml)
already filled in with the debug report, where you only add what you did. If the
link does not open, copy the full report from the same window and paste it in the
form. When Mnemosyne hits one of its own errors, it offers the same report once
per session, until you click **Don't ask again** (the **Offer a report after an
error** switch turns it back on). Nothing is sent by itself.

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
