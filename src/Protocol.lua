-- Protocol: the wire format of Mnemosyne's addon messages, and the validation
-- of everything a peer sends. Pure: no WoW API (decision 0004).
--
-- A message is text, at most 255 bytes, sent on the prefix "Mnemosyne":
--
--   <version>:<kind>[:<fields>]
--
--   1:A:<revision>:<nickname>   announcement: a character says who plays it
--   1:Q                         ask: the receivers answer who plays them
--   1:R:<revision>:<nickname>   answer to an ask
--   1:U:<revision>              removal: the character unregistered
--
-- The version is a decimal number; a peer drops every other version. The kind
-- is one capital letter; a peer drops a kind it does not know, so later kinds
-- (chunks, syncs) can join version 1 without breaking older peers. A nickname is
-- the last field, so it may hold ':'. The revision is a positive integer of at
-- most 14 digits (what tostring writes exactly), without leading zeros, so it
-- reads back as the same number.
local _, ns = ...

local Protocol = {}
ns.Protocol = Protocol

Protocol.PREFIX = "Mnemosyne"
Protocol.VERSION = 1
Protocol.MAX_MESSAGE_BYTES = 255
Protocol.MAX_NICKNAME_CHARACTERS = 32

local KIND_LETTER = { announcement = "A", ask = "Q", answer = "R", removal = "U" }
local KIND_NAME = {}
for name, letter in pairs(KIND_LETTER) do
	KIND_NAME[letter] = name
end

local byte = string.byte

-- Reads one UTF-8 character at position i. Returns its code point and size,
-- or nil when the bytes are not valid UTF-8 (overlong forms and surrogates
-- included).
local function readCharacter(text, i)
	local first = byte(text, i)
	if first < 0x80 then
		return first, 1
	end
	local size, codePoint, minimum
	if first >= 0xC2 and first <= 0xDF then
		size, codePoint, minimum = 2, first - 0xC0, 0x80
	elseif first >= 0xE0 and first <= 0xEF then
		size, codePoint, minimum = 3, first - 0xE0, 0x800
	elseif first >= 0xF0 and first <= 0xF4 then
		size, codePoint, minimum = 4, first - 0xF0, 0x10000
	else
		return nil
	end
	for k = 1, size - 1 do
		local continuation = byte(text, i + k)
		if not continuation or continuation < 0x80 or continuation > 0xBF then
			return nil
		end
		codePoint = codePoint * 64 + (continuation - 0x80)
	end
	if codePoint < minimum or codePoint > 0x10FFFF or (codePoint >= 0xD800 and codePoint <= 0xDFFF) then
		return nil
	end
	return codePoint, size
end

-- Checks a nickname against the rules: 1 to 32 UTF-8 characters, no '|' (the
-- client's escape character: colors, textures, links), no control character.
-- Returns true, or false and why: "empty", "long", "escape", "control" or
-- "encoding".
function Protocol.checkNickname(nickname)
	if type(nickname) ~= "string" or nickname == "" then
		return false, "empty"
	end
	local count, i = 0, 1
	while i <= #nickname do
		local codePoint, size = readCharacter(nickname, i)
		if not codePoint then
			return false, "encoding"
		elseif codePoint == 0x7C then
			return false, "escape"
		elseif codePoint < 0x20 or (codePoint >= 0x7F and codePoint <= 0x9F) then
			return false, "control"
		end
		count = count + 1
		if count > Protocol.MAX_NICKNAME_CHARACTERS then
			return false, "long"
		end
		i = i + size
	end
	return true
end

local function readRevision(text)
	if text and #text <= 14 and text:match("^[1-9]%d*$") then
		return tonumber(text)
	end
end

-- Writes a message table ({ kind = ..., nickname = ..., revision = ... }, as
-- read returns it) as wire text. Trusts its input: the nickname comes from
-- Self, which checked it.
function Protocol.write(message)
	local text = Protocol.VERSION .. ":" .. KIND_LETTER[message.kind]
	if message.revision then
		text = text .. ":" .. tostring(message.revision)
	end
	if message.nickname then
		text = text .. ":" .. message.nickname
	end
	return text
end

-- Reads wire text from a peer. Returns the message table, or nil and why it
-- was dropped: "malformed", "oversized", "version" or "nickname".
function Protocol.read(text)
	if type(text) ~= "string" then
		return nil, "malformed"
	end
	if #text > Protocol.MAX_MESSAGE_BYTES then
		return nil, "oversized"
	end
	local version, letter, rest = text:match("^(%d+):(%u)(.*)$")
	if not version then
		return nil, "malformed"
	end
	if version ~= tostring(Protocol.VERSION) then
		return nil, "version"
	end
	local kind = KIND_NAME[letter]
	if kind == "ask" then
		if rest ~= "" then
			return nil, "malformed"
		end
		return { kind = kind }
	elseif kind == "removal" then
		local revision = readRevision(rest:match("^:(.*)$"))
		if not revision then
			return nil, "malformed"
		end
		return { kind = kind, revision = revision }
	elseif kind then
		local revisionText, nickname = rest:match("^:([^:]*):(.*)$")
		local revision = readRevision(revisionText)
		if not revision then
			return nil, "malformed"
		end
		if not Protocol.checkNickname(nickname) then
			return nil, "nickname"
		end
		return { kind = kind, nickname = nickname, revision = revision }
	end
	return nil, "malformed"
end
