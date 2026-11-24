-- Catalog: what the window's Professions tab shows, decided here and drawn by
-- the Interface adapter (decision 0004). Pure: it takes the professions as
-- Professions:list gives them, whether second-hand ones show, and the game's
-- lookups (names are looked up when shown, decision 0008) as arguments.
local _, ns = ...

local Catalog = {}
Catalog.__index = Catalog
ns.Catalog = Catalog

-- Whether a skill line is a secondary profession (Professions.SKILL_LINES);
-- every other one is primary.
function Catalog.isSecondary(skillLine)
	return ns.Professions.SKILL_LINES[skillLine] == "secondary"
end

-- entries: Professions:list(). showSecondHand: the setting; while it is off,
-- second-hand professions are left out, your own characters' never.
-- lookups: { profession = function(skillLine), recipe = function(recipeID),
-- nickname = function(name) }, each giving the name to show, or nil: a
-- profession or recipe the game cannot name shows its ID, a character whose
-- identity does not show has no nickname. known: the game's professions, a
-- table keyed by skill line (Professions.SKILL_LINES), shown even when nobody
-- has them (nil for none).
function Catalog.new(entries, showSecondHand, lookups, known)
	local shown = {}
	for _, entry in ipairs(entries) do
		if not entry.disputed and (showSecondHand or entry.own or entry.firstHand ~= false) then
			shown[#shown + 1] = entry
		end
	end
	return setmetatable({ entries = shown, lookups = lookups, known = known or {} }, Catalog)
end

local function named(lookup, id)
	return lookup and lookup(id) or tostring(id)
end

-- Sorts found by folded name, then by id; before(a, b) comes first when it
-- decides. Each name is folded once, not in every comparison.
local function sortByName(found, idKey, before)
	local folded = {}
	for _, item in ipairs(found) do
		folded[item] = ns.Memory.fold(item.name)
	end
	table.sort(found, function(a, b)
		local first = before and before(a, b)
		if first ~= nil then
			return first
		end
		if folded[a] ~= folded[b] then
			return folded[a] < folded[b]
		end
		return a[idKey] < b[idKey]
	end)
end

-- Every profession that shows: { skillLine, name, secondary, recipes (how
-- many distinct recipes its characters know), characters (how many) }, the
-- known ones and those heard of, the primary ones first, each part by name.
function Catalog:professions()
	local found, bySkillLine = {}, {}
	local function add(skillLine)
		if not bySkillLine[skillLine] then
			bySkillLine[skillLine] = {
				skillLine = skillLine,
				name = named(self.lookups.profession, skillLine),
				secondary = Catalog.isSecondary(skillLine),
				recipes = 0,
				characters = 0,
				known = {},
			}
			found[#found + 1] = bySkillLine[skillLine]
		end
		return bySkillLine[skillLine]
	end
	for skillLine in pairs(self.known) do
		add(skillLine)
	end
	for _, entry in ipairs(self.entries) do
		local profession = add(entry.skillLine)
		profession.characters = profession.characters + 1
		for _, recipe in ipairs(entry.recipes or {}) do
			if not profession.known[recipe] then
				profession.known[recipe] = true
				profession.recipes = profession.recipes + 1
			end
		end
	end
	for _, profession in ipairs(found) do
		profession.known = nil
	end
	sortByName(found, "skillLine", function(a, b)
		if a.secondary ~= b.secondary then
			return b.secondary
		end
	end)
	return found
end

-- A profession's recipes whose name contains the text, ignoring case and
-- accents: { recipe, name, characters (how many know it) }, by name.
function Catalog:recipes(skillLine, text)
	local found, byRecipe = {}, {}
	for _, entry in ipairs(self.entries) do
		if entry.skillLine == skillLine then
			for _, id in ipairs(entry.recipes or {}) do
				local recipe = byRecipe[id]
				if not recipe then
					recipe = { recipe = id, name = named(self.lookups.recipe, id), characters = 0 }
					byRecipe[id] = recipe
					if ns.Memory.matches(text, recipe.name) then
						found[#found + 1] = recipe
					end
				end
				recipe.characters = recipe.characters + 1
			end
		end
	end
	sortByName(found, "recipe")
	return found
end

-- A character's row: { name, nickname, level, maxLevel, own, source, online }.
local function row(self, entry, online)
	return {
		name = entry.name,
		nickname = self.lookups.nickname and self.lookups.nickname(entry.name),
		level = entry.level,
		maxLevel = entry.maxLevel,
		own = entry.own,
		source = entry.source,
		online = online[entry.name] == true,
	}
end

local function byLevel(a, b)
	if a.level ~= b.level then
		return a.level > b.level
	end
	return a.name < b.name
end

-- Who knows a recipe of a profession, as rows: online first (online: a set
-- of names), then by skill level.
function Catalog:knowers(skillLine, recipe, online)
	local found = {}
	for _, entry in ipairs(self.entries) do
		if entry.skillLine == skillLine then
			for _, id in ipairs(entry.recipes or {}) do
				if id == recipe then
					found[#found + 1] = row(self, entry, online)
				end
			end
		end
	end
	table.sort(found, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return byLevel(a, b)
	end)
	return found
end

-- A profession's characters whose name or nickname contains the text,
-- ignoring case and accents, as rows, by skill level.
function Catalog:characters(skillLine, text, online)
	local found = {}
	for _, entry in ipairs(self.entries) do
		if entry.skillLine == skillLine then
			local character = row(self, entry, online)
			if ns.Memory.matches(text, character.name, character.nickname) then
				found[#found + 1] = character
			end
		end
	end
	table.sort(found, byLevel)
	return found
end
