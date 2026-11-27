-- Copies: the rules every per-character category spreads by (decision 0008),
-- each copy keyed by the character's full name and a key of its category,
-- first-hand and second-hand. Professions is the first category (its key, the
-- skill line ID); a category is a table on top of Copies (setmetatable with
-- __index = Copies) that sets:
--   KEYS: the category's keys, a set: any other heard is dropped, so a peer
--     cannot grow one character without end.
--   KEY: the name of the key's field in what peers and Self give.
--   FIELDS: the content's fields; a removal has no first one.
--   content(name, key, copy): what a copy says, as one text: two copies say
--     the same when it matches.
--   write(passed): the text a copy passed on takes (its size counts).
--   stamp(name), stamped(name): stamps one of this account's characters'
--     copies, as a sync starts, and returns them, as Self holds them.
--   withCurrent(), current(name): this account's characters with a copy read
--     now, and a character's copies read now (Self).
--   clean(key, heard), optional: trims the content of a copy heard from a peer.
-- Pure: it takes its saved table, the clock (the server time), the memory,
-- this account's characters and the settings as arguments (decision 0004).
--
-- Each copy follows the rules of the identities (decision 0001): a
-- first-hand one always wins; among second-hand copies the later revision
-- wins; the same revision with other content is disputed and hidden; a
-- removal (no content) is a revision too. It goes stale when its full name
-- shows up with another GUID, hidden until the character shares first-hand;
-- this account's characters', which take their GUID from Self, only once
-- the GUID seen is not Self's (another player's character took the name).
-- Kept only for this account's characters (not while they come as anyone's,
-- nor a name another player's character has taken), and for characters seen
-- on a guild roster or online as a friend's in the last 30 days; others are dropped
-- quietly. Second-hand ones are refused and dropped while the character is
-- forgotten (a first-hand one still gets through, as for identities) or while
-- its identity is held as a removal (anonymous or unregistered), so no peer
-- can link an anonymous character to its copies; first-hand ones too
-- while that removal is not disputed. Only the category's
-- keys are kept. At most 2,000 second-hand changes a day from one
-- peer, first-hand ones aside.
local _, ns = ...

local Digest = ns.Digest

local Copies = {}
ns.Copies = Copies

local DAY = 24 * 60 * 60

Copies.MAX_CHANGES_PER_PEER = 2000
Copies.KEPT_FOR = 30 * DAY -- after a character was last seen on a roster or as a friend's
Copies.PRUNE_EVERY = 10 * 60 -- seconds between two prunes as the lists are read again (seeLists)
Copies.MAX_SYNC_BYTES = 100000 -- of copies a sync passes on
Copies.STEP = 100 -- copies an answer writes before it lets the queue send (lazy)

