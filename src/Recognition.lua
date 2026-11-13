-- Recognition: what Mnemosyne shows where a character appears, decided here
-- and drawn by the adapters (decision 0004). Pure: it takes the memory, the
-- settings, the locale table and the clock (the server time) as arguments.
--
-- It also keeps, for the session only, which GUID goes with which full name
-- (decision 0003): learned from chat lines and group members, it finds the
-- character behind a tooltip that shows only a first name. The GUID is a
-- lookup aid, never a key.
local _, ns = ...

local Recognition = {}
Recognition.__index = Recognition
ns.Recognition = Recognition

local MINUTE, HOUR, DAY = 60, 3600, 86400

-- memory: the Memory to recall identities from.
-- settings: the saved settings (MnemosyneDB.settings); settings.chat switches
-- chat recognition on.
-- L: the locale table. clock: returns the server time, in seconds.
function Recognition.new(memory, settings, L, clock)
	return setmetatable({ memory = memory, settings = settings, L = L, clock = clock, fullNames = {} }, Recognition)
end

-- Learns that a GUID belongs to a full name, from a chat line or a group
-- member, for this session. A missing or empty GUID or name teaches nothing.
function Recognition:learn(guid, fullName)
	if guid and guid ~= "" and fullName and fullName ~= "" then
		self.fullNames[guid] = fullName
	end
end

-- Recalls the identity of a character shown by name, and by GUID when it is
-- known: the full name learned for the GUID wins over the name shown, which
-- may be a first name alone. Nil when its player's nickname is not known.
function Recognition:recall(name, guid)
	return self.memory:recall(guid and self.fullNames[guid] or name)
end

-- The sender's name in a chat line with its player's nickname after it, or nil
-- to leave the line as it is (an unknown character, or chat recognition off).
-- decorated: the name as the chat frame shows it, colors included.
function Recognition:chatName(decorated, name)
	if not self.settings.chat then
		return nil
	end
	local identity = self.memory:recall(name)
	return identity and self.L.CHAT_NAME:format(decorated, identity.nickname)
end

-- When an identity was last heard, in words.
local function heardAgo(L, age)
	if age >= DAY then
		return L.HEARD_DAYS:format(math.floor(age / DAY))
	elseif age >= HOUR then
		return L.HEARD_HOURS:format(math.floor(age / HOUR))
	elseif age >= MINUTE then
		return L.HEARD_MINUTES:format(math.floor(age / MINUTE))
	end
	return L.HEARD_NOW
end

-- The character a chat link points to ("player:First Last:..." or
-- "playerCommunity:First Last:..."), or nil for any other link.
local function linkedName(link)
	local kind, name = link:match("^(%a+):([^:]*)")
	if (kind == "player" or kind == "playerCommunity") and name ~= "" then
		return name
	end
	return nil
end

-- The tooltip on a character's name in a chat line, from the line's link:
-- { name, playedBy, heard }, or nil to show none (not a character's link, an
-- unknown character, or chat recognition off).
function Recognition:chatTooltip(link)
	if not self.settings.chat then
		return nil
	end
	local name = linkedName(link)
	local identity = name and self.memory:recall(name)
	if not identity then
		return nil
	end
	local L = self.L
	return {
		name = name,
		playedBy = L.TOOLTIP_PLAYED_BY:format(identity.nickname),
		heard = heardAgo(L, self.clock() - identity.heard),
	}
end
