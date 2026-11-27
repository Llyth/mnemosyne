-- Professions: every profession the character played holds, first-hand and
-- second-hand, keyed by the character's full name and the profession's skill
-- line ID (decision 0008). Pure: it takes its saved table, the clock (the
-- server time), the memory, this account's characters and the settings as
-- arguments (decision 0004).
--
-- Each profession is a copy and spreads by the rules of Copies (decision 0001:
-- first-hand wins, disputes, removals, staleness, who is kept, the daily
-- limit); Professions adds the game's skill lines, what a profession says
-- (its level, maximum and recipes), and its recipes: those a peer places in
-- another profession are dropped, and those others know are found.
local _, ns = ...

local Copies = ns.Copies
local Protocol = ns.Protocol

local Professions = setmetatable({}, { __index = Copies })
Professions.__index = Professions
ns.Professions = Professions

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
Professions.KEYS = Professions.SKILL_LINES
Professions.KEY = "skillLine"
-- A profession, heard or listed: { name, skillLine, revision, level, maxLevel, recipes, guid }.
Professions.FIELDS = { "level", "maxLevel", "recipes" } -- a removal has no level
Professions.write = Protocol.writeProfession

-- saved: the table Professions keeps its professions in
-- (MnemosyneCharacterDB.professions).
-- clock, memory, characters, settings, scope, playerName: as Copies.new takes them.
-- recipeSkillLine: returns the skill line the game places a recipe ID in, or
-- nil when it cannot; peers' recipes placed in another profession, or that it
-- cannot place, are dropped.
function Professions.new(saved, clock, memory, characters, settings, scope, recipeSkillLine, playerName)
	local self = Copies.new(Professions, saved, clock, memory, characters, settings, scope, playerName)
	self.recipeSkillLine = recipeSkillLine or function() end
	-- profession -> true once its recipes were checked with the game placing recipes: prune checks it no more;
	-- false once checked while the game placed none: prune checks one such copy at a time, until it places one.
	self.checked = setmetatable({}, { __mode = "k" })
	self.placesRecipes = false -- whether the game placed a recipe this session
	self.heardSince = {} -- name -> true once a profession of it was heard since the last look (recipesToFind)
	return self
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

-- This account's characters' professions, as Self reads them (Copies' hooks):
-- stamping gives a removal of each of the game's skill lines a registered
-- character lacks too.
function Professions:stamp(name)
	self.characters:stampProfessions(name, Professions.SKILL_LINES)
end

function Professions:stamped(name)
	return self.characters:professions(name)
end

function Professions:withCurrent()
	return self.characters:withProfessions()
end

function Professions:current(name)
	return self.characters:currentProfessions(name)
end

-- Places a peer's recipes as it is heard (ownRecipes).
function Professions:clean(skillLine, heard)
	heard.recipes = ownRecipes(self, skillLine, heard.recipes)
end

-- Drops quietly the professions no longer kept (Copies:prune). Then drops from
-- the peers' professions held the recipes the game
-- places in another profession or cannot place, each copy once this session
-- after the game placed a recipe; while it has placed none, one copy a prune,
-- to find whether it does now. only (name -> character held), when given:
-- those characters only, as a sync starts (prepare).
function Professions:prune(only)
	Copies.prune(self, only)
	local probed = false
	for _, character in pairs(only or self.held) do
		if not character.own then
			for skillLine, profession in pairs(character.skills) do
				local checked = self.checked[profession]
				if checked == nil or (checked == false and (self.placesRecipes or not probed)) then
					probed = probed or (checked == false and not self.placesRecipes)
					local recipes, placed = ownRecipes(self, skillLine, profession.recipes)
					if recipes ~= profession.recipes then
						profession.recipes = recipes
						self.hashes[profession] = nil
					end
					self.checked[profession] = placed
				end
			end
		end
	end
end

-- What a profession says, as one text: two copies say the same when it matches.
function Professions.content(name, skillLine, profession)
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
-- character finds its recipes without opening it. Looks at the professions
-- that show (list), read in place: neither copied nor sorted, only those of
-- the character's skill lines. With sinceLast (after a sync), only peers'
-- professions heard since the last look, besides this account's characters'.
function Professions:recipesToFind(name, sinceLast)
	local heardSince = self.heardSince
	self.heardSince = {}
	local wanted = {}
	for _, profession in ipairs(self.characters:currentProfessions(name)) do
		local skip = {}
		for _, recipe in ipairs(profession.recipes or {}) do
			skip[recipe] = true
		end
		wanted[profession.skillLine] = skip
	end
	local found = {}
	local function add(skillLine, recipes)
		local skip = wanted[skillLine]
		for _, recipe in ipairs(skip and recipes or {}) do
			if not skip[recipe] then
				skip[recipe] = true
				local list = found[skillLine] or {}
				found[skillLine] = list
				list[#list + 1] = recipe
			end
		end
	end
	if not next(wanted) then
		return found
	end
	local mine = {}
	for _, other in ipairs(self.characters:withProfessions()) do
		mine[other] = true
		for _, profession in ipairs(self.characters:currentProfessions(other)) do
			add(profession.skillLine, profession.recipes)
		end
	end
	for heldName in pairs(sinceLast and heardSince or self.held) do
		local character = self.held[heldName]
		if character and not (character.own or mine[heldName]) then
			for skillLine, profession in pairs(character.skills) do
				if
					wanted[skillLine]
					and profession.recipes
					and profession.level
					and not (profession.disputed or profession.stale)
					and not self:isRefused(heldName, profession.firstHand)
				then
					add(skillLine, profession.recipes)
				end
			end
		end
	end
	for _, list in pairs(found) do
		table.sort(list)
	end
	return found
end
