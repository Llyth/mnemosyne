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
