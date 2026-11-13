-- Self: this account's characters and their registrations, keyed by full name.
-- Pure: it takes its saved table and the clock (the server time) as arguments
-- (decision 0004).
--
-- A character is in one of three states: "notAsked" (never registered, or
-- unregistered since), "registered" (with a nickname) or "anonymous" (its
-- player chose not to register it). Each change gets a revision: the server time, or the previous revision plus
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

local function change(self, name, nickname, anonymous)
	local previous = self.characters[name]
	self.characters[name] = {
		nickname = nickname,
		anonymous = anonymous,
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

-- Keeps a character anonymous: a change with a revision, so peers that held
-- its nickname forget it. Returns false when it already is anonymous.
function Self:keepAnonymous(name)
	if self:state(name) == "anonymous" then
		return false
	end
	change(self, name, nil, true)
	return true
end

-- The registration of a character, a copy: { nickname, revision } while it is
-- registered, { anonymous = true, revision } while it is anonymous, { revision }
-- once it unregistered, nil if it never registered.
function Self:registration(name)
	local character = self.characters[name]
	return character
		and { nickname = character.nickname, anonymous = character.anonymous, revision = character.revision }
end

-- A character's state: "notAsked", "registered" or "anonymous".
function Self:state(name)
	local character = self.characters[name]
	if character and character.nickname then
		return "registered"
	elseif character and character.anonymous then
		return "anonymous"
	end
	return "notAsked"
end

-- How many of this account's characters are in a state.
function Self:count(state)
	local count = 0
	for name in pairs(self.characters) do
		if self:state(name) == state then
			count = count + 1
		end
	end
	return count
end

-- What the registration prompt offers for a character, or nil when it should
-- not prompt (the character is registered or anonymous). A character not asked
-- yet is prompted at each login until its player answers. The offer pre-fills
-- the nickname of the player's latest registered character, or else what peers
-- say about this one (heard: Memory's identity for it, if any, flagged
-- fromPeers). The pre-fill is only an offer: nothing changes until the player
-- registers.
function Self:prompt(name, heard)
	if self:state(name) ~= "notAsked" then
		return nil
	end
	local latest
	for other, character in pairs(self.characters) do
		if other ~= name and character.nickname and not (latest and latest.revision >= character.revision) then
			latest = character
		end
	end
	if latest then
		return { nickname = latest.nickname }
	elseif heard and heard.nickname then
		return { nickname = heard.nickname, fromPeers = true }
	end
	return {}
end
