-- Memory: every identity this account holds, keyed by the character's full
-- name as the server gives it ("First Last", decision 0003). Pure: it takes
-- its saved table and the clock (the server time) as arguments (decision 0004).
--
-- The rules of decision 0001 live here: a first-hand identity always wins;
-- among second-hand copies the later revision wins; the same revision with
-- different nicknames is disputed and hidden until the character speaks;
-- unregistering and anonymous are revisions without a nickname; at most
-- 20,000 second-hand identities are kept (the oldest heard dropped first) and
-- at most 1,000 changes (new, later, removed or disputed) accepted from one
-- peer a day, and 5,000 more it vouches it heard first-hand in the last day.
-- Staleness too (decision 0003): an identity keeps its
-- character's GUID once seen in the game (see) or passed on with it, and goes
-- stale, hidden until its full name speaks first-hand, when the name shows up
-- with another GUID. A forgotten character's second-hand copies are refused
-- (only the player's choice, nobody is told).
local _, ns = ...

local Memory = {}
Memory.__index = Memory
ns.Memory = Memory

Memory.MAX_SECOND_HAND = 20000
Memory.MAX_CHANGES_PER_PEER = 1000
-- Changes a peer vouches it heard first-hand in the last day, taken from it a
-- day besides its 1,000 (decision 0001).
Memory.MAX_VOUCHED_PER_PEER = 5000
Memory.BUCKETS = 128 -- of the digest, DIGITS each (BUCKETS * DIGITS = Protocol.DIGEST_LENGTH)

local DIGITS = 8 -- hexadecimal, a bucket of the digest

local DAY = 24 * 60 * 60
-- How old, at most, a vouched change may be (its revision) to count as vouched;
-- one ahead of the clock never does: no real change is.
Memory.VOUCHED_WINDOW = DAY
local HASH_MODULUS = 4294967296 -- 2^32: the hashes stay exact in a Lua number

-- Latin letters with accents, by code point ranges, and the letters they fold
-- to for a search: Latin-1 Supplement and Latin Extended-A, both cases.
local FOLDS = {
	{ 0xC0, 0xC5, "a" },
	{ 0xC6, 0xC6, "ae" },
	{ 0xC7, 0xC7, "c" },
	{ 0xC8, 0xCB, "e" },
	{ 0xCC, 0xCF, "i" },
	{ 0xD0, 0xD0, "d" },
	{ 0xD1, 0xD1, "n" },
	{ 0xD2, 0xD6, "o" },
	{ 0xD8, 0xD8, "o" },
	{ 0xD9, 0xDC, "u" },
	{ 0xDD, 0xDD, "y" },
	{ 0xDF, 0xDF, "ss" },
	{ 0xE0, 0xE5, "a" },
	{ 0xE6, 0xE6, "ae" },
	{ 0xE7, 0xE7, "c" },
	{ 0xE8, 0xEB, "e" },
	{ 0xEC, 0xEF, "i" },
	{ 0xF0, 0xF0, "d" },
	{ 0xF1, 0xF1, "n" },
	{ 0xF2, 0xF6, "o" },
	{ 0xF8, 0xF8, "o" },
	{ 0xF9, 0xFC, "u" },
	{ 0xFD, 0xFD, "y" },
	{ 0xFF, 0xFF, "y" },
	{ 0x100, 0x105, "a" },
	{ 0x106, 0x10D, "c" },
	{ 0x10E, 0x111, "d" },
	{ 0x112, 0x11B, "e" },
	{ 0x11C, 0x123, "g" },
	{ 0x124, 0x127, "h" },
	{ 0x128, 0x131, "i" },
	{ 0x132, 0x133, "ij" },
	{ 0x134, 0x135, "j" },
	{ 0x136, 0x138, "k" },
	{ 0x139, 0x142, "l" },
	{ 0x143, 0x14B, "n" },
	{ 0x14C, 0x151, "o" },
	{ 0x152, 0x153, "oe" },
	{ 0x154, 0x159, "r" },
	{ 0x15A, 0x161, "s" },
	{ 0x162, 0x167, "t" },
	{ 0x168, 0x173, "u" },
	{ 0x174, 0x175, "w" },
	{ 0x176, 0x178, "y" },
	{ 0x179, 0x17E, "z" },
	{ 0x17F, 0x17F, "s" },
}

-- The two-byte UTF-8 sequence of each folded letter, and its plain letters.
local FOLDED = {}
for _, range in ipairs(FOLDS) do
	for codePoint = range[1], range[2] do
		FOLDED[string.char(0xC0 + math.floor(codePoint / 64), 0x80 + codePoint % 64)] = range[3]
	end
end

-- Text as a search compares it: lower case and without accents. Other
-- alphabets are compared as they are.
local function fold(text)
	return (text:gsub("[\192-\223][\128-\191]", FOLDED):lower())
end

-- Whether a character's name or nickname contains the folded text.
local function matches(wanted, name, nickname)
	return fold(name):find(wanted, 1, true) or (nickname and fold(nickname):find(wanted, 1, true))
end

-- Text as a search compares it (fold), remembered for the session: a search
-- through the whole memory then folds each name and nickname once.
-- shortcut: never emptied, so it also holds nicknames since replaced; about
-- 4 MB for 20,000 identities. Empty it when the panel closes if memory matters.
local function cachedFold(self, text)
	local value = self.folds[text]
	if not value then
		value = fold(text)
		self.folds[text] = value
	end
	return value
end

-- Whether the folded text is in a character's name or nickname, as matches.
local function contains(self, wanted, name, nickname)
	return cachedFold(self, name):find(wanted, 1, true)
		or (nickname and cachedFold(self, nickname):find(wanted, 1, true))
end

-- Whether a character's name or nickname contains the text, ignoring case and
-- accents, as Memory:list matches.
function Memory.matches(text, name, nickname)
	return matches(fold(text), name, nickname) ~= nil
end

local function hash(text)
	local value = 5381
	for i = 1, #text do
		value = (value * 33 + text:byte(i)) % HASH_MODULUS
	end
	return value
end

local function bucketOf(name)
	return hash(name) % Memory.BUCKETS
end

-- Adds (sign 1) or takes out (sign -1) an identity's hash, with its revision
-- and nickname, in the sum of its bucket for the digest. A disputed identity
-- is left out. A stale one is not, so peers still holding the same old copy
-- match; nor is the GUID hashed, or peers that know it and peers that do not
-- would never match: neither changes a sum.
local function sum(self, name, known, sign)
	if known and not known.disputed then
		local bucket = bucketOf(name) + 1
		local value = hash(name .. "\n" .. known.revision .. "\n" .. (known.nickname or ""))
		self.sums[bucket] = (self.sums[bucket] + sign * value) % HASH_MODULUS
	end
end

-- Adds (or with held false, takes out) a name in the index of full names by
-- folded text. Two names rarely fold the same: then the index holds both, as
-- a set.
local function index(self, name, held)
	local key = fold(name)
	local indexed = self.byFolded[key]
	if held then
		if indexed == nil then
			self.byFolded[key] = name
		elseif type(indexed) == "table" then
			indexed[name] = true
		elseif indexed ~= name then
			self.byFolded[key] = { [indexed] = true, [name] = true }
		end
	elseif indexed == name then
		self.byFolded[key] = nil
	elseif type(indexed) == "table" then
		indexed[name] = nil
		local only = next(indexed)
		if next(indexed, only) == nil then
			self.byFolded[key] = only
		end
	end
end

-- Stores an identity (or nil to drop it), keeping the digest's sums, the
-- names of its bucket and, once built, the index of full names in step.
local function store(self, name, known)
	local before = self.identities[name]
	sum(self, name, before, -1)
	self.identities[name] = known
	sum(self, name, known, 1)
	self.names[bucketOf(name) + 1][name] = known and true or nil
	if self.byFolded and (before == nil) ~= (known == nil) then
		index(self, name, known ~= nil)
	end
end

-- Queues a second-hand identity to be dropped after the ones heard before it.
-- An entry stays live while the identity it holds is the one stored for its
-- name; once dead entries outnumber the live ones, the queue keeps the live
-- ones only, in order, so a long session of changes cannot grow it unbounded.
local function queue(self, name, known)
	self.queueEnd = self.queueEnd + 1
	self.queue[self.queueEnd] = { name = name, known = known }
	if self.queueEnd - self.queueStart + 1 > 2 * self.secondHand + 1000 then
		local live = {}
		for at = self.queueStart, self.queueEnd do
			local entry = self.queue[at]
			if self.identities[entry.name] == entry.known then
				live[#live + 1] = entry
			end
		end
		self.queue, self.queueStart, self.queueEnd = live, 1, #live
	end
end

-- saved: the table Memory keeps its identities in (MnemosyneDB.memory), and
-- how many second-hand changes each peer brought today. Counts older
-- than a day are let go here.
-- clock: returns the server time, in seconds.
-- forgotten: the characters forgotten, as a set of full names
-- (MnemosyneDB.forgotten); an empty one when left out. A name matches it
-- ignoring case and accents, as a player may type it.
function Memory.new(saved, clock, forgotten)
	saved.identities = saved.identities or {}
	saved.newFrom = saved.newFrom or {} -- counts every change, not only new ones (key kept)
	local now = clock()
	for peer, counted in pairs(saved.newFrom) do
		if now - counted.since >= DAY then
			saved.newFrom[peer] = nil
		end
	end
	local self = setmetatable({
		identities = saved.identities, -- written only through store, which keeps names in step
		newFrom = saved.newFrom,
		forgottenNames = forgotten or {},
		folded = {}, -- each forgotten name, by its folded text
		secondHand = 0,
		clock = clock,
		sums = {},
		names = {}, -- bucket -> set of the names held in it, so missing hashes no name
		folds = {}, -- text -> its folded text, for searches (cachedFold)
		byFolded = nil, -- folded text -> full name held (or a set of them), built on the first fullName
		queue = {},
		queueStart = 1,
		queueEnd = 0,
	}, Memory)
	for bucket = 1, Memory.BUCKETS do
		self.sums[bucket] = 0
		self.names[bucket] = {}
	end
	for name in pairs(self.forgottenNames) do
		if type(name) == "string" then -- the saved file may have been edited by hand
			self.folded[fold(name)] = name
		end
	end
	for name, known in pairs(saved.identities) do
		sum(self, name, known, 1)
		self.names[bucketOf(name) + 1][name] = true
		if not known.firstHand then
			self.secondHand = self.secondHand + 1
			queue(self, name, known)
		end
	end
	table.sort(self.queue, function(a, b)
		return a.known.heard < b.known.heard
	end)
	return self
end

-- Counts one second-hand change from a peer, toward its 5,000 vouched ones
-- while they last when vouched, else its 1,000. Returns false once the peer
-- brought all it may of the day.
local function countChange(self, peer, now, vouched)
	local counted = self.newFrom[peer]
	if not counted or now - counted.since >= DAY then
		counted = { since = now, count = 0 }
		self.newFrom[peer] = counted
	end
	if vouched and (counted.vouched or 0) < Memory.MAX_VOUCHED_PER_PEER then
		counted.vouched = (counted.vouched or 0) + 1
		return true
	end
	if counted.count >= Memory.MAX_CHANGES_PER_PEER then
		return false
	end
	counted.count = counted.count + 1
	return true
end

-- Drops the second-hand identity heard the longest ago: the first in the queue
-- still live (its identity still the one stored). heard only grows, so the queue
-- stays in the order heard.
local function dropOldest(self)
	while true do
		local oldest = self.queue[self.queueStart]
		self.queue[self.queueStart] = nil
		self.queueStart = self.queueStart + 1
		if self.identities[oldest.name] == oldest.known then
			store(self, oldest.name, nil)
			self.secondHand = self.secondHand - 1
			return
		end
	end
end

local function hearSecondHand(self, name, heard, known)
	local now = self.clock()
	-- A revision is the server time of the change: one far ahead is forged, and
	-- no real change could ever beat it.
	if heard.revision > now + DAY then
		return false
	end
	if known then
		if known.firstHand or known.stale or known.revision > heard.revision then
			return false
		elseif known.revision == heard.revision and (known.disputed or known.nickname == heard.nickname) then
			return false
		end
	end
	-- Every change counts, not only new identities: else a peer could rewrite
	-- all it was ever told, with no limit.
	-- Vouched only lately: a revision older than a day, or ahead of the clock, counts as any other.
	local age = now - heard.revision
	if not countChange(self, heard.source, now, heard.vouched and age >= 0 and age <= Memory.VOUCHED_WINDOW) then
		return false
	end
	if not known then
		if self.secondHand >= Memory.MAX_SECOND_HAND then
			dropOldest(self)
		end
		self.secondHand = self.secondHand + 1
	elseif known.revision == heard.revision then
		sum(self, name, known, -1)
		known.disputed = true
		return true, "disputed"
	end
	local stored = {
		nickname = heard.nickname,
		revision = heard.revision,
		firstHand = false,
		source = heard.source,
		heard = now,
		-- The GUID held stays, whatever the peer says: if the name changed hands,
		-- better hidden until it speaks than shown on another character, and a
		-- forged GUID never stops it going stale.
		guid = known and known.guid or heard.guid,
	}
	store(self, name, stored)
	queue(self, name, stored)
	return true
end

-- Hears an identity: heard.nickname and heard.revision, or heard.revision
-- alone when the character unregistered or is anonymous; heard.source, the
-- peer that passed it on, and heard.guid, the GUID it passed on with it, when
-- it is second-hand. Returns true when the identity changed, and "disputed"
-- after it when it became disputed.
--
-- First-hand (from the character itself), it replaces any second-hand copy
-- and a stale identity, and a revision older than the first-hand one held is
-- ignored. Second-hand, it never replaces a first-hand or stale identity, a
-- later revision wins (but not one more than a day ahead of the clock), and the
-- same revision with another nickname makes the identity disputed.
function Memory:hear(name, heard)
	local known = self.identities[name]
	if heard.source and self:isForgotten(name) then
		return false
	elseif heard.source then
		return hearSecondHand(self, name, heard, known)
	end
	if known and known.firstHand and not known.stale and known.revision > heard.revision then
		return false
	end
	if known and not known.firstHand then
		self.secondHand = self.secondHand - 1
	end
	-- The GUID stays, even a peer's or one from before a new registration: if it
	-- is not this character's, the identity goes stale when the character is
	-- seen, and is asked as a stranger, until it speaks first-hand again.
	store(self, name, {
		nickname = heard.nickname,
		revision = heard.revision,
		firstHand = true,
		heard = self.clock(),
		guid = known and known.guid,
	})
	return true
end

-- Sees a character's GUID where the game gives it reliably: a chat line or a
-- group member. An identity without a GUID takes it. One held with another
-- GUID goes stale: its full name now belongs to another character (the old
-- one was deleted or renamed), so it is hidden until the name speaks
-- first-hand, and keeps the new GUID for that character. Neither changes the
-- digest's sums (sum), so the identity is changed in place, keeping its place
-- in the drop queue.
function Memory:see(name, guid)
	local known = self.identities[name]
	if known and known.guid ~= guid then
		if known.guid then
			known.stale = true
		end
		known.guid = guid
	end
end

-- Whether an identity is passed on (and shows, with a nickname): neither
-- disputed nor stale.
local function passesOn(known)
	return not known.disputed and not known.stale
end

-- Whether an identity shows: it has a nickname and is passed on.
local function shows(known)
	return known and known.nickname and passesOn(known)
end

-- Recalls the identity of a character: { nickname, revision, firstHand,
-- source, heard }, a copy, or nil when its player's nickname is not known, is
-- disputed or is stale.
function Memory:recall(name)
	local known = self.identities[name]
	if not shows(known) then
		return nil
	end
	return {
		nickname = known.nickname,
		revision = known.revision,
		firstHand = known.firstHand,
		source = known.source,
		heard = known.heard,
	}
end

-- Finds the identities whose character name or nickname contains the text,
-- ignoring case and accents. Returns a list of { name, nickname, revision,
-- firstHand, heard }, copies, sorted by name; every identity for an empty text.
function Memory:search(text)
	local wanted = cachedFold(self, text)
	local found = {}
	for name, known in pairs(self.identities) do
		if shows(known) and contains(self, wanted, name, known.nickname) then
			local identity = self:recall(name)
			identity.name = name
			found[#found + 1] = identity
		end
	end
	table.sort(found, function(a, b)
		return a.name < b.name
	end)
	return found
end

-- Lists, for the settings panel, every identity with a nickname, disputed
-- ones included (marked disputed) and stale ones left out (hidden, as recall
-- hides them), and every forgotten character (marked
-- forgotten, with its identity if heard first-hand since), whose name or
-- nickname contains the text, ignoring case and accents. Returns a list of
-- { name, nickname, firstHand, source, heard, disputed, forgotten }, copies,
-- sorted by name, and how many it found.
-- max: at most this many entries, the first by name (all when left out).
-- keep(name, identity, forgotten): whether to list one, identity nil for a
-- forgotten character not held; all when left out. Only those count.
function Memory:list(text, max, keep)
	local wanted = cachedFold(self, text)
	local found, total = {}, 0
	local function add(name, known)
		local isForgotten = self.forgottenNames[name] ~= nil
		if keep and not keep(name, known, isForgotten) then
			return
		end
		total = total + 1
		local last = found[#found]
		if max and #found >= max and not (last and name < last.name) then
			return
		end
		local entry = { name = name, forgotten = isForgotten or nil }
		if known then
			entry.nickname, entry.firstHand, entry.source = known.nickname, known.firstHand, known.source
			entry.heard, entry.disputed = known.heard, known.disputed
		end
		if not max then
			found[#found + 1] = entry
			return
		end
		-- Kept sorted, and at most max long: a search of the whole memory sorts
		-- only the rows it shows.
		local at = #found + 1
		while at > 1 and name < found[at - 1].name do
			at = at - 1
		end
		table.insert(found, at, entry)
		found[max + 1] = nil
	end
	local function listed(name)
		local known = self.identities[name]
		return known and known.nickname and not known.stale and contains(self, wanted, name, known.nickname)
	end
	for name, known in pairs(self.identities) do
		if listed(name) then
			add(name, known)
		end
	end
	for name in pairs(self.forgottenNames) do
		if not listed(name) and contains(self, wanted, name) then
			add(name, nil)
		end
	end
	if not max then
		table.sort(found, function(a, b)
			return a.name < b.name
		end)
	end
	return found, total
end

-- How many identities show (a nickname, neither disputed nor stale); only
-- first-hand ones when firstHandOnly is true.
function Memory:count(firstHandOnly)
	local count = 0
	for _, known in pairs(self.identities) do
		if shows(known) and not (firstHandOnly and known.source) then
			count = count + 1
		end
	end
	return count
end

-- Whether it heard a character itself (first-hand): a nickname, or that the
-- character has none (it unregistered or is anonymous). Not a stale identity:
-- the character that took its name is a stranger.
function Memory:knows(name)
	local known = self.identities[name]
	return known ~= nil and known.firstHand == true and not known.stale
end

-- The digest of the memory, for a sync (decision 0002): each identity, hashed
-- with its revision and nickname, summed in the bucket of its character's
-- name; 8 hexadecimal digits a bucket. How it was heard does not count, so two
-- memories holding the same identities give the same digest. A disputed
-- identity is left out, as it is never passed on. The sums are kept as the
-- identities change (store), so a digest only writes them out.
function Memory:digest()
	local digits = {}
	for bucket, total in ipairs(self.sums) do
		-- Two halves: string.format's %x takes at most 32-bit signed integers on some builds.
		digits[bucket] = string.format("%04x%04x", math.floor(total / 65536), total % 65536)
	end
	return table.concat(digits)
end

-- What to pass on to a peer, from its digest: the names of every identity in a
-- bucket whose digest differs from this memory's, removals included; never a
-- disputed or stale one. Names only, so a whole memory costs no table each:
-- passOn gives what to send of the ones chosen. The peer keeps what is newer
-- than what it holds.
function Memory:missing(digest)
	local mine = self:digest()
	local found = {}
	for bucket = 1, Memory.BUCKETS do
		local first, last = (bucket - 1) * DIGITS + 1, bucket * DIGITS
		if mine:sub(first, last) ~= digest:sub(first, last) then
			for name in pairs(self.names[bucket]) do
				if passesOn(self.identities[name]) then
					found[#found + 1] = name
				end
			end
		end
	end
	return found
end

-- What to pass on of a character's identity: { name, nickname, revision, guid },
-- a removal without a nickname, guid when known; nil when it is not passed on
-- (not held, disputed or stale).
function Memory:passOn(name)
	local known = self.identities[name]
	if known and passesOn(known) then
		return { name = name, nickname = known.nickname, revision = known.revision, guid = known.guid }
	end
end

-- Forgets a character (its full name in any case, accents or not): drops its
-- identity and refuses its second-hand copies
-- until unforgotten; first-hand ones still get through. With no identity
-- left, it is out of the digest and never passed on; once heard first-hand,
-- it is passed on like any other. Returns false when it was already
-- forgotten.
-- shortcut: a peer that still holds it keeps that digest bucket differing, so
-- each sync with it (at most every 6 hours) resends the bucket, about 1/128 of
-- the memory, to be refused or already held; keep a hidden copy in the digest
-- if players forget many characters.
function Memory:forget(name)
	name = self:fullName(name) or name
	if self:isForgotten(name) then
		return false
	end
	self.forgottenNames[name] = true
	self.folded[fold(name)] = name
	local known = self.identities[name]
	if known and not known.firstHand then
		self.secondHand = self.secondHand - 1
	end
	store(self, name, nil)
	return true
end

-- Lets a forgotten character's second-hand copies in again. Returns false
-- when it was not forgotten.
function Memory:unforget(name)
	local folded = fold(name)
	local forgotten = self.folded[folded]
	if not forgotten then
		return false
	end
	self.forgottenNames[forgotten] = nil
	self.folded[folded] = nil
	return true
end

-- The full name of a character held or forgotten, from the text a player
-- typed, ignoring case and accents; nil when none matches. The text itself
-- when held or forgotten as typed. The first call indexes the names held.
function Memory:fullName(text)
	if self.identities[text] or self.forgottenNames[text] then
		return text
	end
	if not self.byFolded then
		self.byFolded = {}
		for name in pairs(self.identities) do
			index(self, name, true)
		end
	end
	local held = self.byFolded[fold(text)]
	if type(held) == "table" then
		held = next(held)
	end
	return held or self.folded[fold(text)]
end

-- Whether the player forgot the character.
function Memory:isForgotten(name)
	return self.folded[fold(name)] ~= nil
end

-- The forgotten characters' full names, sorted.
function Memory:forgotten()
	local names = {}
	for name in pairs(self.forgottenNames) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end
