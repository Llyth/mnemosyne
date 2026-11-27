-- Professions: every profession the character played holds, first-hand and
-- second-hand, keyed by the character's full name and the profession's skill
-- line ID (decision 0008). Pure: it takes its saved table, the clock (the
-- server time), the memory, this account's characters and the settings as
-- arguments (decision 0004).
--
-- Each profession follows the rules of the identities (decision 0001): a
-- first-hand one always wins; among second-hand copies the later revision
-- wins; the same revision with other content is disputed and hidden; a
-- removal (no level) is a revision too. It goes stale when its full name
-- shows up with another GUID, hidden until the character shares first-hand;
-- this account's characters', which take their GUID from Self, only once
-- the GUID seen is not Self's (another player's character took the name).
-- Kept only for this account's characters (not while they come as anyone's,
-- nor a name another player's character has taken), and for characters seen
-- on a guild roster or online as a friend's in the last 30 days; others are dropped
-- quietly. Second-hand ones are refused and dropped while the character is
-- forgotten (a first-hand one still gets through, as for identities) or while
-- its identity is held as a removal (anonymous or unregistered), so no peer
-- can link an anonymous character to its professions; first-hand ones too
-- while that removal is not disputed. Only the game's
-- skill lines are kept. At most 2,000 second-hand changes a day from one
-- peer, first-hand ones aside.
local _, ns = ...

local Digest = ns.Digest
local Protocol = ns.Protocol

local Professions = {}
Professions.__index = Professions
ns.Professions = Professions

local DAY = 24 * 60 * 60

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

-- saved: the table Professions keeps its professions in
-- (MnemosyneCharacterDB.professions).
-- clock: returns the server time, in seconds.
-- memory: the Memory, for forgotten characters and identities held as removals.
-- characters: this account's characters (Self): their professions are read
-- from it, and never adopted from peers.
-- settings: the saved settings; settings.passOn switches passing on what was
-- heard from others (this account's characters' professions always go, but
-- for those that go as anyone's, asAnyone).
-- scope: the Scope, which holds the friends and the guild roster as last read:
-- whose professions are kept, and which peers may keep the roster's.
-- recipeSkillLine: returns the skill line the game places a recipe ID in, or
-- nil when it cannot; peers' recipes placed in another profession, or that it
-- cannot place, are dropped.
-- playerName: returns the full name of the character played, the one that
-- syncs, or nil before login.
function Professions.new(saved, clock, memory, characters, settings, scope, recipeSkillLine, playerName)
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
		scope = scope,
		recipeSkillLine = recipeSkillLine or function() end,
		playerName = playerName or function() end,
		changes = 0, -- how many changes were heard this session: the window redraws when it moves
		hashes = setmetatable({}, { __mode = "k" }), -- profession -> its hash, computed once
		-- profession -> true once its recipes were checked with the game placing recipes: prune checks it no more.
		checked = setmetatable({}, { __mode = "k" }),
		placesRecipes = false, -- whether the game placed a recipe this session
	}, Professions)
end

-- The professions' saved table copied whole (as Professions.new takes it),
-- for another of the account's characters to start from (the seed, decision
-- 0001): every
-- profession held but the disputed ones, each its own tables, this account's
-- characters' included (prepare takes an unregistered one's removals from
-- them); when each character was seen, so a roster read empty at login drops
-- nothing; not the daily counts of each peer.
function Professions.copy(saved)
	local held, seen = {}, {}
	for name, character in pairs(saved.held or {}) do
		local skills = {}
		for skillLine, profession in pairs(character.skills) do
			if not profession.disputed then
				local copied = {}
				for key, value in pairs(profession) do
					copied[key] = value
				end
				if profession.recipes then
					copied.recipes = {}
					for i, recipe in ipairs(profession.recipes) do
						copied.recipes[i] = recipe
					end
				end
				skills[skillLine] = copied
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

-- Whether a recipe belongs to a profession (a skill line), from the skill line
-- the game places it in: yes unless that is another of the game's skill lines
-- or the game cannot place it (nil). A skill line the game has no profession
-- for is kept.
function Professions.belongsTo(lookedUp, skillLine)
	return lookedUp ~= nil and (not Professions.SKILL_LINES[lookedUp] or lookedUp == skillLine)
end