-- category: the category's table (its __index set to itself).
-- saved: the table the category keeps its copies in
-- (MnemosyneCharacterDB.professions for professions).
-- clock: returns the server time, in seconds.
-- memory: the Memory, for forgotten characters and identities held as removals.
-- characters: this account's characters (Self): their copies are read
-- from it, and never adopted from peers.
-- settings: the saved settings; settings.passOn switches passing on what was
-- heard from others (this account's characters' copies always go, but
-- for those that go as anyone's, asAnyone).
-- scope: the Scope, which holds the friends and the guild roster as last read:
-- whose copies are kept, and which peers may keep the roster's.
-- playerName: returns the full name of the character played, the one that
-- syncs, or nil before login.
function Copies.new(category, saved, clock, memory, characters, settings, scope, playerName)
	-- name -> { guid, own, skills = { [key] = copy } }: skills, as professions saved them first.
	saved.held = saved.held or {}
	saved.seen = saved.seen or {} -- name -> when last seen on a roster or as a friend's
	saved.newFrom = saved.newFrom or {} -- peer -> { since, count }
	local now = clock()
	for peer, counted in pairs(saved.newFrom) do
		if now - counted.since >= DAY then
			saved.newFrom[peer] = nil
		end
	end
	return setmetatable({
		held = saved.held,
		seen = saved.seen,
		newFrom = saved.newFrom,
		clock = clock,
		memory = memory,
		characters = characters,
		settings = settings,
		scope = scope,
		playerName = playerName or function() end,
		changes = 0, -- how many changes were heard this session: the window redraws when it moves
		hashes = setmetatable({}, { __mode = "k" }), -- copy -> its hash, computed once
	}, category)
end

-- A copy's value as its own: a list copied, anything else as is.
local function copied(value)
	if type(value) ~= "table" then
		return value
	end
	local list = {}
	for i, item in ipairs(value) do
		list[i] = item
	end
	return list
end

-- The saved table copied whole (as new takes it), for another of the
-- account's characters to start from (the seed, decision 0001): every
-- copy held but the disputed ones, each its own tables, this account's
-- characters' included (prepare takes an unregistered one's removals from
-- them); when each character was seen, so a roster read empty at login drops
-- nothing; not the daily counts of each peer.
function Copies.copy(saved)
	local held, seen = {}, {}
	for name, character in pairs(saved.held or {}) do
		local skills = {}
		for key, copy in pairs(character.skills) do
			if not copy.disputed then
				local own = {}
				for field, value in pairs(copy) do
					own[field] = copied(value)
				end
				skills[key] = own
			end
		end
		if character.own or next(skills) then
			held[name] = { guid = character.guid, own = character.own, skills = skills }
		end
	end
	for name, seenAt in pairs(saved.seen or {}) do
		seen[name] = seenAt
	end
	return { held = held, seen = seen }
end

-- Sets a copy's content from another's: none in a removal.
local function fill(self, copy, from)
	local shows = from[self.FIELDS[1]]
	for _, field in ipairs(self.FIELDS) do
		copy[field] = shows and from[field]
	end
	return copy
end

function Copies.clean() end

local function hashOf(self, name, key, copy)
	local value = self.hashes[copy]
	if not value then
		value = Digest.hash(self.content(name, key, copy))
		self.hashes[copy] = value
	end
	return value
end

-- Whether a character is one of this account's, given the GUID it told of
-- itself (nil when none, or when a peer passed it on: no proof): not once
-- another player's character has taken its name (Self:owns, which remembers
-- a taken name account-wide, Self:seeName).
local function isOwn(self, name, guid)
	local character = self.held[name]
	return ((character and character.own) or self.characters:state(name) ~= "notAsked")
		and self.characters:owns(name, guid)
end

-- Whether one of this account's characters' copies go and come as any
-- other player's: while the character played is not registered (anonymous,
-- unregistered or not asked yet), for every other one; and, whichever
-- character plays, for every other one that is anonymous or unregistered.
-- Passed on, stamped, kept or refused as this account's then, they would link
-- the character played to them (decision 0001), or to each other; the
-- character played still shares its own first-hand.
local function asAnyone(self, name)
	local played = self.playerName()
	if played == nil or name == played then
		return false
	end
	-- Self:state, not Self:registration: no table made at each call.
	if self.characters:state(played) ~= "registered" then
		return true
	end
	local state = self.characters:state(name)
	return state == "anonymous" or state == "unregistered"
end

-- Whether a character was seen on a roster or as a friend's in the last 30 days.
local function seenLately(self, name, now)
	local seen = self.seen[name]
	return seen ~= nil and now - seen < self.KEPT_FOR
end

-- Whether copies of a character are kept: this account's, or seen lately.
-- This account's are kept as anyone's while they go and come as anyone's
-- (asAnyone), and so is a name another player's character has taken (isOwn).
local function keeps(self, name, now, guid)
	return (isOwn(self, name, guid) and not asAnyone(self, name)) or seenLately(self, name, now)
end

