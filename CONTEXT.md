# Mnemosyne

A WoW Forever addon that helps players recognize the people they know behind characters whose names are word plays or role-play names. This file is the glossary: the words used in code, tests, UI and docs.

## Language

**Player**:
The person playing, known to their friends by a nickname. One player can have several characters.
_Avoid_: user, account

**Character**:
A WoW Forever character, named with a first name and a last name, often a word play rather than the player's nickname.
_Avoid_: toon, avatar, alt (for a character in general)

**Nickname**:
The name a player is really known by in their community, as the player types it: free text, self-declared, never verified, tied to no other service, and neither unique nor owned (two players can both be Tony).
_Avoid_: Discord nickname, username, handle, tag, battle tag

**Registration**:
A character's declaration of its player's nickname, made by the player on that character only. Each character is registered, or not, on its own.
_Avoid_: sign-up, claim, link

**Anonymous character**:
A character whose player chose not to register it. Mnemosyne never links it to a nickname or to the player's other characters.
_Avoid_: hidden, private, unregistered (a character not asked yet is neither)

**Recognition**:
Showing a character's nickname where the character appears: its tooltip and its chat lines.
_Avoid_: identification, detection

**Identity**:
What Mnemosyne knows about one character: that it belongs to the player with a given nickname, heard first-hand or second-hand.
_Avoid_: record, entry, mapping, profile

**Peer**:
Another player's character running Mnemosyne, which you can exchange messages with.
_Avoid_: node, client, user

**First-hand**:
Heard from the character itself. A first-hand identity always wins over a second-hand one.
_Avoid_: verified, trusted (nothing is verified: a player can still lie about themselves)

**Second-hand**:
Heard from a peer that is not the character, passed along from its memory. Shown apart from first-hand, because any peer can pass along something false.
_Avoid_: gossip, rumor, relayed, unverified

**Source**:
The peer a second-hand identity came from, shown with it so you can judge it.
_Avoid_: origin, provider, relay

**Memory**:
Every identity one account holds, first-hand and second-hand, shared by all its characters.
_Avoid_: database, cache, store

**Revision**:
When, by the game server's clock, a character's player last registered it, changed its nickname, unregistered it or kept it anonymous. Between second-hand copies, the later revision wins.
_Avoid_: version, timestamp

**Disputed**:
An identity heard second-hand with the same revision but different nicknames. Not shown until the character settles it first-hand.
_Avoid_: conflict, invalid

**Stale**:
An identity whose full name now belongs to another character (a different GUID), after its own was deleted or renamed. Hidden until the new character speaks first-hand.
_Avoid_: expired, outdated, invalid

**Sync**:
Two peers bringing each other's memory up to date, privately and in the background.
_Avoid_: exchange, transfer, replication

**News**:
An identity that a sync brought you new or at a higher revision, posted once to your guild so it spreads in seconds.
_Avoid_: update, broadcast, event

**Ask**:
A message asking a character to say who plays it. A peer answers with its identity, or that it is anonymous.
_Avoid_: ping, request, query

**Unregistering**:
Withdrawing a character's registration. The character tells its peers, and they forget its identity.
_Avoid_: deleting, opting out

**Forgetting**:
Dropping a character's identity from your own memory and refusing second-hand copies of it until you undo it. A first-hand message from the character still gets through. Nobody else is told.
_Avoid_: deleting, blocking