-- A peer's recipes of a profession without those the game places in another
-- (1.1.x saved a window's recipes under the profession opened before) or
-- cannot place: a hostile peer could fill each copy with 600 made-up IDs. All
-- are kept while the game has placed no recipe this session (its lookup
-- missing, or answering nothing), so real recipes are never lost to it. The
-- same table when none is dropped; then whether checking them again would
-- change nothing.
local function ownRecipes(self, skillLine, recipes)
	if not recipes then
		return nil, true
	end
	local lookedUp = {}
	for i, recipe in ipairs(recipes) do
		lookedUp[i] = self.recipeSkillLine(recipe)
		self.placesRecipes = self.placesRecipes or lookedUp[i] ~= nil
	end
	if not self.placesRecipes then
		return recipes, false
	end
	local kept = {}
	for i, recipe in ipairs(recipes) do
		if Professions.belongsTo(lookedUp[i], skillLine) then
			kept[#kept + 1] = recipe
		end
	end
	return #kept < #recipes and kept or recipes, true
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
		value = Digest.hash(content(name, skillLine, profession))
		self.hashes[profession] = value
	end
	return value
end

-- Whether a character is one of this account's, given the GUID it told of
-- itself (nil when none, or when a peer passed it on: no proof): not once
-- another player's character has taken its name (Self:owns).
local function isOwn(self, name, guid)
	local character = self.held[name]
	return ((character and character.own) or self.characters:registration(name) ~= nil)
		and self.characters:owns(name, guid)
end

-- Whether another player's character has taken the name of one of this
-- account's: it told its professions itself (first-hand) under a GUID that is
-- not this account's character's, or the game showed it under the name (see),
-- which left this account's character's, first-hand, stale under its GUID.
local function isTaken(self, name)
	local character = self.held[name]
	if not character or character.own then
		return false
	end
	for _, profession in pairs(character.skills) do
		if profession.firstHand then
			return not isOwn(self, name, character.guid)
		end
	end
	return false
end

-- Whether one of this account's characters' professions go and come as any
-- other player's: while the character played is not registered (anonymous,
-- unregistered or not asked yet), for every other one. Passed on, stamped or
-- refused as this account's then, they would link the character played to
-- them (decision 0001); the character played still shares its own first-hand.
local function asAnyone(self, name)
	local played = self.playerName()
	if played == nil or name == played then
		return false
	end
	local registration = self.characters:registration(played)
	return not (registration and registration.nickname)
end

-- Whether a character was seen on a roster or as a friend's in the last 30 days.
local function seenLately(self, name, now)
	local seen = self.seen[name]
	return seen ~= nil and now - seen < Professions.KEPT_FOR
end

-- Whether professions of a character are kept: this account's, or seen lately.
-- This account's are kept as anyone's while they go and come as anyone's
-- (asAnyone), and so is a name another player's character has taken (isTaken,
-- or told under its GUID: guid as isOwn takes it).
local function keeps(self, name, now, guid)
	return (isOwn(self, name, guid) and not asAnyone(self, name) and not isTaken(self, name))
		or seenLately(self, name, now)
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
-- First-hand when the peer is the character itself: under a GUID other than
-- the one of this account's character of that name, the name is another
-- player's character's, and what was held as this account's goes. Returns
-- true when it changed what is held.
function Professions:hear(peer, heard)
	local now, name, skillLine = self.clock(), heard.name, heard.skillLine
	local firstHand = name == peer
	local guid = firstHand and heard.guid or nil -- a peer's word on another character's GUID tells nothing
	if
		not Professions.SKILL_LINES[skillLine]
		or heard.revision > now + DAY
		or (isOwn(self, name, guid) and not asAnyone(self, name))
		or not keeps(self, name, now, guid)
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
	if character and character.own and not isOwn(self, name, guid) then
		character = nil -- the name is another player's character's now
	end
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
	-- The GUID held stays, whatever the peer says (as Memory keeps it). This
	-- account's characters' copies take a peer's as anyone's would: holding
	-- none would tell a peer which names are this account's. Those prepare
	-- holds keep Self's.
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
-- it hidden until the character shares first-hand. This account's characters
-- are left to Self, which knows their GUIDs (prepare), unless the GUID seen is
-- not the one Self knows (Self:owns): another player's character has taken
-- the name, which is held as anyone's from then on (isTaken).
function Professions:see(name, guid)
	local character = self.held[name]
	if character and character.own then
		if self.characters:owns(name, guid) then
			return
		end
		character.own = nil
	end
	if character and character.guid ~= guid then
		if character.guid then
			for _, profession in pairs(character.skills) do
				profession.stale = true
			end
		end
		character.guid = guid
	end
end

-- Drops every profession held, every character seen and every peer's daily
-- count: a character new since the update starts empty (Memory:empty).
function Professions:empty()
	for _, saved in ipairs({ self.held, self.seen, self.newFrom }) do
		for key in pairs(saved) do
			saved[key] = nil
		end
	end
end

-- Drops quietly the professions no longer kept: of characters neither seen on
-- a roster nor as a friend's in the last 30 days, and those refused
-- (isRefused). Drops from the peers' professions held the recipes the game
-- places in another profession or cannot place, each copy once this session
-- after the game placed a recipe.
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
				if not self.checked[profession] then
					local recipes, placed = ownRecipes(self, skillLine, profession.recipes)
					if recipes ~= profession.recipes then
						profession.recipes = recipes
						self.hashes[profession] = nil
					end
					self.checked[profession] = placed or nil
				end
			end
		end
	end