-- Whether a character's copy heard first-hand or not is refused:
-- second-hand while the character is forgotten or its identity is held as a
-- removal (disputed or stale too); first-hand while that removal is not
-- disputed. Any peer can forge a removal that disputes a nickname: it never
-- keeps out what the character shares itself, which for an anonymous
-- character is only removals (Self:professions).
function Copies:isRefused(name, firstHand)
	local withdrawn, disputed = self.memory:isWithdrawn(name)
	if firstHand then
		return withdrawn and not disputed
	end
	return withdrawn or self.memory:isForgotten(name)
end

-- Counts one second-hand change from a peer. Returns false once the peer
-- brought all it may of the day.
local function countChange(self, peer, now)
	local counted = self.newFrom[peer]
	if not counted or now - counted.since >= DAY then
		counted = { since = now, count = 0 }
		self.newFrom[peer] = counted
	end
	if counted.count >= self.MAX_CHANGES_PER_PEER then
		return false
	end
	counted.count = counted.count + 1
	return true
end

-- Hears a copy from a peer, as Protocol reads it: { name, [KEY], revision,
-- the content's FIELDS, guid }, a removal without content.
-- First-hand when the peer is the character itself: the GUID it tells of
-- itself counts as the game showing it (see), so under a GUID other than the
-- one of this account's character of that name, the name is another player's
-- character's, and what was held as this account's goes stale. Returns true
-- when it changed what is held.
function Copies:hear(peer, heard)
	local now, name, key = self.clock(), heard.name, heard[self.KEY]
	local firstHand = name == peer
	local guid = firstHand and heard.guid or nil -- a peer's word on another character's GUID tells nothing
	if guid then
		self:see(name, guid)
	end
	if
		not self.KEYS[key]
		or heard.revision > now + DAY
		or (isOwn(self, name, guid) and not asAnyone(self, name))
		or not keeps(self, name, now, guid)
		or self:isRefused(name, firstHand)
	then
		return false
	end
	local character = self.held[name]
	local known = character and character.skills[key]
	-- Refused on the revisions first: a copy is cleaned (a profession's recipes
	-- placed), and hashed, only when it may be kept.
	if firstHand then
		if known and known.firstHand and not known.stale and known.revision > heard.revision then
			return false
		end
	elseif known and (known.firstHand or known.stale or known.revision > heard.revision) then
		return false
	end
	local taken = { revision = heard.revision, guid = heard.guid }
	for _, field in ipairs(self.FIELDS) do
		taken[field] = heard[field]
	end
	self:clean(key, taken)
	heard = taken
	-- The hash holds the revision: copies of two revisions never say the same.
	local same = known
		and not known.disputed
		and known.revision == heard.revision
		and hashOf(self, name, key, known) == hashOf(self, name, key, heard)
	if firstHand then
		if known and known.firstHand and not known.stale and same then
			return false
		end
	else
		if known and known.revision == heard.revision and (known.disputed or same) then
			return false
		elseif not countChange(self, peer, now) then
			return false
		elseif known and known.revision == heard.revision then
			character.skills[key] = { revision = known.revision, disputed = true, heard = now }
			self.changes = self.changes + 1
			if self.heardSince then
				self.heardSince[name] = true
			end
			return true
		end
	end
	if not character then
		character = { skills = {} }
		self.held[name] = character
	end
	-- The GUID held stays, whatever the peer says (as Memory keeps it). This
	-- account's characters' copies take a peer's as anyone's would: holding
	-- none would tell a peer which names are this account's. Those prepare
	-- holds keep Self's.
	character.guid = character.guid or heard.guid
	character.skills[key] = fill(self, {
		revision = heard.revision,
		firstHand = firstHand,
		source = not firstHand and peer or nil,
		heard = now,
	}, heard)
	self.changes = self.changes + 1
	if self.heardSince then -- a category that looks at what was heard (Professions:recipesToFind)
		self.heardSince[name] = true
	end
	return true
end

-- Sees a character's GUID (a chat line, a group member, or one it told of
-- itself): a character held without one takes it; one held with another goes
-- stale, every copy of it hidden until the character shares first-hand.
-- This account's characters are left to Self, which knows their GUIDs
-- (prepare), unless the GUID seen is not the one Self knows: another player's
-- character has taken the name, which Self remembers (Self:seeName) and is
-- held as anyone's from then on.
function Copies:see(name, guid)
	self.characters:seeName(name, guid)
	local character = self.held[name]
	if character and character.own then
		if self.characters:owns(name, guid) then
			return
		end
		character.own = nil
	end
	if character and character.guid ~= guid then
		if character.guid then
			for _, copy in pairs(character.skills) do
				copy.stale = true
			end
		end
		character.guid = guid
	end
