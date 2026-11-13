-- Memory: every identity this account holds, keyed by the character's full
-- name as the server gives it ("First Last", decision 0003). Pure: it takes
-- its saved table and the clock (the server time) as arguments (decision 0004).
--
-- First form: first-hand identities only. Second-hand identities, disputes,
-- staleness, forgetting and the limits of decision 0001 join it later, behind
-- the same hear and recall.
local _, ns = ...

local Memory = {}
Memory.__index = Memory
ns.Memory = Memory

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

-- saved: the table Memory keeps its identities in (MnemosyneDB.memory).
-- clock: returns the server time, in seconds.
function Memory.new(saved, clock)
	saved.identities = saved.identities or {}
	return setmetatable({ identities = saved.identities, clock = clock }, Memory)
end

-- Hears what a character said about itself (first-hand): heard.nickname and
-- heard.revision, or heard.revision alone when it unregistered. A revision
-- older than the one held is ignored. Returns true when the identity changed.
function Memory:hear(name, heard)
	local known = self.identities[name]
	if known and known.revision > heard.revision then
		return false
	end
	self.identities[name] = {
		nickname = heard.nickname,
		revision = heard.revision,
		firstHand = true,
		heard = self.clock(),
	}
	return true
end

-- Recalls the identity of a character: { nickname, revision, firstHand, heard },
-- a copy, or nil when its player's nickname is not known.
function Memory:recall(name)
	local known = self.identities[name]
	if not known or not known.nickname then
		return nil
	end
	return { nickname = known.nickname, revision = known.revision, firstHand = known.firstHand, heard = known.heard }
end

-- Finds the identities whose character name or nickname contains the text,
-- ignoring case and accents. Returns a list of { name, nickname, revision,
-- firstHand, heard }, copies, sorted by name; every identity for an empty text.
function Memory:search(text)
	local wanted = fold(text)
	local found = {}
	for name, known in pairs(self.identities) do
		if known.nickname and (fold(name):find(wanted, 1, true) or fold(known.nickname):find(wanted, 1, true)) then
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

-- How many identities it holds.
function Memory:count()
	local count = 0
	for _, known in pairs(self.identities) do
		if known.nickname then
			count = count + 1
		end
	end
	return count
end