end

-- Sees the friends' characters online and the guild roster, as the Scope
-- holds them once Client read them again: each is seen now. Then drops what is
-- no longer kept.
function Professions:seeLists()
	local now = self.clock()
	for _, name in ipairs(self.scope:listed()) do
		self.seen[name] = now
	end
	self:prune()
end

-- Reads this account's characters' professions, as a sync starts: stamps each
-- character's (a new revision for what changed since its last one, and a
-- removal of each of the game's skill lines a registered one lacks, so peers
-- drop a copy forged for it), then keeps them first-hand, with the GUID Self
-- holds, never stale, and only them: a profession peers passed on before the
-- character was this account's never goes as its own. While the character
-- played is not registered, only its own: the others' wait for a registered
-- one (asAnyone). A name another player's character has taken (isTaken) is
-- left to it. Then drops what is no longer kept.
function Professions:prepare()
	local names = {}
	for _, character in ipairs(self.characters:list("")) do
		names[character.name] = true
	end
	for name, character in pairs(self.held) do
		if character.own then
			-- Unregistered since: its removals still go while it syncs itself (goesTo).
			names[name] = true
		end
	end
	local now = self.clock()
	for name in pairs(names) do
		if asAnyone(self, name) or isTaken(self, name) then
			names[name] = nil
		end
	end
	for name in pairs(names) do
		self.characters:stampProfessions(name, Professions.SKILL_LINES)
		local character = self.held[name] or { skills = {} }
		character.own, character.guid = true, self.characters:guid(name)
		self.held[name] = character
		local read = {}
		for _, profession in ipairs(self.characters:professions(name)) do
			read[profession.skillLine] = true
			local known = character.skills[profession.skillLine]
			if
				not known
				or known.stale -- from an earlier version, which took a peer's GUID for it
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
		for skillLine in pairs(character.skills) do
			if not read[skillLine] then
				character.skills[skillLine] = nil
			end
		end
	end
	self:prune()
end

-- Whether a character's professions go to a peer, or come from it: this
-- account's registered characters' to a peer seen lately (on the roster or a
-- friend), which keeps them; to a guildmate, also the roster's. Passing on is
-- left aside, so both sides' digests compare the same set: Professions:answer
-- leaves the roster's out while it is off. Those of this account's anonymous
-- or unregistered characters, all removals, go only while that character is
-- the one played: the peer hears them first-hand, from the character itself,
-- which links nothing. Sent while another character of the account syncs,
-- they would link it to the account (decision 0001). While the character
-- played is not registered, the account's others go as anyone's (asAnyone),
-- left out as a peer leaves them out once their identity is held as a removal.
local function goesTo(self, peer, name, character, now)
	local anyone = asAnyone(self, name)
	if character.own and not anyone then
		local registration = self.characters:registration(name)
		local registered = registration ~= nil and registration.nickname ~= nil
		return (registered or name == self.playerName()) and seenLately(self, peer, now)
	end
	local scope = self.scope
	return (scope:isGuildmate(peer) and scope:isGuildmate(name) and not (anyone and isRefused(self, name, true)))
		or false
end

-- The digest for a peer, and the names in each bucket: every profession that
-- goes to it, disputed ones left out.
local function sums(self, peer)
	local now, digest, names = self.clock(), Digest.new(), {}
	for bucket = 1, Digest.BUCKETS do
		names[bucket] = {}
	end
	for name, character in pairs(self.held) do
		if goesTo(self, peer, name, character, now) then
			local bucket = Digest.bucket(name)
			names[bucket][#names[bucket] + 1] = name
			for skillLine, profession in pairs(character.skills) do
				if not profession.disputed then
					digest:add(name, hashOf(self, name, skillLine, profession))
				end
			end
		end
	end
	return digest, names
end

-- The digest of what goes to a peer, for a sync: each profession hashed with
-- what it says, summed in the bucket of its character's name.
function Professions:digest(peer)
	return (sums(self, peer)):write()
end

-- What to pass on to a peer, from its digest: the professions that go to it,
-- in buckets whose digest differs, never a disputed or stale one, and only
-- this account's characters' while passing on is off (not those that go as
-- anyone's, asAnyone); at most
-- 100 KB, the first-hand ones changed in the past day first, the latest
-- first, then the rest from a point that moves with the clock. Each is
-- { name, skillLine, revision, level, maxLevel, recipes, guid }, a removal
-- without a level.
function Professions:answer(peer, digest)
	local now = self.clock()
	local mine, names = sums(self, peer)
	local fresh, rest = {}, {}
	for _, bucket in ipairs(Digest.differing(mine:write(), digest)) do
		for _, name in ipairs(names[bucket]) do
			local character = self.held[name]
			local passes = (character.own and not asAnyone(self, name)) or self.settings.passOn
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