end

-- Drops every copy held, every character seen and every peer's daily
-- count: a character new since the update starts empty (Memory:empty).
function Copies:empty()
	for _, saved in ipairs({ self.held, self.seen, self.newFrom }) do
		for key in pairs(saved) do
			saved[key] = nil
		end
	end
end

-- Drops quietly the copies no longer kept: of characters neither seen on
-- a roster nor as a friend's in the last 30 days, and those refused
-- (isRefused). only (name -> character held), when given:
-- those characters only, as a sync starts (prepare).
function Copies:prune(only)
	local now = self.clock()
	if not only then
		self.prunedAt = now
		for name, seenAt in pairs(self.seen) do
			if now - seenAt >= self.KEPT_FOR then
				self.seen[name] = nil
			end
		end
	end
	for name, character in pairs(only or self.held) do
		if character.own and asAnyone(self, name) then
			-- Kept or dropped as a peer would (asAnyone), until prepare reads it
			-- again: a registered character's copies as a peer that synced
			-- with it holds them; an anonymous or unregistered one's removals go,
			-- as a peer drops them with its identity's removal.
			character.own = nil
			local registration = self.characters:registration(name)
			if not (registration and registration.nickname) then
				character.skills = {}
			end
		end
		if not character.own then
			if not keeps(self, name, now) then
				self.held[name] = nil
			else
				for key, copy in pairs(character.skills) do
					if self:isRefused(name, copy.firstHand) then
						character.skills[key] = nil
					end
				end
				if not next(character.skills) then
					self.held[name] = nil
				end
			end
		end
	end
end

-- Sees the friends' characters online and the guild roster, as the Scope
-- holds them once Client read them again: each is seen now. Then drops what is
-- no longer kept, at most once every 10 minutes: a character is kept 30 days.
function Copies:seeLists()
	local now = self.clock()
	for _, name in ipairs(self.scope:listed()) do
		self.seen[name] = now
	end
	if not self.prunedAt or now - self.prunedAt >= self.PRUNE_EVERY then
		self:prune()
	end
end

-- Reads this account's characters' copies, as a sync starts: stamps each
-- character's (stamp: a new revision for what changed since its last one, and,
-- for professions, a removal of each of the game's skill lines a registered
-- one lacks, so peers drop a copy forged for it), then keeps them first-hand,
-- with the GUID Self holds, never stale, and only them: a copy peers passed on
-- before the character was this account's never goes as its own. While the character
-- played is not registered, only its own: the others' wait for a registered
-- one (asAnyone); an anonymous or unregistered one's, only while it plays. A
-- name another player's character has taken (Self:owns) is left to it, what
-- was held as this account's under it stale, as see leaves it. Then drops
-- what is no longer kept of this account's characters; the others' as the
-- lists are read (seeLists), at most every 10 minutes.
function Copies:prepare()
	local names, account = {}, {}
	for _, character in ipairs(self.characters:list("")) do
		names[character.name] = true
	end
	local played = self.playerName()
	if played and self.characters:registration(played) then
		-- Unregistered: its removals still go while it syncs itself (goesTo).
		names[played] = true
	end
	for name in pairs(names) do
		account[name] = true
	end
	for name, character in pairs(self.held) do
		if character.own then
			account[name] = true -- unregistered or anonymous since, as anyone's from now (prune)
		end
	end
	local now = self.clock()
	for name in pairs(names) do
		local character = self.held[name]
		if not self.characters:owns(name) then
			names[name] = nil
			if character and character.own then
				-- Seen taken by another of this account's characters.
				character.own = nil
				for _, copy in pairs(character.skills) do
					copy.stale = true
				end
			end
		elseif asAnyone(self, name) then
			names[name] = nil
		end
	end
	for name in pairs(names) do
		self:stamp(name)
		local character = self.held[name] or { skills = {} }
		character.own, character.guid = true, self.characters:guid(name)
		self.held[name] = character
		local read = {}
		for _, stamped in ipairs(self:stamped(name)) do
			local key = stamped[self.KEY]
			read[key] = true
			local known = character.skills[key]
			if
				not known
				or known.stale -- from an earlier version, which took a peer's GUID for it
				or hashOf(self, name, key, known) ~= hashOf(self, name, key, stamped)
			then
				character.skills[key] =
					fill(self, { revision = stamped.revision, firstHand = true, heard = now }, stamped)
			end
		end
		for key in pairs(character.skills) do
			if not read[key] then
				character.skills[key] = nil
			end
		end
	end
	for name in pairs(account) do
		account[name] = self.held[name]
	end
	self:prune(account)
