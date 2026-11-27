-- Professions: every profession this account holds, first-hand and
-- second-hand, keyed by the character's full name and the profession's skill
-- line ID (decision 0008). Pure: it takes its saved table, the clock (the
-- server time), the memory, this account's characters and the settings as
-- arguments (decision 0004).
--
-- Each profession follows the rules of the identities (decision 0001): a
-- first-hand one always wins; among second-hand copies the later revision
-- wins; the same revision with other content is disputed and hidden; a
-- removal (no level) is a revision too. It goes stale when its full name
-- shows up with another GUID, hidden until the character shares first-hand.
-- Kept only for this account's characters, and for characters seen on a guild
-- roster or online as a friend's in the last 30 days; others are dropped
-- quietly. Second-hand ones are refused and dropped while the character is
-- forgotten (a first-hand one still gets through, as for identities) or while
-- its identity is held as a removal (anonymous or unregistered), so no peer
-- can link an anonymous character to its professions; first-hand ones too
-- while that removal is not disputed. Only the game's
-- skill lines are kept. At most 2,000 second-hand changes a day from one
-- peer, first-hand ones aside.
local _, ns = ...

local Protocol = ns.Protocol

local Professions = {}
Professions.__index = Professions
ns.Professions = Professions

local DAY = 24 * 60 * 60
local HASH_MODULUS = 4294967296 -- 2^32: the hashes stay exact in a Lua number
local BUCKETS = Protocol.DIGEST_LENGTH / 8 -- 8 hexadecimal digits a bucket

Professions.MAX_CHANGES_PER_PEER = 2000
-- The game's professions, by skill line ID: any other heard is dropped, so a
-- peer cannot grow one character without end. Each is "crafting", "gathering"
-- (both primary) or "secondary". Forever has no Jewelcrafting, Inscription or
-- Archaeology.
Professions.SKILL_LINES = {
	[171] = "crafting", -- Alchemy
	[164] = "crafting", -- Blacksmithing
	[333] = "crafting", -- Enchanting
	[202] = "crafting", -- Engineering
	[165] = "crafting", -- Leatherworking
	[197] = "crafting", -- Tailoring
	[182] = "gathering", -- Herbalism
	[186] = "gathering", -- Mining
	[393] = "gathering", -- Skinning
	[185] = "secondary", -- Cooking
	[129] = "secondary", -- First Aid
	[356] = "secondary", -- Fishing
}
Professions.KEPT_FOR = 30 * DAY -- after a character was last seen on a roster or as a friend's
Professions.MAX_SYNC_BYTES = 100000 -- of professions a sync passes on

-- saved: the table Professions keeps its professions in (MnemosyneDB.professions).
-- clock: returns the server time, in seconds.
-- memory: the Memory, for forgotten characters and identities held as removals.
-- characters: this account's characters (Self): their professions are read
-- from it, and never adopted from peers.
-- settings: the saved settings; settings.passOn switches passing on what was
-- heard from others (this account's characters' professions always go).
-- recipeSkillLine: returns the skill line the game places a recipe ID in, or
-- nil when it cannot; peers' recipes placed in another profession are dropped.
function Professions.new(saved, clock, memory, characters, settings, recipeSkillLine)
	saved.held = saved.held or {} -- name -> { guid, own, skills = { [skillLine] = profession } }
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
		recipeSkillLine = recipeSkillLine or function() end,
		roster = {}, -- the current guild roster, a set, for this session
		changes = 0, -- how many changes were heard this session: the window redraws when it moves
		hashes = setmetatable({}, { __mode = "k" }), -- profession -> its hash, computed once
	}, Professions)
end

-- Whether a recipe belongs to a profession (a skill line), from the skill line
-- the game places it in: yes unless that is another of the game's skill lines,
-- so a recipe the game cannot place (nil, or a skill line it has no
-- profession for) is kept.
function Professions.belongsTo(lookedUp, skillLine)
	return not Professions.SKILL_LINES[lookedUp] or lookedUp == skillLine
end

