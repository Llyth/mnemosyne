-- Protocol: the wire format of Mnemosyne's addon messages, and the validation
-- of everything a peer sends. Pure: no WoW API (decision 0004).
--
-- A message is text, at most 255 bytes, sent on the prefix "Mnemosyne":
--
--   <version>:<kind>[:<fields>]
--
--   2:A:<revision>:<nickname>   announcement: a character says who plays it
--   2:Q                         ask: the receivers answer who plays them
--   2:R:<revision>:<nickname>   answer to an ask
--   2:U:<revision>              removal: the character unregistered
--   2:N:<revision>              anonymous: the character is kept anonymous
--   2:V:<version>               the version of Mnemosyne the sender runs,
--                               "1.4.1", sent with each announcement; one heard
--                               on the guild's or the group's channel is
--                               whispered back once (1.4.0 sends only that,
--                               with its tag's v: "v1.4.0")
--
-- A sync (decision 0002) adds, by whisper:
--
--   2:D:<digest>                the sender's memory hashed in buckets: 1024
--                               lowercase hexadecimal digits
--   2:I:<identity>[\n<identity>...]
--                               identities passed on, each
--                               <revision>:<name>[:<nickname>], a removal
--                               without a nickname, followed by a line
--                               G:<guid> when its character's GUID is known,
--                               then a line F when the sender vouches it
--                               heard it first-hand in the last day
--   2:H:<digest>                the sender's professions hashed in buckets,
--                               as 2:D (decision 0008), sent before it
--   2:K:<profession>[\n<profession>...]
--                               professions passed on, after the identities,
--                               each <revision>:<name>:<skill line ID>, then
--                               :<level>:<max level> unless it is a removal,
--                               then :<recipes> once the recipes were read:
--                               the recipe IDs sorted, as base-36 differences
--                               (the first ID, then each minus the one before),
--                               comma-separated; followed by a line G:<guid>
--                               when its character's GUID is known
--   2:E                         the sender has sent all it had to send
--
-- News (decision 0002) adds, on the guild channel:
--
--   2:P:<identity>              one identity a sync brought the sender new or
--                               at a later revision, as a sync passes it on,
--                               its GUID too ("P" for posted: "G" starts a
--                               GUID's line)
--
-- A message longer than 255 bytes goes as chunks of the same version, numbered
-- from 1 to their count, the pieces of its text in order, each carrying the
-- message's id, 1 to 99, which the sender's next message changes:
--
--   2:C:<id>:<index>:<count>:<piece>
--
-- The id keeps the chunks of two messages apart when they come interleaved
-- (whispers come out of order on Forever): version 1 had none, and spliced
-- them into one.
--
-- The version is a decimal number; a peer drops every other version. The kind
-- is one capital letter; a peer drops a kind it does not know, so later kinds
-- can join version 2 without breaking older peers. A nickname is the last
-- field, so it may hold ':'. The revision is a positive integer of at most 14
-- digits (what tostring writes exactly), without leading zeros, so it reads
-- back as the same number. A name is a full name, "First Last". A GUID has a
-- line of its own, so an older peer drops it as an identity it cannot read and
-- keeps the rest.
local _, ns = ...

local Protocol = {}
ns.Protocol = Protocol

Protocol.PREFIX = "Mnemosyne"
Protocol.VERSION = 2
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
-- Recipes of one profession: the largest, Tailoring, holds 471, learned or not.
Protocol.MAX_RECIPES = 600
local MAX_RECIPE_ID = 2147483647

local CHUNK_HEADER_BYTES = #"2:C:99:99:99:" -- the longest chunk header
local MAX_ID = 99
local CHUNK_BYTES = Protocol.MAX_MESSAGE_BYTES - CHUNK_HEADER_BYTES
local MAX_CHUNKS = math.ceil(Protocol.MAX_CHUNKED_BYTES / CHUNK_BYTES)
local CHUNK_TIMEOUT = 60 -- seconds before a message whose chunks stopped coming is dropped
local MAX_PENDING = 4 -- messages held per sender; a fifth drops the one heard from least lately

local KIND_LETTER = {
	announcement = "A",
	ask = "Q",
	answer = "R",
	removal = "U",
	anonymous = "N",
	digest = "D",
	identities = "I",
	done = "E",
	news = "P", -- posted; G is a GUID's line, inside identities
	professionDigest = "H", -- hashed
	professions = "K",
	version = "V",
}
local MAX_VERSION_BYTES = 20

-- The version of Mnemosyne in a release's tag, "v1.4.0" (as the packager
-- writes it in the .toc, and a 1.4.0 peer sends it) or "1.4.0": digits and dots
-- then letters, digits, dots and hyphens ("1.4.0-beta.1"), without the v.
-- Returns it, or nil for the packager's placeholder of a copy it did not build
-- or anything else.
function Protocol.releaseVersion(text)
	local version = type(text) == "string" and text:match("^v?(.*)$")
	if version and #version <= MAX_VERSION_BYTES and version:match("^%d+%.%d+%.%d+[%w%.%-]*$") then
		return version
	end
end

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
-- UTF-8 characters. Invisible and direction characters count as control
-- characters. Returns true, or false and why: "empty", "long",
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
		elseif
			codePoint < 0x20
			or (codePoint >= 0x7F and codePoint <= 0x9F)
			-- Invisible and direction characters: soft hyphen, combining
			-- grapheme joiner, Arabic letter mark, Hangul fillers (not the
			-- syllables Korean names are written in), Khmer inherent vowels,
			-- Mongolian variation selectors and vowel separator, zero-width
			-- and joiner, bidi marks, line and paragraph separators,
			-- embeddings and overrides, word joiner and isolates, Braille blank,
			-- variation selectors, zero-width no-break space, interlinear
			-- annotations, musical formatting, tags. Spaces that have a width
			-- (no-break, en, em, ideographic...) show, and pass.
			or codePoint == 0xAD
			or codePoint == 0x34F
			or codePoint == 0x61C
			or codePoint == 0x115F
			or codePoint == 0x1160
			or (codePoint >= 0x17B4 and codePoint <= 0x17B5)
			or (codePoint >= 0x180B and codePoint <= 0x180F)
			or (codePoint >= 0x200B and codePoint <= 0x200F)
			or (codePoint >= 0x2028 and codePoint <= 0x202E)
			or (codePoint >= 0x2060 and codePoint <= 0x206F)
			or codePoint == 0x2800
			or codePoint == 0x3164
			or (codePoint >= 0xFE00 and codePoint <= 0xFE0F)
			or codePoint == 0xFEFF
			or codePoint == 0xFFA0
			or (codePoint >= 0xFFF9 and codePoint <= 0xFFFB)
			or (codePoint >= 0x1D173 and codePoint <= 0x1D17A)
			or (codePoint >= 0xE0000 and codePoint <= 0xE007F)
			or (codePoint >= 0xE0100 and codePoint <= 0xE01EF)
		then
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

-- Writes an identity, and its GUID on a line of its own when known.
-- A sync's identity vouches when it says so; news never does (it goes one hop already).
local function writeIdentity(identity, vouching)
	local nickname = identity.nickname and ":" .. identity.nickname or ""
	local guid = identity.guid and "\nG:" .. identity.guid or ""
	local vouched = vouching and identity.vouched and "\nF" or ""
	return identity.revision .. ":" .. identity.name .. nickname .. guid .. vouched
end

-- Writes a message table ({ kind = ..., nickname = ..., revision = ... }, as
-- read returns it) as wire text. Trusts its input: the nickname comes from
-- Self, which checked it.
function Protocol.write(message)
	local text = Protocol.VERSION .. ":" .. KIND_LETTER[message.kind]
	if message.digest then
		return text .. ":" .. message.digest
	elseif message.version then
		return text .. ":" .. message.version
	elseif message.identities then
		local lines = {}
		for i, identity in ipairs(message.identities) do
			lines[i] = writeIdentity(identity, true)
		end
		return text .. ":" .. table.concat(lines, "\n")
	elseif message.identity then
		return text .. ":" .. writeIdentity(message.identity)
	elseif message.professions then
		local lines = {}
		for i, profession in ipairs(message.professions) do
			lines[i] = Protocol.writeProfession(profession)
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
-- MAX_LINES lines, a GUID and a vouching each taking a line of their own.
function Protocol.batch(identities)
	local batches, lines = {}, Protocol.MAX_LINES
	for _, identity in ipairs(identities) do
		local cost = 1 + (identity.guid and 1 or 0) + (identity.vouched and 1 or 0)
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

local BASE36 = "0123456789abcdefghijklmnopqrstuvwxyz"

local function base36(number)
	local text = ""
	repeat
		local digit = number % 36
		text = BASE36:sub(digit + 1, digit + 1) .. text
		number = (number - digit) / 36
	until number == 0
	return text
end

-- Writes a profession passed on ({ name, skillLine, revision, level, maxLevel,
-- recipes, guid }, a removal without a level), and its GUID on a line of its
-- own when known. Trusts its input: the recipe IDs sorted, from Self or a peer
-- checked by read.
function Protocol.writeProfession(profession)
	local text = profession.revision .. ":" .. profession.name .. ":" .. profession.skillLine
	if profession.level then
		text = text .. ":" .. profession.level .. ":" .. profession.maxLevel
		if profession.recipes then
			local previous, parts = 0, {}
			for i, recipe in ipairs(profession.recipes) do
				parts[i] = base36(recipe - previous)
				previous = recipe
			end
			text = text .. ":" .. table.concat(parts, ",")
		end
	end
	return text .. (profession.guid and "\nG:" .. profession.guid or "")
end

-- Splits professions into batches, each the professions of one message that a
-- peer reads whole (at most MAX_CHUNKED_BYTES). One that could never fit is
-- left out.
-- shortcut: a profession past about 4 KB (over 1,000 recipes) never goes; split
-- its recipes over lines if professions ever grow that large.
function Protocol.batchProfessions(professions)
	local limit = Protocol.MAX_CHUNKED_BYTES - #"2:K:"
	local batches, bytes = {}, limit
	for _, profession in ipairs(professions) do
		local cost = #Protocol.writeProfession(profession) + 1
		if cost <= limit then
			if bytes + cost > limit then
				batches[#batches + 1] = {}
				bytes = 0
			end
			local batch = batches[#batches]
			batch[#batch + 1] = profession
			bytes = bytes + cost
		end
	end
	return batches
end

-- Reads a decimal number of at most maxDigits digits, without leading zeros.
local function readNumber(text, maxDigits)
	if text and #text <= maxDigits and (text == "0" or text:match("^[1-9]%d*$")) then
		return tonumber(text)
	end
end

-- Reads recipe IDs written by writeProfession: at most MAX_RECIPES, each
-- difference 1 to 6 base-36 digits without leading zeros, so the IDs come out
-- sorted, each once. Returns them, or nil.
local function readRecipes(text)
	local recipes, previous = {}, 0
	if text == "" then
		return recipes
	end
	for token in (text .. ","):gmatch("([^,]*),") do
		if #recipes >= Protocol.MAX_RECIPES or #token > 6 or not token:match("^[1-9a-z][0-9a-z]*$") then
			return nil
		end
		previous = previous + tonumber(token, 36)
		if previous > MAX_RECIPE_ID then
			return nil
		end
		recipes[#recipes + 1] = previous
	end
	return recipes
end

-- Reads one profession passed on (writeProfession's line). Returns it, or nil.
local function readProfession(line)
	local revisionText, name, rest = line:match("^([^:]*):([^:]*):(.*)$")
	local revision = readRevision(revisionText)
	if not revision or not isFullName(name) then
		return nil
	end
	local skillText, levelText, maxText, recipesText = rest:match("^([^:]*):?([^:]*):?([^:]*):?(.*)$")
	local skillLine = readNumber(skillText, 6)
	if not skillLine or skillLine == 0 then
		return nil
	elseif rest == skillText then
		return { name = name, skillLine = skillLine, revision = revision }
	end
	local level, maxLevel = readNumber(levelText, 4), readNumber(maxText, 4)
	if not level or not maxLevel or maxLevel == 0 or level > maxLevel then
		return nil
	end
	local profession = { name = name, skillLine = skillLine, revision = revision, level = level, maxLevel = maxLevel }
	if #rest > #skillText + #levelText + #maxText + 2 then
		profession.recipes = readRecipes(recipesText)
		if not profession.recipes then
			return nil
		end
	end
	return profession
end

-- Reads a GUID passed on with an identity. Returns it, or nil when it is not a
-- character's.
local function readGuid(text)
	if #text <= Protocol.MAX_GUID_BYTES and text:find("^Player%-%d+%-%x+$") then
		return text
	end
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
	if kind == "digest" or kind == "professionDigest" then
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
		-- not a character's is dropped, and its identity kept. A line F after them
		-- vouches for that identity; one with no identity before it is dropped.
		local identities, reason, count, last, vouchable = {}, nil, 0, nil, nil
		for line in (rest:sub(2) .. "\n"):gmatch("([^\n]*)\n") do
			count = count + 1
			if count > Protocol.MAX_LINES then
				return nil, "oversized"
			end
			local guid = line:match("^G:(.*)$")
			if guid then
				if last then
					last.guid = readGuid(guid)
				end
				last = nil
			elseif line == "F" then
				if vouchable then
					vouchable.vouched = true
				end
				last, vouchable = nil, nil
			else
				local identity, why = readIdentity(line)
				identities[#identities + 1] = identity
				reason = reason or why
				last, vouchable = identity, identity
			end
		end
		if not identities[1] then
			return nil, reason or "malformed"
		end
		return { kind = kind, identities = identities }
	elseif kind == "professions" then
		if rest:sub(1, 1) ~= ":" then
			return nil, "malformed"
		end
		-- Each profession stands alone, as an identity does: one that does not
		-- parse is dropped, the others kept; a GUID goes with the profession on
		-- the line just before it.
		local professions, last = {}, nil
		for line in (rest:sub(2) .. "\n"):gmatch("([^\n]*)\n") do
			local guid = line:match("^G:(.*)$")
			if guid then
				if last then
					last.guid = readGuid(guid)
				end
				last = nil
			else
				last = readProfession(line)
				professions[#professions + 1] = last
			end
		end
		if not professions[1] then
			return nil, "malformed"
		end
		return { kind = kind, professions = professions }
	elseif kind == "news" then
		if rest:sub(1, 1) ~= ":" then
			return nil, "malformed"
		end
		-- Its GUID, if any, as in identities: one that is not a character's is
		-- dropped, and the identity kept.
		local line, guid = rest:sub(2):match("^([^\n]*)\nG:(.*)$")
		local identity, reason = readIdentity(line or rest:sub(2))
		if not identity then
			return nil, reason
		end
		identity.guid = guid and readGuid(guid)
		return { kind = kind, identity = identity }
	elseif kind == "version" then
		local version = Protocol.releaseVersion(rest:match("^:(.*)$"))
		if not version then
			return nil, "malformed"
		end
		return { kind = kind, version = version }
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

local Writer = {}
Writer.__index = Writer

-- A writer splits a sender's messages, each chunked one under the next id.
function Protocol.newWriter()
	return setmetatable({ id = 0 }, Writer)
end

-- Splits wire text into messages of at most 255 bytes: the text itself when it
-- fits, its chunks otherwise. Trusts its input: at most MAX_CHUNKED_BYTES.
function Writer:split(text)
	if #text <= Protocol.MAX_MESSAGE_BYTES then
		return { text }
	end
	self.id = self.id % MAX_ID + 1
	local header = Protocol.VERSION .. ":C:" .. self.id .. ":"
	local count = math.ceil(#text / CHUNK_BYTES)
	local chunks = {}
	for index = 1, count do
		local piece = text:sub((index - 1) * CHUNK_BYTES + 1, index * CHUNK_BYTES)
		chunks[index] = header .. index .. ":" .. count .. ":" .. piece
	end
	return chunks
end

local Reader = {}
Reader.__index = Reader

-- A reader puts each sender's chunks back together, message by message.
-- clock: returns the time, in seconds.
function Protocol.newReader(clock)
	return setmetatable({ clock = clock, pending = {} }, Reader)
end

-- Reads wire text from a peer. Returns the message table once it is whole;
-- nil alone while chunks of it are still to come; or nil and why it was
-- dropped: the reasons of Protocol.read. Chunks that stopped coming for a
-- minute are let go, and so is the message heard from least lately when a
-- sender starts more than MAX_PENDING at once.
function Reader:read(sender, text)
	if type(text) ~= "string" or #text > Protocol.MAX_MESSAGE_BYTES then
		return Protocol.read(text)
	end
	local letter, rest = readHeader(text)
	if letter ~= "C" then
		return Protocol.read(text)
	end
	local now = self.clock()
	for other, messages in pairs(self.pending) do
		for id, pending in pairs(messages) do
			if now - pending.at > CHUNK_TIMEOUT then
				messages[id] = nil
			end
		end
		if not next(messages) then
			self.pending[other] = nil
		end
	end
	local id, indexText, countText, piece = rest:match("^:([1-9]%d?):([1-9]%d?):([1-9]%d?):(.*)$")
	local index, count = tonumber(indexText), tonumber(countText)
	if not index or index > count then
		return nil, "malformed"
	end
	if count > MAX_CHUNKS then
		return nil, "oversized"
	end
	-- Chunks may come in any order (addon whispers do on Forever), those of
	-- several messages interleaved: each message keeps its own. A chunk of
	-- another count, or one already held, starts its message over: the
	-- sender's ids came round again.
	local messages = self.pending[sender] or {}
	self.pending[sender] = messages
	local pending = messages[id]
	if not pending then
		local held, oldest = 0, nil
		for other, message in pairs(messages) do
			held = held + 1
			if not oldest or message.at < messages[oldest].at then
				oldest = other
			end
		end
		if held >= MAX_PENDING then
			messages[oldest] = nil
		end
	end
	if not pending or pending.count ~= count or pending.pieces[index] then
		pending = { count = count, pieces = {}, held = 0 }
		messages[id] = pending
	end
	pending.pieces[index] = piece
	pending.held = pending.held + 1
	pending.at = now
	if pending.held < count then
		return nil
	end
	messages[id] = nil
	if not next(messages) then
		self.pending[sender] = nil
	end
	return readWhole(table.concat(pending.pieces), Protocol.MAX_CHUNKED_BYTES)
end

-- Makes text from a peer safe to print in the chat frame, for the debug log:
-- '|' doubled, so escape sequences show as text, and control characters
-- replaced by '?'.
function Protocol.printable(text)
	return (text:gsub("|", "||"):gsub("%c", "?"))
end
