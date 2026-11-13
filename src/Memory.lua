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
-- peer a day. Staleness and forgetting join it later, behind the same hear
-- and recall.
local _, ns = ...

local Memory = {}
Memory.__index = Memory
ns.Memory = Memory

Memory.MAX_SECOND_HAND = 20000
Memory.MAX_CHANGES_PER_PEER = 1000
Memory.BUCKETS = 128 -- of the digest, DIGITS each (BUCKETS * DIGITS = Protocol.DIGEST_LENGTH)

local DIGITS = 8 -- hexadecimal, a bucket of the digest

local DAY = 24 * 60 * 60
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
-- is left out.
local function sum(self, name, known, sign)
	if known and not known.disputed then
		local bucket = bucketOf(name) + 1
		local value = hash(name .. "\n" .. known.revision .. "\n" .. (known.nickname or ""))
		self.sums[bucket] = (self.sums[bucket] + sign * value) % HASH_MODULUS
	end
end

-- Stores an identity (or nil to drop it), keeping the digest's sums in step.
local function store(self, name, known)
	sum(self, name, self.identities[name], -1)
	self.identities[name] = known
	sum(self, name, known, 1)
end

-- Queues a second-hand identity to be dropped after the ones heard before it.
-- An entry stays live while the identity it holds is the one stored for its
-- name; once stale entries outnumber the live ones, the queue keeps the live
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
function Memory.new(saved, clock)
	saved.identities = saved.identities or {}
	saved.newFrom = saved.newFrom or {} -- counts every change, not only new ones (key kept)
	local now = clock()
	for peer, counted in pairs(saved.newFrom) do
		if now - counted.since >= DAY then
			saved.newFrom[peer] = nil
		end
	end
	local self = setmetatable({
		identities = saved.identities,
		newFrom = saved.newFrom,
		secondHand = 0,
		clock = clock,
		sums = {},
		queue = {},
		queueStart = 1,
		queueEnd = 0,
	}, Memory)
	for bucket = 1, Memory.BUCKETS do
		self.sums[bucket] = 0
	end
	for name, known in pairs(saved.identities) do
		sum(self, name, known, 1)
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

-- Counts one second-hand change from a peer. Returns false once the peer
-- brought its 1,000 of the day.
local function countChange(self, peer, now)
	local counted = self.newFrom[peer]
	if not counted or now - counted.since >= DAY then
		counted = { since = now, count = 0 }
		self.newFrom[peer] = counted
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
		if known.firstHand or known.revision > heard.revision then
			return false
		elseif known.revision == heard.revision and (known.disputed or known.nickname == heard.nickname) then
			return false
		end
	end
	-- Every change counts, not only new identities: else a peer could rewrite
	-- all it was ever told, with no limit.
	if not countChange(self, heard.source, now) then
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
		return true
	end
	local stored = {
		nickname = heard.nickname,
		revision = heard.revision,
		firstHand = false,
		source = heard.source,
		heard = now,
	}
	store(self, name, stored)
	queue(self, name, stored)
	return true
end

-- Hears an identity: heard.nickname and heard.revision, or heard.revision
-- alone when the character unregistered or is anonymous; heard.source, the
-- peer that passed it on, when it is second-hand. Returns true when the
-- identity changed.
--
-- First-hand (from the character itself), it replaces any second-hand copy,
-- and a revision older than the first-hand one held is ignored. Second-hand,
-- it never replaces a first-hand identity, a later revision wins (but not one
-- more than a day ahead of the clock), and the same revision with another
-- nickname makes the identity disputed.
function Memory:hear(name, heard)
	local known = self.identities[name]
	if heard.source then
		return hearSecondHand(self, name, heard, known)
	end
	if known and known.firstHand and known.revision > heard.revision then
		return false
	end
	if known and not known.firstHand then
		self.secondHand = self.secondHand - 1
	end
	store(self, name, {
		nickname = heard.nickname,
		revision = heard.revision,
		firstHand = true,
		heard = self.clock(),
	})
	return true
end

-- Whether an identity shows: it has a nickname and is not disputed.
local function shows(known)
	return known and known.nickname and not known.disputed
end

-- Recalls the identity of a character: { nickname, revision, firstHand,
-- source, heard }, a copy, or nil when its player's nickname is not known or
-- is disputed.
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
	local wanted = fold(text)
	local found = {}
	for name, known in pairs(self.identities) do
		if shows(known) and (fold(name):find(wanted, 1, true) or fold(known.nickname):find(wanted, 1, true)) then
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

-- How many identities show (a nickname, not disputed); only first-hand ones
-- when firstHandOnly is true.
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
-- character has none (it unregistered or is anonymous).
function Memory:knows(name)
	local known = self.identities[name]
	return known ~= nil and known.firstHand == true
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

-- What to pass on to a peer, from its digest: every identity in a bucket whose
-- digest differs from this memory's, as { name, nickname, revision }, removals
-- included; never a disputed one. The peer keeps what is newer than what it
-- holds.
function Memory:missing(digest)
	local mine = self:digest()
	local differs = {}
	for bucket = 0, Memory.BUCKETS - 1 do
		local first = bucket * DIGITS + 1
		differs[bucket] = mine:sub(first, first + DIGITS - 1) ~= digest:sub(first, first + DIGITS - 1)
	end
	local found = {}
	for name, known in pairs(self.identities) do
		if not known.disputed and differs[bucketOf(name)] then
			found[#found + 1] = { name = name, nickname = known.nickname, revision = known.revision }
		end
	end
	return found
end
