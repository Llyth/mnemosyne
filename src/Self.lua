-- Self: this account's characters and their registrations, keyed by full name.
-- Pure: it takes its saved table and the clock (the server time) as arguments
-- (decision 0004).
--
-- Each change gets a revision: the server time, or the previous revision plus
-- one if that is later, so it always moves forward (decision 0001).
local _, ns = ...

local Self = {}
Self.__index = Self
ns.Self = Self

-- saved: the table Self keeps the registrations in (MnemosyneDB.characters).
-- clock: returns the server time, in seconds.
function Self.new(saved, clock)
	return setmetatable({ characters = saved, clock = clock }, Self)
end

local function change(self, name, nickname)
	local previous = self.characters[name]
	self.characters[name] = {
		nickname = nickname,
		revision = math.max(self.clock(), previous and previous.revision + 1 or 0),
	}
end

-- Registers a character with its player's nickname, or changes it. Returns
-- true, or false and why the nickname breaks the rules (Protocol.checkNickname).
function Self:register(name, nickname)
	local ok, reason = ns.Protocol.checkNickname(nickname)
	if not ok then
		return false, reason
	end
	change(self, name, nickname)
	return true
end

-- Withdraws a character's registration. Returns false when it was not
-- registered.
function Self:unregister(name)
	local character = self.characters[name]
	if not (character and character.nickname) then
		return false
	end
	change(self, name, nil)
	return true
end

-- The registration of a character, a copy: { nickname, revision } while it is
-- registered, { revision } once it unregistered, nil if it never registered.
function Self:registration(name)
	local character = self.characters[name]
	return character and { nickname = character.nickname, revision = character.revision }
end
