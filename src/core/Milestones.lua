-- Milestones: what Progress tracks (the attunements, entrance keys and
-- summoning items of WoW Forever), and the cell each shows for one character
-- from what it holds and its quests. Pure: no WoW API, no clock (decision
-- 0004); Client reads the game, Progress spreads the cells.
--
-- A cell is nil for "—", else a flat table, the same in memory and, once
-- Protocol writes it, on the wire:
--   state  "done" (✓) or "progress" (In progress); summons are only ever done
--   item   done: the item held that counts (the first of the milestone's
--          items held); progress: the item held that makes it in progress
--          (a seal step), if any. The item a milestone leads to is its
--          items[1].
--   quest  progress only: the milestone's quest in the log, if any
--   gems   Upper Blackrock Spire in progress only: the gems held, a bit each
--          in the order of its gems (1 Spirestone, 2 Smolderthorn,
--          4 Bloodaxe), 7 with the Unforged or Forged Seal
local _, ns = ...

local Milestones = {}
ns.Milestones = Milestones

-- One entry per milestone, in the order shown. Adding a milestone is one
-- entry here. Each id goes on the wire: never reuse or renumber one, even
-- after its milestone is dropped (older clients ignore IDs they don't know).
--   items          held: done (✓)
--   quests         in the log: in progress (a character only ever has its
--                  own faction's)
--   finals         a chain's final quests: until one is completed, any of
--                  quests completed counts as in progress too
--   seals          held: in progress, with every gem lit
--   progressItems  held: in progress
--   gems           held: in progress, each shown lit
--   placeholder    shown greyed, tracks nothing
Milestones.LIST = {
	-- Attunements
	{
		id = 1,
		key = "onyxia",
		category = "attunements",
		kind = "attunement",
		items = { 16309 }, -- Drakefire Amulet
		quests = { 6403, 6501, 6502, 6585, 6601, 6602 }, -- Alliance 6403 → 6501 → 6502, Horde 6585 → 6601 → 6602
		finals = { 6502, 6602 },
	},
	-- Not in Forever yet: quests 7848 / 7487 kept for later.
	{ id = 2, key = "moltenCore", category = "attunements", kind = "attunement", placeholder = true },
	-- Endgame entrances
	{
		id = 3,
		key = "blackrockDepths",
		category = "entrances",
		kind = "entrance",
		items = { 11000 }, -- Shadowforge Key
		quests = { 3802 }, -- Dark Iron Legacy
	},
	-- By possession only, never a quest.
	{ id = 4, key = "direMaul", category = "entrances", kind = "entrance", items = { 18249 } }, -- Crescent Key
	{
		id = 5,
		key = "scholomance",
		category = "entrances",
		kind = "entrance",
		items = { 13704 }, -- Skeleton Key
		quests = { 5505, 5511 }, -- The Key to Scholomance: Alliance, Horde
	},
	{
		id = 6,
		key = "upperBlackrockSpire",
		category = "entrances",
		kind = "entrance",
		items = { 12344 }, -- Seal of Ascension
		seals = { 12324, 12323 }, -- Forged, Unforged Seal of Ascension
		quests = { 4742, 4743 }, -- Seal of Ascension
		progressItems = { 12219 }, -- Unadorned Seal of Ascension
		gems = { 12336, 12335, 12337 }, -- Spirestone, Smolderthorn, Bloodaxe
	},
	{ id = 7, key = "stratholme", category = "entrances", kind = "entrance", items = { 12382 } }, -- Key to the City
	-- Endgame summons: the Brazier of Invocation (22057) counts for each
	-- Brazier of Beckoning's boss.
	{ id = 8, key = "theldren", category = "summons", kind = "summon", items = { 21986 } }, -- Banner of Provocation
	{ id = 9, key = "morGrayhoof", category = "summons", kind = "summon", items = { 22049, 22057 } },
	{ id = 10, key = "isalien", category = "summons", kind = "summon", items = { 22050, 22057 } },
	{ id = 11, key = "jarienSothos", category = "summons", kind = "summon", items = { 22051, 22057 } },
	{ id = 12, key = "kormok", category = "summons", kind = "summon", items = { 22052, 22057 } },
	{ id = 13, key = "lordValthalak", category = "summons", kind = "summon", items = { 22056, 22057 } },
	-- Leveling
	{ id = 14, key = "scarletMonastery", category = "leveling", kind = "entrance", items = { 7146 } }, -- The Scarlet Key
	{ id = 15, key = "gnomeregan", category = "leveling", kind = "entrance", items = { 6893 } }, -- Workshop Key
	{
		id = 16,
		key = "maraudon",
		category = "leveling",
		kind = "entrance",
		items = { 17191 }, -- Scepter of Celebras
		quests = { 7044, 7046 },
	},
	{
		id = 17,
		key = "krolDokStronghold",
		category = "leveling",
		kind = "entrance",
		items = { 267089 }, -- Krol'dok Compound Key
		quests = { 94973, 94974, 94980, 94981 }, -- Horde 94973 → 94974, Alliance 94980 → 94981
	},
	{
		id = 18,
		key = "cityOfDalaran",
		category = "leveling",
		kind = "entrance",
		items = { 277507 }, -- Dalaran Sewer Key
		quests = { 92458, 96984 }, -- Heart of Disruption: Alliance, Horde
	},
	{ id = 19, key = "gahzrilla", category = "leveling", kind = "summon", items = { 9240 } }, -- Mallet of Zul'Farrak
	{ id = 20, key = "lynTheIgnored", category = "leveling", kind = "summon", items = { 275989 } }, -- Tome of Dalaran
}

-- Derived from the list: each milestone by its id, and every item and quest
-- the milestones track (Client reads only those), each once.
Milestones.BY_ID = {}
Milestones.ITEMS = {}
Milestones.QUESTS = {}
local seen = { [Milestones.ITEMS] = {}, [Milestones.QUESTS] = {} }
local function collect(into, values)
	for _, value in ipairs(values or {}) do
		if not seen[into][value] then
			seen[into][value] = true
			into[#into + 1] = value
		end
	end
end
for _, milestone in ipairs(Milestones.LIST) do
	Milestones.BY_ID[milestone.id] = milestone
	for _, field in ipairs({ "items", "seals", "progressItems", "gems" }) do
		collect(Milestones.ITEMS, milestone[field])
	end
	collect(Milestones.QUESTS, milestone.quests)
end

-- The first of values in the set, if any.
local function first(values, set)
	for _, value in ipairs(values or {}) do
		if set[value] then
			return value
		end
	end
end

local function cell(milestone, held, completed, inLog)
	local item = first(milestone.items, held)
	if item then
		return { state = "done", item = item }
	end
	local seal = first(milestone.seals, held)
	if seal then
		return { state = "progress", item = seal, gems = 7 }
	end
	local gems, bit = 0, 1
	for _, gem in ipairs(milestone.gems or {}) do
		gems = held[gem] and gems + bit or gems
		bit = bit * 2
	end
	local quest = first(milestone.quests, inLog)
	item = first(milestone.progressItems, held)
	local chain = milestone.finals and not first(milestone.finals, completed) and first(milestone.quests, completed)
	if quest or item or gems > 0 or chain then
		return { state = "progress", quest = quest, item = item, gems = milestone.gems and gems }
	end
end

-- Each milestone's cell for one character, by milestone id (nil for "—").
-- held: the items it holds in bags, keyring and bank as last seen;
-- completed: the quests it has completed; inLog: the quests in its log; each
-- a set ({ [id] = true }) of at least those in ITEMS or QUESTS.
function Milestones.cells(held, completed, inLog)
	local result = {}
	for _, milestone in ipairs(Milestones.LIST) do
		result[milestone.id] = cell(milestone, held, completed, inLog)
	end
	return result
end

-- Whether value is one of values.
local function among(value, ...)
	for i = 1, select("#", ...) do
		for _, candidate in ipairs(select(i, ...) or {}) do
			if value == candidate then
				return true
			end
		end
	end
	return false
end

-- Whether value is absent, or one of values.
local function absentOrAmong(value, ...)
	return value == nil or among(value, ...)
end

-- A cell heard from a peer for milestone id, as a cell of its own, or nil to
-- drop it whole: an id it does not know (a later version's milestone,
-- ignored), a placeholder, a malformed cell, a summon in progress, or an
-- item, quest or gems that is not the milestone's. Never trimmed: a trimmed
-- copy would say other than the same revision a later version holds, which
-- disputes it there. Fields a cell does not have are left out.
function Milestones.normalize(id, heard)
	local milestone = Milestones.BY_ID[id]
	if not milestone or milestone.placeholder or type(heard) ~= "table" then
		return nil
	end
	local state, item, quest, gems = heard.state, heard.item, heard.quest, heard.gems
	if state == "done" then
		if absentOrAmong(item, milestone.items) and quest == nil and gems == nil then
			return { state = "done", item = item }
		end
		return nil
	end
	if state ~= "progress" or milestone.kind == "summon" then
		return nil
	end
	local gemsFit = gems == nil
		or (milestone.gems and type(gems) == "number" and gems >= 0 and gems <= 7 and gems % 1 == 0)
	if
		absentOrAmong(item, milestone.seals, milestone.progressItems)
		and absentOrAmong(quest, milestone.quests)
		and gemsFit
	then
		return { state = "progress", item = item, quest = quest, gems = gems }
	end
	return nil
end

-- Whether two cells (or nil) show the same.
function Milestones.equal(a, b)
	if a == nil or b == nil then
		return a == b
	end
	return a.state == b.state and a.item == b.item and a.quest == b.quest and a.gems == b.gems
end
