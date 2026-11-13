# Identities spread second-hand, first-hand wins

Mnemosyne shares identities peer to peer with the client's addon messages, with no server. Peers pass along what they know, so you can learn that Hugh Jass is Tony without ever meeting Hugh Jass: the network grows past the people you meet. Addon messages are not authenticated, so a second-hand identity can be false: it is shown apart from a first-hand one (heard from the character itself), and a first-hand identity always replaces it. We chose this over first-hand only, which is safe but reaches only your guild and groups, and over signed registrations, which need cryptography in pure Lua and a way to trust a key on first contact.

## Consequences

- Each character is registered on its own, by its player, on that character; nothing links an anonymous character to the player's others.
- Players can only describe themselves. Nobody can register another character, and there are no notes about other characters, not even private ones.
- Unregistering and staying anonymous have to spread second-hand too, or peers would bring a withdrawn identity back. Each change carries the character's revision, the game server's time of the change (or the previous revision plus one, if later, so it always moves forward), which survives a reinstall: among second-hand copies the later one wins, and the same revision with different nicknames is disputed and hidden until the character speaks. What peers say about one of your own characters is never adopted: it only pre-fills the registration prompt for you to confirm.
- A hostile peer can push false identities, so you keep at most 20,000 second-hand identities and accept at most 1,000 new ones per peer per day; first-hand identities never count toward either.

**Update, 2026-11-13.** The per-peer limit now counts every change: new identities, later revisions, removals and disputes alike. Known risk: revisions are trusted across hops, so a forged revision up to a day ahead beats every honest copy and spreads through syncs. The daily limit caps how many identities one peer can forge, but each forged one stays until the character changes its identity or is heard first-hand.
