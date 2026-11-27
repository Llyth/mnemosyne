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
It also shows the professions and recipes of your guildmates and friends, which
WoW Forever's own guild professions view no longer does.

> **Status: 1.4.0.** Everything version 1 set out to do: registering,
> recognition on tooltips and in chat, sharing first-hand and second-hand, and
> every language WoW Forever has; since 1.1.0, Mnemosyne's window and the
> professions of the characters you know, also in the Guild & Communities
> window since 1.3.0. Nameplates and unit frames come later; the
> plan is in [docs/decisions/](docs/decisions/) and the words in
> [CONTEXT.md](CONTEXT.md).

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
one, and nothing is registered until you click Register. A nickname cannot hold
invisible characters, except that the invisible mark a phone adds to some emoji
(as in ❤️) is dropped for you. If an older version registered a nickname with
other invisible characters, Mnemosyne asks again on that character. Only a
character's own player can register it, and Mnemosyne never links an anonymous
character to your other characters in what it shows or shares (see
[Privacy](#privacy) for what a player who records syncs could still guess).
Trial accounts are not asked: they cannot send addon
messages.

There is no server. Copies of Mnemosyne talk to each other in the background
with the game's addon messages, over your guild and group channels and by
whisper. By default Mnemosyne talks only with your friends (your friend list and
your Battle.net friends' characters) and your guild: it ignores everyone else
and sends nothing on your group's channel. Turn **Talk with everyone** on in the
settings panel to open it to your groups and to anyone you hover or target.
You learn your guildmates' nicknames when you log in, your group's when
you join it (with **Talk with everyone** on), and a friend's or a stranger's
when you hover them. Other players also pass along
what they learned before you, second-hand: two copies of Mnemosyne sync their
memories privately by whisper, in the background, at login with the first few
players who answer, with each new group member who has Mnemosyne, and when you
type `/mnemosyne sync`, at most once an hour with the same guildmate and once
every 6 hours with anyone else, counted for each of your characters on its own.
When a
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
nickname until the new character says who plays it. The same goes for a name
one of your own characters had: once another player's character takes it, it
shows that player's nickname, not yours. You keep at
most 20,000 second-hand nicknames, and take at most 1,000 changes a day (new
nicknames, newer ones, removed ones and disputed ones) from any one player,
plus up to 5,000 that player says it heard from the characters themselves in
the last day; a sync passes on at most as much, those first-hand changes first,
the rest in later syncs.

Nicknames show on tooltips and in chat (the **Show on tooltips** and **Show in
chat** switches turn each off): every chat type except emotes (channels and
Communities included), in the Communities window too, and when you hover a name
in a chat line. Your own registered characters show their nickname there too.
Nameplates and unit frames come later.

## Installing

Mnemosyne is for **WoW Forever** only (client 1.60.1). Install it with:

- WoWUp: search for Mnemosyne (it comes from
  [Wago](https://addons.wago.io/addons/56nby069)), or add it from its GitHub
  URL, `https://github.com/Llyth/mnemosyne`.
- CurseForge app: search for Mnemosyne under WoW Forever, or open its
  [CurseForge page](https://www.curseforge.com/wow/addons/mnemosyne).
- By hand: download the zip from the
  [latest release](https://github.com/Llyth/mnemosyne/releases/latest) and
  unzip it into `World of Warcraft\_forever_\Interface\AddOns\`, so that you get
  `AddOns\Mnemosyne\Mnemosyne.toc`.

Mnemosyne speaks every language WoW Forever has: English, French, German,
Spanish (Spain and Latin America), Brazilian Portuguese, Russian, Korean and
Chinese (simplified and traditional). It follows your game client's language,
using the game's own words for guilds, groups, chat and the rest, and falls back
to English for anything not translated. The slash commands stay
the same in every language (`/mnemosyne register`, `/mnemosyne lookup`...).

## Using it

Mnemosyne's window opens from the **Mnemosyne** button under the Escape menu,
or with `/mnemosyne` alone. You can drag the window
anywhere; it opens again where you left it, on the tab you last used, and Escape
closes it. Its **Identities** tab lists the characters you know, one row each,
sorted by nickname, searched by name or nickname, ignoring case and accents.
Each row shows the nickname, whether you heard it first-hand or from whom, and
when, and the version of Mnemosyne the player runs (sent by versions after 1.4.0,
and by 1.4.0 only in answer to them, so blank for older versions and for players
you haven't heard since); disputed ones are listed as disputed. Forget drops one (as
`/mnemosyne forget` does), Undo takes the forgetting back, and Whisper opens a
whisper to the character. Second-hand ones are listed only while **Show
second-hand** is on, and the first 50 found show. Your own registered and
anonymous characters come first, marked as yours. Under the list, the sync
status: this character's last sync, with whom and when, and how many players
wait for theirs.

Its **Professions** tab (`/mnemosyne professions` opens it, and the Guild & Communities window has the same tab, under its guild
tabs) shows every profession of the game as a tile, primary ones first (the
gathering ones on their own row, after the crafting ones), then secondary ones, each with how many distinct recipes and how many of the
characters you know and your own have it (0 when none does). Click one for its page: its recipes, sorted by name with how
many characters know each, and its characters, sorted by skill level. Each
shows its icon, and a recipe its tooltip when you point at it. Click a recipe
to see who knows it, online characters first (shift-click links it in chat);
click a character to whisper it. The search box
finds recipes by name and characters by name or nickname, ignoring case and
accents. A character shows its nickname only while its identity shows, and is
listed by name otherwise; your own characters are marked as yours and show
their professions as they are now, shared or not. A
profession heard second-hand shows its skill level with ~ and who passed it on,
and only while **Show second-hand** is on.

The settings panel is in Options, AddOns, Mnemosyne; the addon drawer next to
the minimap and `/mnemosyne settings` open it too. It has:

- **This character**: its registration, the nickname to register or change,
  Unregister and Keep anonymous, working like the commands and the first-login
  question. A trial account sees why it cannot register.
- **Options**, the switches: **Show on tooltips**, **Show in chat**, **Show
  second-hand**, **Pass on what I know**, **Share my professions**, **Ask
  strangers** and **Offer a report after an error**, on until you turn them off, and **Talk with everyone**, off
  until you turn it on (see [Privacy](#privacy)). Each is saved for all your characters and applies at
  once.
- **Status**: what `/mnemosyne status` says, and a **Report a bug** button that
  opens the same window as `/mnemosyne report`.

| Command | What it does |
| --- | --- |
| `/mnemosyne` | Open Mnemosyne's window |
| `/mnemosyne professions` | Open the Professions tab of Mnemosyne's window |
| `/mnemosyne settings` | Open the settings panel |
| `/mnemosyne register <nickname>` | Register the character you are playing |
| `/mnemosyne unregister` | Withdraw its registration; peers forget it |
| `/mnemosyne lookup <text>` | Find characters by name or by nickname, ignoring case and accents; a second-hand nickname shows with who passed it on |
| `/mnemosyne forget <character>` | Forget a character (its full name): drop its nickname from your memory and refuse what other players pass on about it; what the character says itself still counts. Without a name, lists the characters you forgot |
| `/mnemosyne unforget <character>` | Undo forget: learn about the character from other players again |
| `/mnemosyne sync` | Sync with the players heard this session who have Mnemosyne (at most once an hour with each guildmate, once every 6 hours with anyone else) |
| `/mnemosyne sync reset` | Forget when you last synced with each player, on all your characters, so you can sync with them again at once. It works on your side only: a player who synced with you recently still refuses until they type `/mnemosyne sync reset` too |
| `/mnemosyne status` | How many identities you know (second-hand ones only while **Show second-hand** is on), how many of your characters are registered or anonymous, how many players who have Mnemosyne you heard this session, whom this character synced with in the last 6 hours, and this character's registration (registered, anonymous, unregistered, or not registered yet) |
| `/mnemosyne report` | A debug report to paste in a bug report |
| `/mnemosyne debug` | Log every message sent and received in the chat frame, or stop |
| `/mnemosyne echo` | A test peer, Echo Mnemosyne, that sends back what you send, to test alone, or stop |
| `/mnemosyne debug copy` | The session's debug log in a window, to copy |
| `/mnemosyne help` | The list of commands |

## Privacy

Mnemosyne keeps everything on your computer, in the game's saved variables, and
sends nothing outside the game.

When you hover or target a character Mnemosyne doesn't know, it whispers that
character an ask, invisible in chat, at most once a day per character: only a
friend or a guildmate, unless **Talk with everyone** is on. Turn **Ask
strangers** off in the settings panel to stop it.

Syncs and guild posts pass along every nickname you know, second-hand, what
other players say about your own characters included, so what you hold and
pass on doesn't single them out; Mnemosyne still shows your own registrations
for them. Two
switches of the settings panel, both on by default, change that: **Pass on what
I know**, off to share only your own registrations, and **Show second-hand**, off
to see only what characters said about themselves. When a player with a newer Mnemosyne talks
to yours, it tells you once a session that a newer version exists.

Your characters share one memory, though: two of them that sync with the same
player within a short time send that player the same summary of it, which a
player who records every sync could use to guess they're yours, an anonymous
one included.

When you register a character, its nickname spreads to every player who has
Mnemosyne, through other players too. Characters you don't register are never
shared: an anonymous character only tells other players who have Mnemosyne that
it is anonymous, so they forget any nickname they held for it. Unregistering
spreads the same way, but more slowly than the nickname did.

Mnemosyne also reads your registered characters' professions: each one's skill
level, and the recipes you have learned once you open its window (Mnemosyne
never opens it itself). Until then, it finds the learned recipes your
guildmates and friends also know, and asks you once to open each window. **Share my professions**, on by default for all your
characters, shares them when you sync with another player; off, or for a
character you don't register, other players forget them. Your registered
characters also say which professions they don't have, so a profession another
player made up for one of them is dropped when it syncs. A guildmate gets the
professions of your guild roster and of your own characters (only your own with
**Pass on what I know** off); a friend outside your guild gets only your own
characters'. While you play a character you haven't registered, your other
characters' professions go only as anyone's would: to a guildmate, only those
of characters on your guild roster, and only with **Pass on what I know** on;
their changes, and turning **Share my professions** off, reach other players at
the next sync of one of your registered characters. A player whose professions you never received gets one sync even
within an hour (a guildmate) or 6 hours of the last one, so professions don't wait for the next. You keep the professions of your guild roster's characters and your
friends' only, dropped once a character has gone 30 days unseen on your roster
or online as a friend's. The **Professions** tab of Mnemosyne's window shows
them (see [Using it](#using-it)).

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
