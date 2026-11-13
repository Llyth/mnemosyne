-- Strangers: which characters to ask who plays them when the player meets
-- them (hovers or targets them), and when. Pure: it takes its saved table,
-- the clock and the memory as arguments (decision 0004); the hooks that call
-- it are in src/Encounter.lua.
--
-- A character is asked only when its identity is not known and the player did
-- not forget it (asking would bring it back first-hand), at most once a
-- day, and at most one ask goes out every 2 seconds: an ask in between is
-- dropped, not queued (decision 0002).
local _, ns = ...

local Strangers = {}
Strangers.__index = Strangers
ns.Strangers = Strangers

local DAY = 24 * 60 * 60 -- seconds before asking the same character again
local SPACING = 2 -- seconds between two asks

-- saved: the table of whom it asked and when (MnemosyneDB.asked). Asks older
-- than a day are let go here, so it holds at most a day of them.
-- clock: returns the server time, in seconds (fractions welcome).
-- memory: the Memory, to leave alone the characters it knows.
function Strangers.new(saved, clock, memory)
	local now = clock()
	for name, askedAt in pairs(saved) do
		if now - askedAt >= DAY then
			saved[name] = nil
		end
	end
	return setmetatable({ asked = saved, clock = clock, memory = memory }, Strangers)
end

-- Whether to ask a character met just now, given the full name of the
-- character being played; when true, it counts as asked.
function Strangers:ask(name, player)
	local now = self.clock()
	if name == player or self.memory:knows(name) or self.memory:isForgotten(name) then
		return false
	end
	local askedAt = self.asked[name]
	if askedAt and now - askedAt < DAY then
		return false
	end
	if self.lastAsk and now - self.lastAsk < SPACING then
		return false
	end
	self.asked[name] = now
	self.lastAsk = now
	return true
end