end

-- Whether a character's copies go to a peer, or come from it: this
-- account's registered characters' to a peer seen lately (on the roster or a
-- friend), which keeps them; to a guildmate, also the roster's. Passing on is
-- left aside, so both sides' digests compare the same set: answer
-- leaves the roster's out while it is off. Those of this account's anonymous
-- or unregistered characters, all removals, go only while that character is
-- the one played: the peer hears them first-hand, from the character itself,
-- which links nothing. Sent while another character of the account syncs,
-- they would link it to the account (decision 0001). While the character
-- played is not registered, the account's others go as anyone's (asAnyone),
-- left out as a peer leaves them out once their identity is held as a removal.
-- asked: { peerIsGuildmate (Scope:isGuildmate), played (the character
-- played), othersAsAnyone (asAnyone of any other) }, the same for every name
-- of a digest, asked once.
local function goesTo(self, peer, name, character, now, asked)
	if character.own and not asAnyone(self, name) then
		local registration = self.characters:registration(name)
		local registered = registration ~= nil and registration.nickname ~= nil
		return (registered or name == self.playerName()) and seenLately(self, peer, now)
	end
	local anyone = asked.othersAsAnyone and name ~= asked.played
	return (asked.peerIsGuildmate and self.scope:isGuildmate(name) and not (anyone and self:isRefused(name, true)))
		or false
end

