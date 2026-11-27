-- Grid: what the window's Progress tab shows, decided here and drawn by the
-- Interface adapter (decision 0004): for each category of Milestones, one row
-- per character and one column per milestone. Pure: it takes the progress as
-- Progress:list gives it, whether second-hand copies show, and the nickname
-- lookup as arguments.
local _, ns = ...

local Milestones = ns.Milestones

local Grid = {}
Grid.__index = Grid
ns.Grid = Grid

-- A category's milestones (attunements, entrances, summons or leveling), in
-- the order shown, placeholders included.
function Grid.columns(category)
	local found = {}
	for _, milestone in ipairs(Milestones.LIST) do
		if milestone.category == category then
			found[#found + 1] = milestone
		end
	end
	return found
end

-- entries: Progress:list(). showSecondHand: the setting; while it is off,
-- second-hand copies are left out (disputed ones too), your own characters'
-- never. nickname(name): the character's nickname as it shows and bare (for
-- sorting), or nil when its identity does not show. own (optional): your
-- own characters' names, each a row even with no progress (shown when
-- everyone shows).
function Grid.new(entries, showSecondHand, nickname, own)
	local characters, byName = {}, {}
	local function characterOf(name)
		local character = byName[name]
		if not character then
			local shown, bare = nickname(name)
			character = { name = name, nickname = shown, cells = {} }
			character.sortKey = ns.Memory.fold(bare or name)
			byName[name] = character
			characters[#characters + 1] = character
		end
		return character
	end
	for _, entry in ipairs(entries) do
		-- A dispute is between second-hand copies: a disputed entry is second-hand.
		if showSecondHand or entry.own or (entry.firstHand ~= false and not entry.disputed) then
			local character = characterOf(entry.name)
			character.cells[entry.milestone] = entry
			character.own = character.own or entry.own
		end
	end
	for _, name in ipairs(own or {}) do
		characterOf(name).own = true
	end
	return setmetatable({ characters = characters }, Grid)
end

-- Which of a cell's gems (in the order of Upper Blackrock Spire's gems) it
-- holds: a list of three booleans.
function Grid.gems(cell)
	local gems = cell and cell.gems or 0
	local held, bit = {}, 1
	for i = 1, 3 do
		held[i] = math.floor(gems / bit) % 2 == 1
		bit = bit * 2
	end
	return held
end

-- How a cell sorts in its column: done first, then in progress, then the
-- others (none or disputed). A milestone with gems puts, among those in
-- progress, the fewest lacking first, then by which (the lacking ones' bits).
local function rank(milestone, cell)
	if cell and cell.state == "done" then
		return 0, 0
	end
	if not (cell and cell.state == "progress") then
		return 2, 0
	end
	if not milestone.gems then
		return 1, 0
	end
	local lacking, mask, bit = 0, 0, 1
	for _, held in ipairs(Grid.gems(cell)) do
		if not held then
			lacking, mask = lacking + 1, mask + bit
		end
		bit = bit * 2
	end
	return 1, lacking * 8 + mask
end

-- The rows of a category whose name or nickname contains the text, ignoring
-- case and accents: { name, nickname, own, cells (the category's, by
-- milestone ID) }. A character with no cell there that is done or in
-- progress shows only when everyone does. By nickname (or name when none
-- shows), then name; with sortBy (a milestone ID), by that column first.
function Grid:rows(category, text, everyone, sortBy)
	local columns = Grid.columns(category)
	local found = {}
	for _, character in ipairs(self.characters) do
		local row = { name = character.name, nickname = character.nickname, own = character.own, cells = {} }
		local any = false
		for _, milestone in ipairs(columns) do
			local cell = character.cells[milestone.id]
			row.cells[milestone.id] = cell
			any = any or (cell ~= nil and cell.state ~= nil)
		end
		if (any or everyone) and ns.Memory.matches(text, character.name, character.nickname) then
			found[#found + 1] = row
			row.sortKey = character.sortKey
		end
	end
	local sorted = sortBy and Milestones.BY_ID[sortBy]
	table.sort(found, function(a, b)
		if sorted then
			local aState, aDetail = rank(sorted, a.cells[sortBy])
			local bState, bDetail = rank(sorted, b.cells[sortBy])
			if aState ~= bState then
				return aState < bState
			end
			if aDetail ~= bDetail then
				return aDetail < bDetail
			end
		end
		if a.sortKey ~= b.sortKey then
			return a.sortKey < b.sortKey
		end
		return a.name < b.name
	end)
	return found
end

-- The rows that lack a milestone's gem (its index in the milestone's gems):
-- not done, and not holding it, in the order given.
function Grid.lacking(rows, milestoneID, gem)
	local found = {}
	for _, row in ipairs(rows) do
		local cell = row.cells[milestoneID]
		if not (cell and cell.state == "done") and not Grid.gems(cell)[gem] then
			found[#found + 1] = row
		end
	end
	return found
end
