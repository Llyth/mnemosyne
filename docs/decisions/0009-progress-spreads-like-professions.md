# Progress spreads like professions

On WoW Forever, many raids, entrances, shortcuts and extra bosses need an attunement, a key or a summoning item, and nothing in the game shows which guildmates have one. Mnemosyne shares them as a third kind of data after identities and professions: each registered character's **progress**, one **milestone** per attunement, entrance key or summoning item, telling whether the character has it now, is on the way to it, or neither. Each milestone has its own revision and follows the professions' rules (decision 0008), which follow the identities' (decision 0001): first-hand wins, the later revision wins among second-hand copies, the same revision with other content is disputed and hidden, and removals spread. The per-character rules (revisions, first-hand and second-hand, disputes, removals, stale, scope, `asAnyone`, the daily limit, the digest) are one engine in one core module, shared by Professions and Progress, so a fix to what a character's data reveals lands once for both. We chose this over a separate addon, which would rebuild the peers, the sync and the trust rules, and over a second copy of the professions' rules for progress, which would let every privacy fix made to one miss the other.

## Consequences

- Only registered characters share. An anonymous or unregistered character, or one not asked yet, shares nothing, and becoming anonymous or unregistered withdraws what was shared. Your own characters that do not share still show their progress to you only, marked as yours. Sharing is on by default, behind one account-wide "Share my progress" switch next to "Share my professions"; turning it off spreads removals.
- Progress is kept for the same characters as professions: your guild roster's, your friends' characters' (for 30 days after last seen online as one) and your own.
- Progress spreads through syncs only (decision 0002), never as news, with a digest of its own, passed on after the identities and the professions. The new message kinds join protocol version 2, since a peer drops kinds it doesn't know. A peer accepts at most 2,000 milestones a day from one peer.
- Peers that synced during the cooldown before they shared progress get one early sync, as for professions (decision 0008, 2026-11-24 update): the saved early syncs mark a peer `"progress"` once its digest of progress is answered; a peer marked only `"heard"` (its professions answered) skips the cooldown once more, and an older peer, which never sends a digest of progress, gets that one early sync only.
- The milestones are one data table in a pure module, each with a short stable ID on the wire. Adding one later is an entry in that table, its column's name in each locale (or the instance's ID when the game names it) and the count in its test; a new kind of field also needs code to read it, check it and write it. An older client ignores IDs it doesn't know.
- A cell heard from a peer is taken whole or dropped whole, never trimmed: a cell naming an item, quest or gems its milestone doesn't have is dropped, since a trimmed copy would say other than the same revision on a newer peer, which would dispute and hide it there. So an older client drops what a later version adds (a milestone, an item, a quest), and a newer peer passes it on again at each sync while their digests differ, a bounded cost accepted for a simple rule. Changing a cell's format (a field, or gems past three bits) needs a new message kind: this version's reader drops a line in any other shape.
- A milestone reports access now. An item counts while it is held in the bags, the keyring or the bank, the bank as last seen: each character remembers only the tracked items it saw at its last bank visit. A quest completed with the item gone counts as nothing.
- Each milestone shows ✓, In progress or —; a summon shows ✓ or — only. A character's milestones are read again at login, when its bags or keyring change (coalesced), when a quest is accepted or turned in, and when the bank closes, never in combat. A milestone gets a new revision only when its state changes.
- No character level is shared.
- Milestones are split by dungeon level: a dungeon whose level range reaches 60 is endgame, one below is leveling. Item and quest IDs were checked on Wowhead's Forever database (`https://www.wowhead.com/forever/item=<id>`, `/quest=<id>`).

  **Attunements**

  | Milestone | ✓ | In progress | IDs |
  | --- | --- | --- | --- |
  | Onyxia | Drakefire Amulet held | a quest of the chain in the log or completed, the final one not completed, the amulet not held | item 16309; Alliance quests 6403 The Great Masquerade, 6501 The Dragon's Eye, 6502 Drakefire Amulet; Horde quests 6585 The Test of Skulls, Axtroz, 6601 Ascension..., 6602 Blood of the Black Dragon Champion |
  | Molten Core | a greyed placeholder that tracks nothing ("Not in WoW Forever yet") | | quests 7848, 7487 kept for later |

  **Endgame entrances**

  | Milestone | ✓ | In progress | IDs |
  | --- | --- | --- | --- |
  | Blackrock Depths | Shadowforge Key held | Dark Iron Legacy in the log | item 11000; quest 3802 |
  | Dire Maul | Crescent Key held (never a quest) | — | item 18249 |
  | Scholomance | Skeleton Key held | The Key to Scholomance in the log | item 13704; quests 5505 (Alliance), 5511 (Horde) |
  | Upper Blackrock Spire | Seal of Ascension held | a gem held, a seal quest in the log, or the Unforged or Forged Seal held | Seal 12344; Unadorned Seal 12219; gems Spirestone 12336, Smolderthorn 12335, Bloodaxe 12337; Unforged 12323, Forged 12324; quests 4742, 4743 |
  | Stratholme | Key to the City held | — | item 12382 |

  **Endgame summons** (one milestone per boss, ✓ or —)

  | Boss | Counts when held | IDs |
  | --- | --- | --- |
  | Theldren (Blackrock Depths, Ring of Law) | Banner of Provocation | 21986 |
  | Mor Grayhoof (Lower Blackrock Spire) | its Brazier of Beckoning or the Brazier of Invocation | 22049 / 22057 |
  | Isalien (Dire Maul East) | its Brazier of Beckoning or the Brazier of Invocation | 22050 / 22057 |
  | Jarien & Sothos (Stratholme) | its Brazier of Beckoning or the Brazier of Invocation | 22051 / 22057 |
  | Kormok (Scholomance) | its Brazier of Beckoning or the Brazier of Invocation | 22052 / 22057 |
  | Lord Valthalak (Upper Blackrock Spire) | its Brazier of Beckoning or the Brazier of Invocation | 22056 / 22057 |

  The lent Brazier of Beckoning and the kept Brazier of Invocation count as one item for the boss. The Tier 0.5 questline itself is not tracked.

  **Leveling** (the same rules as their endgame kind)

  | Milestone | Kind | ✓ | In progress | IDs |
  | --- | --- | --- | --- | --- |
  | Scarlet Monastery | entrance | The Scarlet Key held | — | item 7146 |
  | Gnomeregan | entrance | Workshop Key held | — | item 6893 |
  | Maraudon | entrance | Scepter of Celebras held | its quests in the log | item 17191; quests 7044, 7046 |
  | Krol'dok Stronghold (40–45) | entrance | Krol'dok Compound Key held | its quests in the log | item 267089; quests 94973, 94974 (Horde), 94980, 94981 (Alliance) |
  | City of Dalaran (about 28–35) | entrance | Dalaran Sewer Key held | Heart of Disruption in the log | item 277507; quests 92458 (Alliance), 96984 (Horde) |
  | Gahz'rilla (Zul'Farrak) | summon | Mallet of Zul'Farrak held | — | item 9240 |
  | Lyn the Ignored (City of Dalaran) | summon | Tome of Dalaran held | — | item 275989 |

  Left out for now, each an entry and its name to add later: the Brooch of the Wardens (277136; what it opens in the Barrow Deeps prison is unconfirmed), the Prison Cell Key (cells only), the Executioner's Key (single use), Zul'Gurub's items (not in Forever), and the Azsharan Key and the Krol'dok Ogre Key (what they open is unconfirmed).