-- A peer's recipes of a profession without those the game places in another:
-- 1.1.x saved a window's recipes under the profession opened before. The
-- same table when none is dropped.
local function ownRecipes(self, skillLine, recipes)
	if not recipes then
		return nil
	end
	local kept = {}
	for _, recipe in ipairs(recipes) do
		if Professions.belongsTo(self.recipeSkillLine(recipe), skillLine) then
			kept[#kept + 1] = recipe
		end
	end
	return #kept < #recipes and kept or recipes
end

local function hash(text)
	local value = 5381
	for i = 1, #text do
		value = (value * 33 + text:byte(i)) % HASH_MODULUS
	end
	return value
end

-- What a profession says, as one text: two copies say the same when it matches.
local function content(name, skillLine, profession)
	local recipes = profession.recipes and table.concat(profession.recipes, ",") or "-"
	return table.concat({
		name,
		skillLine,
		profession.revision,
		profession.level or "",
		profession.maxLevel or "",
		profession.level and recipes or "",
	}, "\n")
end

local function hashOf(self, name, skillLine, profession)
	local value = self.hashes[profession]
	if not value then
		value = hash(content(name, skillLine, profession))
		self.hashes[profession] = value
	end
	return value
end

local function isOwn(self, name)
	local character = self.held[name]
	return (character and character.own) or self.characters:registration(name) ~= nil
end

-- Whether a character was seen on a roster or as a friend's in the last 30 days.
local function seenLately(self, name, now)
	local seen = self.seen[name]
	return seen ~= nil and now - seen < Professions.KEPT_FOR
end

-- Whether professions of a character are kept: this account's, or seen lately.
local function keeps(self, name, now)
	return isOwn(self, name) or seenLately(self, name, now)
end

-- Whether a character's profession heard first-hand or not is refused:
-- second-hand while the character is forgotten or its identity is held as a
-- removal (disputed or stale too); first-hand while that removal is not
-- disputed. Any peer can forge a removal that disputes a nickname: it never
-- keeps out what the character shares itself, which for an anonymous
-- character is only removals (Self:professions).
local function isRefused(self, name, firstHand)
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
	if counted.count >= Professions.MAX_CHANGES_PER_PEER then
		return false
	end
	counted.count = counted.count + 1
	return true
end

-- Hears a profession from a peer, as Protocol reads it: { name, skillLine,
-- revision, level, maxLevel, recipes, guid }, a removal without a level.
-- First-hand when the peer is the character itself. Returns true when it
-- changed what is held.
function Professions:hear(peer, heard)
	local now, name, skillLine = self.clock(), heard.name, heard.skillLine
	local firstHand = name == peer
	if
		not Professions.SKILL_LINES[skillLine]
		or heard.revision > now + DAY
		or isOwn(self, name)
		or not keeps(self, name, now)
		or isRefused(self, name, firstHand)
	then
		return false
	end
	heard = {
		name = name,
		skillLine = skillLine,
		revision = heard.revision,
		level = heard.level,
		maxLevel = heard.maxLevel,
		recipes = ownRecipes(self, skillLine, heard.recipes),
		guid = heard.guid,
	}
	local character = self.held[name]
	local known = character and character.skills[skillLine]
	local same = known
		and not known.disputed
		and hashOf(self, name, skillLine, known) == hashOf(self, name, skillLine, heard)
	if firstHand then
		if known and known.firstHand and not known.stale and (known.revision > heard.revision or same) then
			return false
		end
	else
		if known and (known.firstHand or known.stale or known.revision > heard.revision) then
			return false
		elseif known and known.revision == heard.revision and (known.disputed or same) then
			return false
		elseif not countChange(self, peer, now) then
			return false
		elseif known and known.revision == heard.revision then
			character.skills[skillLine] = { revision = known.revision, disputed = true, heard = now }
			self.changes = self.changes + 1
			return true
		end
	end
	if not character then
		character = { skills = {} }
		self.held[name] = character
	end
	-- The GUID held stays, whatever the peer says (as Memory keeps it).
	character.guid = character.guid or heard.guid
	character.skills[skillLine] = {
		revision = heard.revision,
		level = heard.level,
		maxLevel = heard.level and heard.maxLevel,
		recipes = heard.level and heard.recipes,
		firstHand = firstHand,
		source = not firstHand and peer or nil,
		heard = now,
	}
	self.changes = self.changes + 1
	return true
end

-- Sees a character's GUID (a chat line, a group member): a character held
-- without one takes it; one held with another goes stale, every profession of
-- it hidden until the character shares first-hand.
function Professions:see(name, guid)
	local character = self.held[name]
	if character and character.guid ~= guid then
		if character.guid then
			for _, profession in pairs(character.skills) do
				profession.stale = true
			end
		end
		character.guid = guid
	end
end

-- Drops quietly the professions no longer kept: of characters neither seen on
-- a roster nor as a friend's in the last 30 days, and those refused
-- (isRefused). Drops from the peers' professions held the recipes the game
-- places in another profession.
function Professions:prune()
	local now = self.clock()
	for name, seenAt in pairs(self.seen) do
		if now - seenAt >= Professions.KEPT_FOR then
			self.seen[name] = nil
		end
	end
	for name, character in pairs(self.held) do
		if not character.own then
			if not keeps(self, name, now) then
				self.held[name] = nil
			else
				for skillLine, profession in pairs(character.skills) do
					if isRefused(self, name, profession.firstHand) then
						character.skills[skillLine] = nil
					end
				end
				if not next(character.skills) then
					self.held[name] = nil
				end
			end
			for skillLine, profession in pairs(character.skills) do
				local recipes = ownRecipes(self, skillLine, profession.recipes)
				if recipes ~= profession.recipes then
					profession.recipes = recipes
					self.hashes[profession] = nil
				end
			end
		end
	end
end

-- Sees the friends' characters online and the guild roster, as Client reads
-- them (arrays of full names), then drops what is no longer kept. The roster
-- also says, for this session, which peers are guildmates and whose
-- professions they may keep.
function Professions:seeLists(friends, roster)
	local now = self.clock()
	for _, name in ipairs(friends) do
		self.seen[name] = now
	end
	self.roster = {}
	for _, name in ipairs(roster) do
		self.seen[name] = now
		self.roster[name] = true
	end
	self:prune()
end

-- Reads this account's characters' professions, as a sync starts: stamps each
-- character's (a new revision for what changed since its last one), then keeps
-- them first-hand. Then drops what is no longer kept.
function Professions:prepare()
	local names = {}
	for _, character in ipairs(self.characters:list("")) do
		names[character.name] = true
	end
	for name, character in pairs(self.held) do
		if character.own then
			names[name] = true -- unregistered since: its removals still go
		end
	end
	local now = self.clock()
	for name in pairs(names) do
		self.characters:stampProfessions(name)
		local character = self.held[name] or { skills = {} }
		character.own = true
		self.held[name] = character
		for _, profession in ipairs(self.characters:professions(name)) do
			local known = character.skills[profession.skillLine]
			if
				not known
				or hashOf(self, name, profession.skillLine, known)
					~= hashOf(self, name, profession.skillLine, profession)
			then
				character.skills[profession.skillLine] = {
					revision = profession.revision,
					level = profession.level,
					maxLevel = profession.maxLevel,
					recipes = profession.recipes,
					firstHand = true,
					heard = now,
				}
			end
		end
	end
	self:prune()
end

-- Whether a character's professions go to a peer, or come from it: this
-- account's characters' to a peer seen lately (on the roster or a friend),
-- which keeps them; to a guildmate, also the roster's. Passing on is left
-- aside, so both sides' digests compare the same set: Professions:answer
-- leaves the roster's out while it is off.
local function goesTo(self, peer, name, character, now)
	if character.own then
		return seenLately(self, peer, now)
	end
	return (self.roster[peer] and self.roster[name]) or false
end

local function bucketOf(name)
	return hash(name) % BUCKETS + 1
end

-- The sums of the digest for a peer, and the names in each bucket: every
-- profession that goes to it, disputed ones left out.
local function sums(self, peer)
	local now, totals, names = self.clock(), {}, {}
	for bucket = 1, BUCKETS do
		totals[bucket], names[bucket] = 0, {}
	end
	for name, character in pairs(self.held) do
		if goesTo(self, peer, name, character, now) then
			local bucket = bucketOf(name)
			names[bucket][#names[bucket] + 1] = name
			for skillLine, profession in pairs(character.skills) do
				if not profession.disputed then
					totals[bucket] = (totals[bucket] + hashOf(self, name, skillLine, profession)) % HASH_MODULUS
				end
			end
		end
	end
	return totals, names
end

local function writeDigest(totals)
	local digits = {}
	for bucket, total in ipairs(totals) do
		digits[bucket] = string.format("%04x%04x", math.floor(total / 65536), total % 65536)
	end
	return table.concat(digits)
end

-- The digest of what goes to a peer, for a sync: each profession hashed with
-- what it says, summed in the bucket of its character's name.
function Professions:digest(peer)
	return writeDigest((sums(self, peer)))
end

-- What to pass on to a peer, from its digest: the professions that go to it,
-- in buckets whose digest differs, never a disputed or stale one, and only
-- this account's characters' while passing on is off; at most
-- 100 KB, the first-hand ones changed in the past day first, the latest
-- first, then the rest from a point that moves with the clock. Each is
-- { name, skillLine, revision, level, maxLevel, recipes, guid }, a removal
-- without a level.
function Professions:answer(peer, digest)
	local now = self.clock()
	local totals, names = sums(self, peer)
	local mine = writeDigest(totals)
	local fresh, rest = {}, {}
	for bucket = 1, BUCKETS do
		local first, last = (bucket - 1) * 8 + 1, bucket * 8
		if mine:sub(first, last) ~= digest:sub(first, last) then
			for _, name in ipairs(names[bucket]) do
				local character = self.held[name]
				local passes = character.own or self.settings.passOn
				for skillLine, profession in pairs(character.skills) do
					if passes and not profession.disputed and not profession.stale then
						local passed = {
							name = name,
							skillLine = skillLine,
							revision = profession.revision,
							level = profession.level,
							maxLevel = profession.maxLevel,
							recipes = profession.recipes,
							guid = character.guid,
						}
						local age = now - profession.revision
						if profession.firstHand and age >= 0 and age <= DAY then
							fresh[#fresh + 1] = passed
						else
							rest[#rest + 1] = passed
						end
					end
				end
			end
		end
	end
	table.sort(fresh, function(a, b)
		return a.revision > b.revision
	end)
	for i = 1, #rest do
		fresh[#fresh + 1] = rest[(now + i) % #rest + 1]
	end
	local chosen, bytes = {}, 0
	for _, passed in ipairs(fresh) do
		bytes = bytes + #Protocol.writeProfession(passed) + 1
		if bytes > Professions.MAX_SYNC_BYTES then
			break
		end
		chosen[#chosen + 1] = passed
	end
	return chosen
end

-- Every profession that shows, sorted by character name then skill line:
-- { name, skillLine, level, maxLevel, recipes, revision, firstHand, source,
-- heard, own }, copies; a disputed one as { name, skillLine, disputed } only.
-- This account's characters' show as read now (Self), registered or not,
-- shared or not, without a revision; never their stamped copies.
-- Removals, stale ones and those refused (isRefused) are left out.
function Professions:list()
	local found, mine = {}, {}
	for _, name in ipairs(self.characters:withProfessions()) do
		mine[name] = true
		for _, profession in ipairs(self.characters:currentProfessions(name)) do
			profession.name, profession.firstHand, profession.own = name, true, true
			found[#found + 1] = profession
		end
	end
	for name, character in pairs(self.held) do
		if not (character.own or mine[name]) then
			for skillLine, profession in pairs(character.skills) do
				-- A refused copy shows nowhere.
				local refused = isRefused(self, name, profession.firstHand)
				if profession.disputed and not refused then
					found[#found + 1] = { name = name, skillLine = skillLine, disputed = true }
				elseif profession.level and not profession.stale and not refused then
					local recipes
					if profession.recipes then
						recipes = {}
						for i, recipe in ipairs(profession.recipes) do
							recipes[i] = recipe
						end
					end
					found[#found + 1] = {
						name = name,
						skillLine = skillLine,
						level = profession.level,
						maxLevel = profession.maxLevel,
						recipes = recipes,
						revision = profession.revision,
						firstHand = profession.firstHand,
						source = profession.source,
						heard = profession.heard,
					}
				end
			end
		end
	end
	table.sort(found, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.skillLine < b.skillLine
	end)
	return found
end

-- Who knows each recipe of a profession (a skill line ID), among those that
-- show: { recipe, knownBy = { { name, firstHand, source } } }, sorted by recipe
-- ID and knownBy by name.
function Professions:recipes(skillLine)
	local byRecipe, found = {}, {}
	for _, profession in ipairs(self:list()) do
		if profession.skillLine == skillLine and profession.recipes then
			for _, recipe in ipairs(profession.recipes) do
				local entry = byRecipe[recipe]
				if not entry then
					entry = { recipe = recipe, knownBy = {} }
					byRecipe[recipe] = entry
					found[#found + 1] = entry
				end
				entry.knownBy[#entry.knownBy + 1] =
					{ name = profession.name, firstHand = profession.firstHand, source = profession.source }
			end
		end
	end
	table.sort(found, function(a, b)
		return a.recipe < b.recipe
	end)
	return found
end

-- The recipes others know of each of a character's professions (one of this
-- account's) that it has not learned, by skill line, sorted: the game says
-- which it has learned even with the profession's window closed, so a
-- character finds its recipes without opening it.
function Professions:recipesToFind(name)
	local wanted = {}
	for _, profession in ipairs(self.characters:currentProfessions(name)) do
		local skip = {}
		for _, recipe in ipairs(profession.recipes or {}) do
			skip[recipe] = true
		end
		wanted[profession.skillLine] = skip
	end
	local found = {}
	for _, profession in ipairs(self:list()) do
		local skip = wanted[profession.skillLine]
		for _, recipe in ipairs(skip and profession.recipes or {}) do
			if not skip[recipe] then
				skip[recipe] = true
				local list = found[profession.skillLine] or {}
				found[profession.skillLine] = list
				list[#list + 1] = recipe
			end
		end
	end
	for _, list in pairs(found) do
		table.sort(list)
	end
	return found
end
