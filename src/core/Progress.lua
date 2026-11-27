-- Progress: every milestone the character played tracks, first-hand and
-- second-hand, keyed by the character's full name and the milestone's ID
-- (decision 0009). Pure: it takes its saved table, the clock (the server
-- time), the memory, this account's characters and the settings as arguments
-- (decision 0004).
--
-- Each milestone is a copy and spreads by the rules of Copies (decision 0001:
-- first-hand wins, disputes, removals, staleness, who is kept, the daily
-- limit); Progress adds the milestones tracked and what a milestone says (its
-- cell, Milestones): a cell heard from a peer that Milestones.normalize
-- refuses is dropped whole, never trimmed.
local _, ns = ...

local Copies = ns.Copies
local Milestones = ns.Milestones

local Progress = setmetatable({}, { __index = Copies })
Progress.__index = Progress
ns.Progress = Progress

-- The milestones tracked, by ID: any other heard is dropped, a placeholder
-- too (it tracks nothing).
Progress.KEYS = {}
for _, milestone in ipairs(Milestones.LIST) do
	if not milestone.placeholder then
		Progress.KEYS[milestone.id] = true
	end
end
Progress.KEY = "milestone"
Progress.FIELDS = { "state", "item", "quest", "gems" } -- a removal has no state

-- saved: the table Progress keeps its milestones in
-- (MnemosyneCharacterDB.progress).
-- clock, memory, characters, settings, scope, playerName: as Copies.new takes them.
function Progress.new(saved, clock, memory, characters, settings, scope, playerName)
	return Copies.new(Progress, saved, clock, memory, characters, settings, scope, playerName)
end

-- shortcut: the text a milestone passed on takes, for its size in an answer,
-- until Protocol writes progress; then Protocol's writer replaces it.
function Progress.write(passed)
	local text = passed.revision .. ":" .. passed.name .. ":" .. passed.milestone
	if passed.state then
		text = text
			.. ":"
			.. table.concat({ passed.state, passed.item or "", passed.quest or "", passed.gems or "" }, ":")
	end
	return text .. (passed.guid and "\nG:" .. passed.guid or "")
end

-- This account's characters' progress, as Self reads it (Copies' hooks):
-- stamping gives a removal of each milestone tracked a registered character
-- lacks too.
function Progress:stamp(name)
	self.characters:stampProgress(name, Progress.KEYS)
end

function Progress:stamped(name)
	return self.characters:progress(name)
end

function Progress:withCurrent()
	return self.characters:withProgress()
end

function Progress:current(name)
	return self.characters:currentProgress(name)
end

-- Checks a peer's cell as it is heard (Milestones.normalize): false drops
-- the copy whole when the cell is malformed or not its milestone's. A
-- removal is kept as is. Only FIELDS are kept, so nothing is trimmed.
function Progress.clean(_, id, heard)
	if heard.state ~= nil and not Milestones.normalize(id, heard) then
		return false
	end
end

-- What a milestone says, as one text: two copies say the same when it matches.
function Progress.content(name, id, milestone)
	local cell = milestone.state
			and table.concat(
				{ milestone.state, milestone.item or "", milestone.quest or "", milestone.gems or "" },
				","
			)
		or ""
	return table.concat({ name, id, milestone.revision, cell }, "\n")
end
