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
--   1:N:<revision>              anonymous: the character is kept anonymous
--
-- A sync (decision 0002) adds, by whisper:
--
--   1:D:<digest>                the sender's memory hashed in buckets: 1024
--                               lowercase hexadecimal digits
--   1:I:<identity>[\n<identity>...]
--                               identities passed on, each
--                               <revision>:<name>[:<nickname>], a removal
--                               without a nickname, followed by a line
--                               G:<guid> when its character's GUID is known
--   1:E                         the sender has sent all it had to send
--
-- A message longer than 255 bytes goes as chunks of the same version, numbered
-- from 1 to their count, the pieces of its text in order:
--
--   1:C:<index>:<count>:<piece>
--
-- The version is a decimal number; a peer drops every other version. The kind
-- is one capital letter; a peer drops a kind it does not know, so later kinds
-- can join version 1 without breaking older peers. A nickname is the last
-- field, so it may hold ':'. The revision is a positive integer of at most 14
-- digits (what tostring writes exactly), without leading zeros, so it reads
-- back as the same number. A name is a full name, "First Last". A GUID has a
-- line of its own, so an older peer drops it as an identity it cannot read and
-- keeps the rest.
local _, ns = ...

local Protocol = {}
ns.Protocol = Protocol

Protocol.PREFIX = "Mnemosyne"
Protocol.VERSION = 1
Protocol.MAX_MESSAGE_BYTES = 255
Protocol.MAX_NICKNAME_CHARACTERS = 32
Protocol.MAX_NAME_BYTES = 64
Protocol.DIGEST_LENGTH = 1024
-- The longest message once its chunks are put together: a digest, or a batch of
-- identities (Sync sends them in batches that fit).
Protocol.MAX_CHUNKED_BYTES = 4096
-- Lines of identities and GUIDs in one message: 16 of the longest (a 64-byte
-- name, a 32-character nickname of 4-byte characters, a 14-digit revision; a
-- GUID's line is shorter) fit MAX_CHUNKED_BYTES. A peer's message with more is
-- dropped, so one costs the reader little.
Protocol.MAX_LINES = 16
Protocol.MAX_GUID_BYTES = 32 -- a character's GUID, "Player-<server>-<id>", is about 20

local CHUNK_HEADER_BYTES = #"1:C:99:99:" -- the longest chunk header
local CHUNK_BYTES = Protocol.MAX_MESSAGE_BYTES - CHUNK_HEADER_BYTES
local MAX_CHUNKS = math.ceil(Protocol.MAX_CHUNKED_BYTES / CHUNK_BYTES)
local CHUNK_TIMEOUT = 60 -- seconds before a message whose chunks stopped coming is dropped

local KIND_LETTER = {
	announcement = "A",
	ask = "Q",
	answer = "R",
	removal = "U",
	anonymous = "N",
	digest = "D",
	identities = "I",
	done = "E",
}
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

-- Checks text from a peer: valid UTF-8, no '|' (the client's escape character:
-- colors, textures, links), no control character, at most maxCharacters
-- UTF-8 characters. Returns true, or false and why: "empty", "long",
-- "escape", "control" or "encoding".
local function checkText(text, maxCharacters)
	if type(text) ~= "string" or text == "" then
		return false, "empty"
	end
	local count, i = 0, 1
	while i <= #text do
		local codePoint, size = readCharacter(text, i)
		if not codePoint then
			return false, "encoding"
		elseif codePoint == 0x7C then
			return false, "escape"
		elseif codePoint < 0x20 or (codePoint >= 0x7F and codePoint <= 0x9F) then
			return false, "control"
		end
		count = count + 1
		if count > maxCharacters then
			return false, "long"
		end
		i = i + size
	end
	return true
end

-- Checks a nickname against the rules: 1 to 32 UTF-8 characters, no '|', no
-- control character. Returns true, or false and why: "empty", "long",
-- "escape", "control" or "encoding".
function Protocol.checkNickname(nickname)
	return checkText(nickname, Protocol.MAX_NICKNAME_CHARACTERS)
end

-- Whether a peer's text is a full name: two words joined by one space, at most
-- 64 bytes, and text a nickname could be.
local function isFullName(name)
	return #name <= Protocol.MAX_NAME_BYTES and name:find("^%S+ %S+$") ~= nil and checkText(name, #name)
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
	if message.digest then
		return text .. ":" .. message.digest
	elseif message.identities then
		local lines = {}
		for _, identity in ipairs(message.identities) do
			local nickname = identity.nickname and ":" .. identity.nickname or ""
			lines[#lines + 1] = identity.revision .. ":" .. identity.name .. nickname
			if identity.guid then
				lines[#lines + 1] = "G:" .. identity.guid
			end
		end
		return text .. ":" .. table.concat(lines, "\n")
	end
	if message.revision then
		text = text .. ":" .. tostring(message.revision)
	end
	if message.nickname then
		text = text .. ":" .. message.nickname
	end
	return text
end

-- Splits identities into batches, each the identities of one message: at most
-- MAX_LINES lines, a GUID taking a line of its own.
function Protocol.batch(identities)
	local batches, lines = {}, Protocol.MAX_LINES
	for _, identity in ipairs(identities) do
		local cost = identity.guid and 2 or 1
		if lines + cost > Protocol.MAX_LINES then
			batches[#batches + 1] = {}
			lines = 0
		end
		local batch = batches[#batches]
		batch[#batch + 1] = identity
		lines = lines + cost
	end
	return batches
end

-- Reads one identity passed on, "<revision>:<name>[:<nickname>]". Returns it,
-- or nil and why it was dropped.
local function readIdentity(line)
	local revisionText, name, nickname = line:match("^([^:]*):([^:]*):?(.*)$")
	local revision = readRevision(revisionText)
	if not revision or not isFullName(name) then
		return nil, "malformed"
	end
	if line:sub(#revisionText + #name + 2, #revisionText + #name + 2) == ":" then
		if not Protocol.checkNickname(nickname) then
			return nil, "nickname"
		end
		return { name = name, nickname = nickname, revision = revision }
	end
	return { name = name, revision = revision }
end

-- Splits wire text into its version, kind letter and the rest. Returns them,
-- or nil and why the text was dropped: "malformed", or "version" for an older
-- version, "newer" for a newer one.
local function readHeader(text)
	local version, letter, rest = text:match("^(%d+):(%u)(.*)$")
	if not version then
		return nil, "malformed"
	end
	if version ~= tostring(Protocol.VERSION) then
		local newer = version:sub(1, 1) ~= "0" and tonumber(version) > Protocol.VERSION
		return nil, newer and "newer" or "version"
	end
	return letter, rest
end

-- Reads a whole message from a peer, chunks put together. Returns the message
-- table, or nil and why it was dropped: "malformed", "oversized", "version",
-- "newer" or "nickname".
local function readWhole(text, maxBytes)
	if type(text) ~= "string" then
		return nil, "malformed"
	end
	if #text > maxBytes then
		return nil, "oversized"
	end
	local letter, rest = readHeader(text)
	if not letter then
		return nil, rest
	end
	local kind = KIND_NAME[letter]
	if kind == "digest" then
		local digest = rest:match("^:(%x+)$")
		if not digest or #digest ~= Protocol.DIGEST_LENGTH or digest:find("%u") then
			return nil, "malformed"
		end
		return { kind = kind, digest = digest }
	elseif kind == "identities" then
		if rest:sub(1, 1) ~= ":" then
			return nil, "malformed"
		end
		-- Each identity stands alone: one that does not parse is dropped, the
		-- others kept, so one odd name never holds back the rest of a sync. A
		-- GUID goes with the identity on the line just before it; one that is
		-- not a character's is dropped, and its identity kept.
		local identities, reason, count, last = {}, nil, 0, nil
		for line in (rest:sub(2) .. "\n"):gmatch("([^\n]*)\n") do
			count = count + 1
			if count > Protocol.MAX_LINES then
				return nil, "oversized"
			end
			local guid = line:match("^G:(.*)$")
			if guid then
				if last and #guid <= Protocol.MAX_GUID_BYTES and guid:find("^Player%-%d+%-%x+$") then
					last.guid = guid
				end
				last = nil
			else
				local identity, why = readIdentity(line)
				identities[#identities + 1] = identity
				reason = reason or why
				last = identity
			end
		end
		if not identities[1] then
			return nil, reason or "malformed"
		end
		return { kind = kind, identities = identities }
	elseif kind == "ask" or kind == "done" then
		if rest ~= "" then
			return nil, "malformed"
		end
		return { kind = kind }
	elseif kind == "removal" or kind == "anonymous" then
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

-- Reads wire text from a peer, one message of at most 255 bytes. Returns the
-- message table, or nil and why it was dropped: "malformed", "oversized",
-- "version", "newer" or "nickname".
function Protocol.read(text)
	return readWhole(text, Protocol.MAX_MESSAGE_BYTES)
end

-- Splits wire text into messages of at most 255 bytes: the text itself when it
-- fits, its chunks otherwise. Trusts its input: at most MAX_CHUNKED_BYTES.
function Protocol.split(text)
	if #text <= Protocol.MAX_MESSAGE_BYTES then
		return { text }
	end
	local count = math.ceil(#text / CHUNK_BYTES)
	local chunks = {}
	for index = 1, count do
		local piece = text:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES)
		chunks[index] = Protocol.VERSION .. ":C:" .. index .. ":" .. count .. ":" .. piece
	end
	return chunks
end

local Reader = {}
Reader.__index = Reader

-- A reader puts each sender's chunks back together. clock: returns the time,
-- in seconds.
function Protocol.newReader(clock)
	return setmetatable({ clock = clock, pending = {} }, Reader)
end

-- Reads wire text from a peer. Returns the message table once it is whole;
-- nil alone while chunks of it are still to come; or nil and why it was
-- dropped: the reasons of Protocol.read, and "incomplete" for chunks out of
-- order or that stopped coming for a minute.
function Reader:read(sender, text)
	if type(text) ~= "string" or #text > Protocol.MAX_MESSAGE_BYTES then
		return Protocol.read(text)
	end
	local letter, rest = readHeader(text)
	if letter ~= "C" then
		return Protocol.read(text)
	end
	local now = self.clock()
	for other, pending in pairs(self.pending) do
		if now - pending.at > CHUNK_TIMEOUT then
			self.pending[other] = nil
		end
	end
	local indexText, countText, piece = rest:match("^:([1-9]%d?):([1-9]%d?):(.*)$")
	local index, count = tonumber(indexText), tonumber(countText)
	if not index or index > count then
		return nil, "malformed"
	end
	if count > MAX_CHUNKS then
		return nil, "oversized"
	end
	local pending = self.pending[sender]
	if index == 1 then
		pending = { count = count, pieces = {}, at = now }
		self.pending[sender] = pending
	elseif not pending or pending.count ~= count or #pending.pieces ~= index - 1 then
		self.pending[sender] = nil
		return nil, "incomplete"
	end
	pending.pieces[index] = piece
	pending.at = now
	if index < count then
		return nil
	end
	self.pending[sender] = nil
	return readWhole(table.concat(pending.pieces), Protocol.MAX_CHUNKED_BYTES)
end

-- Makes text from a peer safe to print in the chat frame, for the debug log:
-- '|' doubled, so escape sequences show as text, and control characters
-- replaced by '?'.
function Protocol.printable(text)
	return (text:gsub("|", "||"):gsub("%c", "?"))
end
