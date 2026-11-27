# A pure core, two adapters, no libraries

The rules live in four pure modules that never call the WoW API: `Memory` (identities, first-hand wins, revisions, disputes, the cap, digests), `Self` (your characters' registrations), `Protocol` (the wire format, chunking, validating what peers send) and `Sync` (the digest exchange and its cooldowns). They take the clock and their saved tables as arguments, so busted tests them outside the game, including a simulation of several peers wired by an in-memory transport. Two adapters face the game: `Client` (events, addon messages, the paced queue, lockdown, saved variables) and `Interface` (the registration prompt, the settings panel, tooltip and chat recognition, slash commands, locales). We chose this over one file per feature (registration, recognition, tooltip, commands...), which would make thin modules over the same data and leave the rules untestable outside the client.

**Update, 2026-11-13.** The core has since grown to seven pure modules: `Recognition` (what to show where a character appears), `Strangers` (whom to ask and when) and `Report` (the debug report and its link) joined the first four. The adapters stay two, now split into files: `Client` with `Encounter` (asking strangers on hover and target), and `Interface` with `Chat`, `Commands`, `Prompt`, `Panel` and `ReportWindow`; `Debug`, the message log, serves both. The decision holds.

No library is embedded (Ace3, ChatThrottleLib, LibDeflate), against the habit of most addons: the queue, the hash and the locale table are small, and nothing then waits on a library's support for WoW Forever.

**Update, 2026-11-14.** `src/` now has a folder per layer: `core/` for the nine pure modules (busted: the seven above, `News` and `Scope`), `client/` and `interface/` for the two adapters, `locales/`, and `Debug.lua` beside them, as it serves both. It follows the layout of the best-structured addons on CurseForge (BagBrother `core/`, `frames/`, `config/`; QuestieDB `src/`), grouped by layer rather than by feature, so the line between what busted tests and what is checked in the game is a path.

**Update, 2026-11-14.** The paced queue moved out of `Client` into a tenth pure module, `Outbox` (the jobs, the sync messages in turns, the allowance and the 1 KB a second), so busted tests it. `Client` hands it a port: whether the client is paused, how to build a job's message, and how to send one. The decision holds.

**Update, 2026-11-14.** The routing of peers' messages moved out of `Client` too, into an eleventh pure module, `Inbox` (who is heard, on which channel each kind counts, the answer cooldown, the syncs after login and with group members). `Client` checks a message holds no secret value, then hands it over. The decision holds.

**Update, 2026-11-27.** The digest scheme moved out of `Memory` and `Professions`, which each wrote it, into a pure module of its own, `Digest` (the hash, the bucket of a name, the sums, the written form and the buckets two digests differ in), which both use. What goes on the wire is unchanged. The decision holds.

**Update, 2026-11-27.** The pure modules in `src/core/` are now fourteen, each tested by busted through its own interface:

- `Protocol`: the wire format, chunking, and validating what peers send.
- `Digest`: the digest a sync compares, for identities and professions alike.
- `Memory`: identities, first-hand wins, revisions, disputes, staleness, the cap and the daily limits.
- `Self`: your characters' registrations and their professions as read from the game.
- `Professions`: every profession held, first-hand and second-hand (decision 0008).
- `Sync`: the digest exchange, its cooldowns and its early syncs (decision 0002).
- `News`: the guild news a sync's changes post, and those heard.
- `Recognition`: what to show where a character appears, and the status.
- `Strangers`: whom to ask who plays them, and when.
- `Scope`: whom Mnemosyne talks with, and who is a friend or a guildmate (decision 0007).
- `Report`: the debug report and its link.
- `Outbox`: the paced queue of addon messages.
- `Inbox`: where every peer's message comes in, and what it leads to.
- `Catalog`: what the Professions tab shows.

The adapters stay two: `Client` with `Encounter`, and `Interface` with `Chat`, `Commands`, `Prompt`, `Panel`, `Window`, `Identities`, `ProfessionsTab`, `CommunitiesTab` and `ReportWindow`; `Debug` serves both. The decision holds.
