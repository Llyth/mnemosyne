# Talk with friends and the guild by default

By default Mnemosyne talks only with friends (the friend list and Battle.net friends' WoW characters) and guildmates: it drops every addon message from anyone else, except on the guild's channel, sends nothing on a group's channel, and asks only friends and guildmates it hovers or targets. A "Talk with everyone" switch, off by default, opens it to groups and strangers as before. The player asked for it: a nickname links characters to a player, and a stranger in a pick-up group has no reason to learn it. We chose dropping messages at the Client over filtering in each pure module: one check where every message comes in covers answers, learning, syncs and the news.

## Consequences

- The network grows more slowly than decision 0001 expected: second-hand identities still spread, but only through friends and guildmates.
- A friend or guildmate in your group is not met through the group's channel. They are met in the guild, by hovering them, or when they whisper first.
- The guild's channel proves its sender is a guildmate, so the roster is needed only for whispers. Whispers from another realm carry `-Realm`, which is dropped before matching.
- Friends and the roster are read again after `BN_FRIEND_INFO_CHANGED` and `GUILD_ROSTER_UPDATE`. On Forever a friend added by character name is listed with the Battle.net friends (`C_FriendList` stays empty), and both lists give `"First Last"` (checked in the game). A friend counts only while online in the game: an offline one has no character to match.