- Progress shows in a Progress tab after Professions, in Mnemosyne's window and in the Guild & Communities window (the same 628 px view as Professions there), with four sub-tabs: Attunements, Endgame entrances, Endgame summons and Leveling. Each window remembers its last sub-tab.
- Each sub-tab is a grid: one row per character, one column per milestone, a search box, and a Whisper button on each row except your own characters'. A row reads "Nickname (Character Name)" when the identity shows, else the character's name, as in the Professions tab, and your own characters are marked. A character with no progress in the sub-tab is hidden unless "Show everyone" is ticked; the Leveling sub-tab lists anyone with a leveling milestone, level-60 characters included.
- Rows sort by nickname, then name. Clicking a column header puts ✓ first, then In progress, then —; clicking again returns to that order. Clicking the Upper Blackrock Spire header sorts by how many gems are lacking, then which; hovering a gem mark lists who lacks it.
- A ✓ for an item shows the item's icon next to the tick, with the game's item tooltip on hover. In progress shows a short text and the icon of the item it leads to, with the quest's name or the item's tooltip on hover. Upper Blackrock Spire without the Seal shows three gem marks (Spirestone, Smolderthorn, Bloodaxe), lit when held, each with its item tooltip; the Unforged or Forged Seal shows "In progress (seal)" with the three gems lit.
- A second-hand copy looks as in the Professions tab, with "heard from" its source in the tooltip; one hidden by a dispute or a taken name shows —, with the reason in the tooltip.
- Nothing new shows in tooltips, chat or slash commands.

## Check in the game

These are open: only the game can tell, and the rules above may change with the answers.

- Whether the keyring is read (bag −1, `Enum.BagIndex.Keyring` or `KEYRING_CONTAINER`, never the number), including when `C_ActionBar.ShouldShowKeyring()` is false, and which of these keys go in the keyring.
- Whether the bank tabs can be read with the bank open, and what `C_Item.GetItemCount(id, true)` returns with it closed.
- Whether a quest is already flagged completed when `QUEST_TURNED_IN` fires, and at `PLAYER_LOGIN`.
- Whether a Brazier of Beckoning leaves the bags at its quest's turn-in; whether the Brazier of Invocation and the Banner of Provocation stay usable for good; whether the Mallet of Zul'Farrak, the Tome of Dalaran and the Dalaran Sewer Key are kept.
- Item icons for items the client hasn't cached yet (`C_Item.GetItemIconByID` may answer late).