-- The digest for a peer, and the names in each bucket: every copy that
-- goes to it, disputed ones left out.
local function sums(self, peer)
	local now, digest, names = self.clock(), Digest.new(), {}
	for bucket = 1, Digest.BUCKETS do
		names[bucket] = {}
	end
	local played = self.playerName()
	local registration = played and self.characters:registration(played)
	local asked = {
		peerIsGuildmate = self.scope:isGuildmate(peer),
		played = played,
		othersAsAnyone = played ~= nil and not (registration and registration.nickname), -- as asAnyone gives
	}
	for name, character in pairs(self.held) do
		if goesTo(self, peer, name, character, now, asked) then
			local bucket = Digest.bucket(name)
			names[bucket][#names[bucket] + 1] = name
			for key, copy in pairs(character.skills) do
				if not copy.disputed then
					digest:addIn(bucket, hashOf(self, name, key, copy))
				end
			end
		end
	end
	return digest, names
end

-- Hashes up to count copies held whose hash is not known yet, so the
-- first sync's digest does not hash them all at once. Returns whether some
-- are left.
function Copies:warm(count)
	for name, character in pairs(self.held) do
		for key, copy in pairs(character.skills) do
			if not self.hashes[copy] then
				if count == 0 then
					return true
				end
				count = count - 1
				hashOf(self, name, key, copy)
			end
		end
	end
	return false
end

-- The digest of what goes to a peer, for a sync: each copy hashed with
-- what it says, summed in the bucket of its character's name.
function Copies:digest(peer)
	return (sums(self, peer)):write()
end

-- What to pass on to a peer, from its digest: the copies that go to it,
-- in buckets whose digest differs, never a disputed or stale one, and only
-- this account's characters' while passing on is off (not those that go as
-- anyone's, asAnyone); at most
-- MAX_SYNC_BYTES (100 KB), the first-hand ones changed in the past day first, the latest
-- first, then the rest from a point that moves with the clock. Each is
-- { name, [KEY], revision, the content's FIELDS, guid }, a removal
-- without content. step(), when given, is called every few copies
-- written (a lazy answer pauses there); one dropped meanwhile is left out.
function Copies:answer(peer, digest, step)
	local now = self.clock()
	local mine, names = sums(self, peer)
	-- The rest as their name and key only: most never fit the 100 KB.
	local fresh, restNames, restKeys = {}, {}, {}
	local function passedOn(name, key)
		local character = self.held[name]
		local copy = character and character.skills[key]
		if not copy then
			return nil
		end
		local passed = { name = name, [self.KEY] = key, revision = copy.revision, guid = character.guid }
		for _, field in ipairs(self.FIELDS) do
			passed[field] = copy[field]
		end
		return passed
	end
	for _, bucket in ipairs(Digest.differing(mine:write(), digest)) do
		for _, name in ipairs(names[bucket]) do
			local character = self.held[name]
			local passes = (character.own and not asAnyone(self, name)) or self.settings.passOn
			for key, copy in pairs(character.skills) do
				if passes and not copy.disputed and not copy.stale then
					local age = now - copy.revision
					if copy.firstHand and age >= 0 and age <= DAY then
						fresh[#fresh + 1] = passedOn(name, key)
					else
						restNames[#restNames + 1], restKeys[#restKeys + 1] = name, key
					end
				end
			end
		end
	end
	table.sort(fresh, function(a, b)
		return a.revision > b.revision
	end)
	local chosen, bytes, rest = {}, 0, #restNames
	for i = 1, #fresh + rest do
		local passed = fresh[i]
		if not passed then
			local at = (now + i - #fresh) % rest + 1
			passed = passedOn(restNames[at], restKeys[at])
		end
		if passed then
			-- Written once: batching and sending reuse the text (the category's write).
			bytes = bytes + #self.write(passed) + 1
			if bytes > self.MAX_SYNC_BYTES then
				break
			end
			chosen[#chosen + 1] = passed
		end
		if step and i % self.STEP == 0 then
			step()
		end
	end
	return chosen
end

-- Every copy that shows, sorted by character name then key:
-- { name, [KEY], the content's FIELDS, revision, firstHand, source,
-- heard, own }, copies; a disputed one as { name, [KEY], disputed } only.
-- This account's characters' show as read now (Self), registered or not,
-- shared or not, without a revision; never their stamped copies.
-- Removals, stale ones and those refused (isRefused) are left out.
function Copies:list()
	local found, mine, KEY = {}, {}, self.KEY
	for _, name in ipairs(self:withCurrent()) do
		mine[name] = true
		for _, copy in ipairs(self:current(name)) do
			copy.name, copy.firstHand, copy.own = name, true, true
			found[#found + 1] = copy
		end
	end
	for name, character in pairs(self.held) do
		if not (character.own or mine[name]) then
			for key, copy in pairs(character.skills) do
				-- A refused copy shows nowhere.
				local refused = self:isRefused(name, copy.firstHand)
				if copy.disputed and not refused then
					found[#found + 1] = { name = name, [KEY] = key, disputed = true }
				elseif copy[self.FIELDS[1]] and not copy.stale and not refused then
					local shown = {
						name = name,
						[KEY] = key,
						revision = copy.revision,
						firstHand = copy.firstHand,
						source = copy.source,
						heard = copy.heard,
					}
					for _, field in ipairs(self.FIELDS) do
						shown[field] = copied(copy[field])
					end
					found[#found + 1] = shown
				end
			end
		end
	end
	table.sort(found, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a[KEY] < b[KEY]
	end)
	return found
end
