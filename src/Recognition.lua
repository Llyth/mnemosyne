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
local PURPLE = { 0.62, 0.55, 0.95 } -- a first-hand nickname's color in a tooltip
local GREY = { 0.5, 0.5, 0.5 } -- a second-hand nickname's color in a tooltip
local GREY_CODE = "|cff808080" -- the same grey, in chat

-- memory: the Memory to recall identities from.
-- settings: the saved settings (MnemosyneDB.settings); settings.chat switches
-- chat recognition on, settings.showSecondHand second-hand identities.
-- L: the locale table. clock: returns the server time, in seconds.
function Recognition.new(memory, settings, L, clock)
	return setmetatable({ memory = memory, settings = settings, L = L, clock = clock, fullNames = {} }, Recognition)
end

-- Learns that a GUID belongs to a full name, from a chat line or a group
-- member: the memory sees it (an identity whose name shows up with another
-- GUID goes stale), and the map keeps it for this session. Only a character
-- the memory knows is mapped, so the map stays small in busy channels; a
-- missing GUID teaches nothing.
function Recognition:learn(guid, fullName)
	if guid and guid ~= "" then
		self.memory:see(fullName, guid)
		if self.memory:recall(fullName) then
			self.fullNames[guid] = fullName
		end
	end
end

-- Recalls the identity of a character shown by name, and by GUID when it is
-- known. A full name shown ("First Last") is trusted; a first name alone
-- finds the full name learned for the GUID. Nil when its player's nickname is
-- not known, or known only second-hand while second-hand identities are off.
function Recognition:recall(name, guid)
	if not name:find(" ", 1, true) and guid then
		name = self.fullNames[guid] or name
	end
	local identity = self.memory:recall(name)
	if identity and not self:shows(identity) then
		return nil
	end
	return identity
end

-- Whether an identity shows: a second-hand one only while second-hand
-- identities are on.
function Recognition:shows(identity)
	return not identity.source or self.settings.showSecondHand
end

-- Finds the identities whose character name or nickname contains the text
-- (Memory:search), leaving out those that do not show.
function Recognition:search(text)
	local found = {}
	for _, identity in ipairs(self.memory:search(text)) do
		if self:shows(identity) then
			found[#found + 1] = identity
		end
	end
	return found
end

-- How many identities show (Recognition:shows).
function Recognition:count()
	return self.memory:count(not self.settings.showSecondHand)
end

-- An identity's nickname as shown: marked with ~ when heard second-hand.
function Recognition:nickname(identity)
	if identity.source then
		return self.L.SECOND_HAND:format(identity.nickname)
	end
	return identity.nickname
end

-- An identity's line in a lookup, from a found identity ({ name, nickname,
-- source }): with who passed it on when heard second-hand.
function Recognition:lookupLine(identity)
	if identity.source then
		return self.L.LOOKUP_FOUND_SECOND_HAND:format(identity.name, self:nickname(identity), identity.source)
	end
	return self.L.LOOKUP_FOUND:format(identity.name, identity.nickname)
end

-- The tooltip lines that say who plays a character, from its identity
-- ({ nickname, source }), as { { text, r, g, b }, ... }: in Mnemosyne's color
-- when heard first-hand; in grey, marked with ~ and with who passed it on,
-- when heard second-hand.
function Recognition:playedBy(identity)
	local playedBy = self.L.TOOLTIP_PLAYED_BY:format(self:nickname(identity))
	if not identity.source then
		return { { playedBy, PURPLE[1], PURPLE[2], PURPLE[3] } }
	end
	return {
		{ playedBy, GREY[1], GREY[2], GREY[3] },
		{ self.L.HEARD_FROM:format(identity.source), GREY[1], GREY[2], GREY[3] },
	}
end

-- The sender's name in a chat line with its player's nickname after it, a
-- second-hand one in grey and marked with ~; or nil to leave the line as it
-- is (a stranger, or chat recognition off).
-- decorated: the name as the chat frame shows it, colors included; guid: the
-- line's GUID, when there is one.
function Recognition:chatName(decorated, name, guid)
	if not self.settings.chat then
		return nil
	end
	local identity = self:recall(name, guid)
	if not identity then
		return nil
	end
	local nickname = self:nickname(identity)
	if identity.source then
		nickname = GREY_CODE .. nickname .. "|r"
	end
	return self.L.CHAT_NAME:format(decorated, nickname)
end

-- A line of the Communities window with its sender's nickname after the name,
-- or nil to leave it as it is. The window formats its own lines and calls no
-- name filter: the sender is its line's first link, when that link is a
-- character's ("|HplayerCommunity:First Last:...|hshown name|h"), and only the
-- link's text changes, the same way chatName changes a chat frame's line.
function Recognition:communitiesLine(line)
	local before, link, kind, name, decorated, after = line:match("^(.-)(|H(%a+):([^:|]*)[^|]*|h)(.-)|h(.*)$")
	if kind ~= "playerCommunity" then
		return nil
	end
	local named = self:chatName(decorated, name)
	return named and before .. link .. named .. "|h" .. after
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
-- { name, nickname, heard, source }, source for a second-hand identity only;
-- or nil to show none (not a character's link, a stranger, or chat recognition
-- off).
function Recognition:chatTooltip(link)
	if not self.settings.chat then
		return nil
	end
	local name = linkedName(link)
	local identity = name and self:recall(name)
	if not identity then
		return nil
	end
	return {
		name = name,
		nickname = identity.nickname,
		heard = heardAgo(self.L, self.clock() - identity.heard),
		source = identity.source,
	}
end
