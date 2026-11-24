local Protocol = require("spec.helpers.addon")("Protocol").Protocol

local function roundTrip(message)
	return Protocol.read(Protocol.write(message))
end

describe("Protocol", function()
	describe("writes what it reads", function()
		it("carries an announcement", function()
			local message = { kind = "announcement", nickname = "Tony", revision = 1731500000 }
			assert.same(message, roundTrip(message))
		end)

		it("carries an ask", function()
			assert.same({ kind = "ask" }, roundTrip({ kind = "ask" }))
		end)

		it("carries an answer", function()
			local message = { kind = "answer", nickname = "Tony", revision = 1731500000 }
			assert.same(message, roundTrip(message))
		end)

		it("carries a removal", function()
			local message = { kind = "removal", revision = 1731500001 }
			assert.same(message, roundTrip(message))
		end)

		it("carries the version of Mnemosyne a peer runs", function()
			local message = { kind = "version", version = "1.4.0" }
			assert.same(message, roundTrip(message))
			assert.equal("2:V:1.4.0", Protocol.write(message))
		end)

		it("carries an anonymous character's answer", function()
			local message = { kind = "anonymous", revision = 1731500001 }
			assert.same(message, roundTrip(message))
			assert.equal("2:N:1731500001", Protocol.write(message))
		end)

		it("keeps a nickname as typed, accents, other alphabets and separators included", function()
			for _, nickname in ipairs({ "Éloïse", "トニー", "Tony: the tank", " Tony ", "😀" }) do
				local message = { kind = "announcement", nickname = nickname, revision = 7 }
				assert.same(message, roundTrip(message))
			end
		end)

		it("fits the longest nickname in one message", function()
			local text = Protocol.write({
				kind = "announcement",
				nickname = string.rep("😀", 32),
				revision = 99999999999999,
			})
			assert.is_true(#text <= Protocol.MAX_MESSAGE_BYTES)
		end)

		it("names the prefix Mnemosyne, within the client's 16 characters", function()
			assert.equal("Mnemosyne", Protocol.PREFIX)
			assert.is_true(#Protocol.PREFIX <= 16)
		end)
	end)

	describe("drops what it cannot trust", function()
		local function assertDropped(text, reason)
			local message, why = Protocol.read(text)
			assert.is_nil(message, text)
			if reason then
				assert.equal(reason, why, text)
			end
		end

		it("drops a message from an older version", function()
			assertDropped("0:Q", "version")
			assertDropped("01:Q", "version")
			assertDropped("1:Q", "version")
		end)

		it("drops a message from a newer version, and says it is newer", function()
			assertDropped("3:A:5:Tony", "newer")
			assertDropped("10:Q", "newer")
		end)

		it("drops a message without a version", function()
			for _, text in ipairs({ "", "Q", "A:5:Tony", ":Q", "hello", "1", "1Q" }) do
				assertDropped(text, "malformed")
			end
		end)

		it("drops a message longer than 255 bytes", function()
			assertDropped("2:A:5:" .. string.rep("a", 250), "oversized")
		end)

		it("drops a message that is not text", function()
			assertDropped(nil, "malformed")
			assertDropped(42, "malformed")
			assertDropped({}, "malformed")
		end)

		it("drops a message of an unknown kind", function()
			assertDropped("2:Z:5:Tony", "malformed")
			assertDropped("2:a:5:Tony", "malformed")
			assertDropped("2:AA:5:Tony", "malformed")
		end)

		it("drops a version that is not one", function()
			assertDropped("2:V", "malformed")
			assertDropped("2:V:", "malformed")
			assertDropped("2:V:1.4", "malformed")
			assertDropped("2:V:v1.4.0", "malformed")
			assertDropped("2:V:1.4.0 beta", "malformed")
			assertDropped("2:V:1.4.0-" .. ("a"):rep(20), "malformed")
			assert.same({ kind = "version", version = "1.4.0-beta.1" }, Protocol.read("2:V:1.4.0-beta.1"))
		end)

		it("tells a version that can go out from one that cannot", function()
			assert.is_true(Protocol.isVersion("1.4.0"))
			assert.is_false(Protocol.isVersion("@project-version@"))
			assert.is_false(Protocol.isVersion(nil))
		end)

		it("drops an announcement or answer without a valid revision", function()
			for _, kind in ipairs({ "A", "R" }) do
				for _, revision in ipairs({ "", "abc", "0", "-5", "1.5", "1e9", "007", "123456789012345", " 5" }) do
					assertDropped("2:" .. kind .. ":" .. revision .. ":Tony", "malformed")
				end
				assertDropped("2:" .. kind .. ":5", "malformed")
			end
		end)

		it("drops a removal without a valid revision, or with a nickname", function()
			assertDropped("2:U", "malformed")
			assertDropped("2:U:", "malformed")
			assertDropped("2:U:abc", "malformed")
			assertDropped("2:U:5:Tony", "malformed")
		end)

		it("drops an anonymous answer without a valid revision, or with a nickname", function()
			assertDropped("2:N", "malformed")
			assertDropped("2:N:", "malformed")
			assertDropped("2:N:0", "malformed")
			assertDropped("2:N:abc", "malformed")
			assertDropped("2:N:5:Tony", "malformed")
		end)

		it("drops an ask with anything after it", function()
			assertDropped("2:Q:", "malformed")
			assertDropped("2:Q:Tony", "malformed")
		end)

		it("drops a nickname with an escape sequence", function()
			for _, nickname in ipairs({
				"|cffff0000Tony|r",
				"|Hplayer:Tony|h[Tony]|h",
				"|TInterface\\Icons\\X:0|t",
				"|",
			}) do
				assertDropped("2:A:5:" .. nickname, "nickname")
				assertDropped("2:R:5:" .. nickname, "nickname")
			end
		end)

		it("drops a nickname with a control character", function()
			for _, nickname in ipairs({ "To\nny", "To\0ny", "Tony\r", "\tTony", "To\127ny", "To\194\133ny" }) do
				assertDropped("2:A:5:" .. nickname, "nickname")
			end
		end)

		it("drops a nickname that is not valid UTF-8", function()
			local invalid = {
				"\255Tony", -- never a UTF-8 byte
				"Tony\195", -- cut in the middle of a character
				"\192\128", -- overlong encoding of NUL
				"\224\128\175", -- overlong encoding of '/'
				"\237\160\128", -- a UTF-16 surrogate
				"\244\144\128\128", -- past U+10FFFF
				"\128Tony", -- a continuation byte alone
			}
			for _, nickname in ipairs(invalid) do
				assertDropped("2:A:5:" .. nickname, "nickname")
			end
		end)

		it("drops a nickname longer than 32 characters", function()
			assertDropped("2:A:5:" .. string.rep("é", 33), "nickname")
		end)

		it("drops an empty nickname", function()
			assertDropped("2:A:5:", "nickname")
		end)

		it("drops a nickname that is only a zero-width space", function()
			assertDropped("2:A:5:\226\128\139", "nickname")
		end)

		it("drops a nickname with a right-to-left override inside", function()
			assertDropped("2:A:5:To\226\128\174ny", "nickname")
		end)

		it("drops a nickname with a line separator inside", function()
			assertDropped("2:A:5:To\226\128\168ny", "nickname")
		end)
	end)

	describe("checks a nickname", function()
		it("accepts 32 characters, counted as characters and not bytes", function()
			assert.is_true(Protocol.checkNickname(string.rep("é", 32)))
			assert.is_true(Protocol.checkNickname(string.rep("😀", 32)))
		end)

		it("accepts the letters of every alphabet", function()
			for _, nickname in ipairs({ "Zoë", "Élodie", "Дмитрий", "토니", "東京", "e\204\129" }) do
				assert.is_true(Protocol.checkNickname(nickname))
			end
		end)

		it("says why it refuses a nickname", function()
			local cases = {
				[""] = "empty",
				[string.rep("a", 33)] = "long",
				["|cffTony"] = "escape",
				["To\nny"] = "control",
				["To\255ny"] = "encoding",
				["To\194\173ny"] = "control", -- soft hyphen
				["To\239\187\191ny"] = "control", -- zero-width no-break space
				["To\226\129\166ny"] = "control", -- left-to-right isolate
			}
			for nickname, reason in pairs(cases) do
				local ok, why = Protocol.checkNickname(nickname)
				assert.is_false(ok)
				assert.equal(reason, why)
			end
		end)

		it("refuses what is not text", function()
			assert.is_false((Protocol.checkNickname(nil)))
			assert.is_false((Protocol.checkNickname(42)))
		end)
	end)

	describe("makes a peer's text printable", function()
		it("shows escape sequences as text instead of running them", function()
			assert.equal("2:A:5:||cffff0000Tony||r", Protocol.printable("2:A:5:|cffff0000Tony|r"))
			assert.equal("||Hplayer:X||h[X]||h", Protocol.printable("|Hplayer:X|h[X]|h"))
		end)

		it("replaces control characters", function()
			assert.equal("To?ny?", Protocol.printable("To\nny\0"))
		end)

		it("keeps other text as it is", function()
			assert.equal("2:R:5:Éloïse: the tank", Protocol.printable("2:R:5:Éloïse: the tank"))
		end)
	end)
end)

describe("Protocol for syncs", function()
	local DIGEST = string.rep("0123abcd", 128)

	-- Reads text the way a peer gets it: as chunks when it is long.
	local function readSplit(text)
		local reader = Protocol.newReader(function()
			return 0
		end)
		local message, why
		for _, chunk in ipairs(Protocol.newWriter():split(text)) do
			message, why = reader:read("Hugh Jass", chunk)
		end
		return message, why
	end

	local function roundTripSplit(message)
		return readSplit(Protocol.write(message))
	end

	local function assertDropped(text, reason)
		local message, why = readSplit(text)
		assert.is_nil(message, text)
		assert.equal(reason, why, text)
	end

	describe("writes what it reads", function()
		it("carries a digest", function()
			assert.same({ kind = "digest", digest = DIGEST }, roundTripSplit({ kind = "digest", digest = DIGEST }))
		end)

		it("carries identities, nicknames and removals, in order", function()
			local message = {
				kind = "identities",
				identities = {
					{ name = "Hugh Jass", nickname = "Tony: the tank", revision = 900 },
					{ name = "Anna Conda", revision = 901 },
					{ name = "Élise Bérénice", nickname = "Zoé", revision = 902 },
				},
			}
			assert.same(message, roundTripSplit(message))
		end)

		it("carries the GUID of an identity that has one", function()
			local message = {
				kind = "identities",
				identities = {
					{ name = "Hugh Jass", nickname = "Tony", revision = 900, guid = "Player-1-0A1B2C3D" },
					{ name = "Anna Conda", revision = 901 },
					{ name = "Cole Slaw", revision = 902, guid = "Player-4184-00000001" },
				},
			}
			assert.same(message, roundTripSplit(message))
		end)

		it("puts each GUID on a line of its own, which an older peer drops as an identity it cannot read", function()
			local text = Protocol.write({
				kind = "identities",
				identities = { { name = "Hugh Jass", nickname = "Tony", revision = 900, guid = "Player-1-0A1B2C3D" } },
			})
			assert.equal("2:I:900:Hugh Jass:Tony\nG:Player-1-0A1B2C3D", text)
			assert.is_nil(("G:Player-1-0A1B2C3D"):match("^[1-9]%d*:"))
		end)

		it("carries that the sender heard an identity first-hand lately, on a line after its GUID's", function()
			local message = {
				kind = "identities",
				identities = {
					{
						name = "Hugh Jass",
						nickname = "Tony",
						revision = 900,
						guid = "Player-1-0A1B2C3D",
						vouched = true,
					},
					{ name = "Anna Conda", revision = 901, vouched = true },
					{ name = "Cole Slaw", revision = 902 },
				},
			}
			assert.same(message, roundTripSplit(message))
			-- An older peer drops the line as an identity it cannot read, after the GUID took its place.
			assert.equal(
				"2:I:900:Hugh Jass:Tony\nG:Player-1-0A1B2C3D\nF",
				Protocol.write({ kind = "identities", identities = { message.identities[1] } })
			)
		end)

		it("counts a vouched identity's line toward the 16 lines of a batch", function()
			local identities = {}
			for i = 1, Protocol.MAX_LINES do
				identities[i] =
					{ name = "Peer" .. i .. " Last", revision = 1, guid = "Player-1-00000001", vouched = true }
			end
			assert.equal(5, #Protocol.batch(identities)[1]) -- 3 lines each: 5 fit in 16
		end)

		it("never vouches in guild news, which goes one hop already", function()
			local identity = { name = "Hugh Jass", nickname = "Tony", revision = 900, vouched = true }
			assert.equal("2:P:900:Hugh Jass:Tony", Protocol.write({ kind = "news", identity = identity }))
		end)

		it("drops a vouched line with no identity before it, and keeps the rest", function()
			assert.same(
				{ kind = "identities", identities = { { name = "Hugh Jass", revision = 900 } } },
				readSplit("2:I:F\n900:Hugh Jass")
			)
		end)

		it("carries the end of a sync", function()
			assert.same({ kind = "done" }, roundTripSplit({ kind = "done" }))
		end)
	end)

	describe("drops what it cannot trust", function()
		it("drops a digest of the wrong size or not in hexadecimal", function()
			assertDropped("2:D", "malformed")
			assertDropped("2:D:" .. DIGEST:sub(2), "malformed")
			assertDropped("2:D:" .. DIGEST .. "0", "malformed")
			assertDropped("2:D:" .. DIGEST:upper(), "malformed")
			assertDropped("2:D:" .. DIGEST:sub(2) .. "g", "malformed")
		end)

		it("drops identities without any", function()
			assertDropped("2:I", "malformed")
			assertDropped("2:I:", "malformed")
		end)

		it("drops an identity without a valid revision", function()
			assertDropped("2:I:0:Anna Conda", "malformed")
			assertDropped("2:I:abc:Hugh Jass:Tony", "malformed")
			assertDropped("2:I:Hugh Jass:Tony", "malformed")
		end)

		it("drops identities that hold more than a batch, so one message never costs more than 16", function()
			local lines = {}
			for i = 1, Protocol.MAX_LINES + 1 do
				lines[i] = "1:Peer" .. i .. " Last"
			end
			assertDropped("2:I:" .. table.concat(lines, "\n"), "oversized")
			lines[#lines] = nil
			assert.equal(Protocol.MAX_LINES, #readSplit("2:I:" .. table.concat(lines, "\n")).identities)
		end)

		it("counts a GUID's line toward the 16 lines of a batch", function()
			local lines = {}
			for i = 1, Protocol.MAX_LINES / 2 do
				lines[#lines + 1] = "1:Peer" .. i .. " Last"
				lines[#lines + 1] = "G:Player-1-0000000" .. i
			end
			assert.equal(Protocol.MAX_LINES / 2, #readSplit("2:I:" .. table.concat(lines, "\n")).identities)
			lines[#lines + 1] = "1:Hugh Jass"
			assertDropped("2:I:" .. table.concat(lines, "\n"), "oversized")
		end)

		it("drops a GUID that does not look like a character's, and keeps its identity", function()
			for _, guid in ipairs({
				"",
				"Creature-0-1-2-3-4-5",
				"Player-1-|cffff0000",
				"Player-1-0A1B2C3D\0",
				"Player--0A1B2C3D",
				"Player-1-" .. string.rep("0", 30),
			}) do
				assert.same(
					{ kind = "identities", identities = { { name = "Hugh Jass", revision = 900 } } },
					readSplit("2:I:900:Hugh Jass\nG:" .. guid),
					guid
				)
			end
		end)

		it("gives a GUID only to the identity on the line just before it", function()
			assert.same(
				{ kind = "identities", identities = { { name = "Hugh Jass", revision = 900 } } },
				readSplit("2:I:G:Player-1-00000001\n900:Hugh Jass\n0:Anna Conda\nG:Player-1-00000002")
			)
			assert.same({
				kind = "identities",
				identities = { { name = "Hugh Jass", revision = 900, guid = "Player-1-00000001" } },
			}, readSplit("2:I:900:Hugh Jass\nG:Player-1-00000001\nG:Player-1-00000002"))
		end)

		it("drops identities made of GUIDs alone", function()
			assertDropped("2:I:G:Player-1-00000001", "malformed")
		end)

		it("drops only the identities that do not parse, and keeps the others", function()
			assert.same(
				{ kind = "identities", identities = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } } },
				readSplit("2:I:0:Anna Conda\n900:Hugh Jass:Tony\n900:Cole Slaw:|cffff0000Cole|r\n\n900:Barb")
			)
		end)

		it("drops an identity whose character's name is not a full name", function()
			for _, name in ipairs({
				"Hugh",
				"",
				" Hugh Jass",
				"Hugh Jass ",
				"Hugh  Jass",
				"Hugh Jass Jr",
				"|cffff0000Hugh|r Jass",
				"Hugh\0 Jass",
				"Hugh \255Jass",
				"Hugh " .. string.rep("a", 60),
			}) do
				assertDropped("2:I:900:" .. name .. ":Tony", "malformed")
			end
		end)

		it("drops an identity whose nickname breaks the rules", function()
			assertDropped("2:I:900:Hugh Jass:", "nickname")
			assertDropped("2:I:900:Hugh Jass:|cffff0000Tony|r", "nickname")
			assertDropped("2:I:900:Hugh Jass:" .. string.rep("a", 33), "nickname")
		end)

		it("drops the end of a sync with anything after it", function()
			assertDropped("2:E:", "malformed")
			assertDropped("2:E:Tony", "malformed")
		end)
	end)

	describe("splits a long message into chunks", function()
		local now, reader, writer

		before_each(function()
			now = 1000
			reader = Protocol.newReader(function()
				return now
			end)
			writer = Protocol.newWriter()
		end)

		-- count identities, with long nicknames when long, for a message of more chunks.
		local function identities(count, long)
			local nickname = long and ("Tony"):rep(8) or "Tony"
			local list = {}
			for i = 1, count do
				list[i] =
					{ name = "Hugh Jass" .. string.char(96 + i % 26), nickname = nickname, revision = 1731500000 + i }
			end
			return { kind = "identities", identities = list }
		end

		local function deliver(sender, texts)
			local message, reason
			for _, text in ipairs(texts) do
				message, reason = reader:read(sender, text)
			end
			return message, reason
		end

		it("sends a short message as it is", function()
			assert.same({ "2:Q" }, writer:split("2:Q"))
			assert.same({ kind = "ask" }, reader:read("Hugh Jass", "2:Q"))
		end)

		it("splits a long message into chunks of at most 255 bytes, and reassembles them", function()
			local message = identities(16, true)
			local chunks = writer:split(Protocol.write(message))
			assert.is_true(#chunks > 1)
			for i, chunk in ipairs(chunks) do
				assert.is_true(#chunk <= Protocol.MAX_MESSAGE_BYTES)
				if i < #chunks then
					assert.is_nil(reader:read("Hugh Jass", chunk))
				end
			end
			assert.same(message, reader:read("Hugh Jass", chunks[#chunks]))
		end)

		it("reassembles each sender's chunks apart", function()
			local a = writer:split(Protocol.write(identities(16, true)))
			local b = writer:split(Protocol.write(identities(16)))
			for i = 1, #b - 1 do
				reader:read("Anna Conda", a[i])
				reader:read("Barb Dwyer", b[i])
			end
			assert.same(identities(16), reader:read("Barb Dwyer", b[#b]))
			assert.same(identities(16, true), deliver("Anna Conda", { unpack(a, #b) }))
		end)

		it("reassembles a message whose chunks come out of order, as whispers can on Forever", function()
			local chunks = writer:split(Protocol.write(identities(16, true)))
			chunks[2], chunks[3] = chunks[3], chunks[2]
			chunks[1], chunks[#chunks] = chunks[#chunks], chunks[1]
			assert.same(identities(16, true), deliver("Hugh Jass", chunks))
		end)

		it("never splices two messages whose chunks interleave", function()
			local function batch(nickname)
				local message = identities(10)
				for _, identity in ipairs(message.identities) do
					identity.nickname = nickname
				end
				return message
			end
			local one, two = batch(("Anna"):rep(8)), batch(("Barb"):rep(8))
			local a, b = writer:split(Protocol.write(one)), writer:split(Protocol.write(two))
			assert.equal(3, #a)
			assert.equal(3, #b)
			local read = {}
			for _, chunk in ipairs({ a[1], a[2], b[1], a[3], b[2], b[3] }) do
				read[#read + 1] = reader:read("Hugh Jass", chunk)
			end
			assert.same({ one, two }, read)
		end)

		it("starts over when a chunk it already holds comes again", function()
			local chunks = writer:split(Protocol.write(identities(16, true)))
			reader:read("Hugh Jass", chunks[2])
			reader:read("Hugh Jass", chunks[2])
			for i = 1, #chunks - 1 do
				if i ~= 2 then
					assert.is_nil(reader:read("Hugh Jass", chunks[i]))
				end
			end
			assert.same(identities(16, true), reader:read("Hugh Jass", chunks[#chunks]))
		end)

		it("reads the sender's next message when one was cut short", function()
			local cut = writer:split(Protocol.write(identities(16, true)))
			reader:read("Hugh Jass", cut[1])
			reader:read("Hugh Jass", cut[2])
			assert.same(identities(16), deliver("Hugh Jass", writer:split(Protocol.write(identities(16)))))
		end)

		it("holds 4 messages of a sender at once, and lets go the one heard from least lately", function()
			local messages = {}
			for i = 1, 5 do
				messages[i] = writer:split(Protocol.write(identities(16, true)))
				now = now + 1
				reader:read("Hugh Jass", messages[i][1])
			end
			assert.same(identities(16, true), deliver("Hugh Jass", { unpack(messages[2], 2) }))
			assert.is_nil(deliver("Hugh Jass", { unpack(messages[1], 2) }))
		end)

		it("gives each long message the next id, from 1 to 99 and round again", function()
			local text = Protocol.write(identities(16, true))
			local ids = {}
			for i = 1, 100 do
				ids[i] = writer:split(text)[1]:match("^2:C:(%d+):")
			end
			assert.same({ "1", "2", "99", "1" }, { ids[1], ids[2], ids[99], ids[100] })
		end)

		it("drops a message whose last chunks never come", function()
			local chunks = writer:split(Protocol.write(identities(16, true)))
			for i = 1, #chunks - 1 do
				reader:read("Hugh Jass", chunks[i])
			end
			now = now + 61
			assert.is_nil(reader:read("Hugh Jass", chunks[#chunks]))
		end)

		it("drops a message announced longer than it may be", function()
			local message, reason = reader:read("Hugh Jass", "2:C:1:1:99:1:Q")
			assert.is_nil(message)
			assert.equal("oversized", reason)
		end)

		it("drops a chunk that does not parse", function()
			for _, text in ipairs({
				"2:C",
				"2:C:1",
				"2:C:1:1",
				"2:C:1:0:2:x",
				"2:C:1:3:2:x",
				"2:C:1:a:2:x",
				"2:C:1:01:2:x",
				"2:C:0:1:2:x",
				"2:C:01:1:2:x",
				"2:C:100:1:2:x",
				"2:C:a:1:2:x",
				"2:C::1:2:x",
			}) do
				local message, reason = reader:read("Hugh Jass", text)
				assert.is_nil(message, text)
				assert.equal("malformed", reason, text)
			end
		end)

		it("drops a reassembled message that does not parse", function()
			local message, reason = deliver("Hugh Jass", { "2:C:1:1:2:2:I:900:Hugh", "2:C:1:2:2:" })
			assert.is_nil(message)
			assert.equal("malformed", reason)
		end)

		it("never reassembles a chunk inside a chunk", function()
			local message, reason = deliver("Hugh Jass", { "2:C:1:1:2:2:C:1:1:", "2:C:1:2:2:1:1:2:Q" })
			assert.is_nil(message)
			assert.equal("malformed", reason)
		end)

		it("drops a chunk from a newer version, and says it is newer", function()
			local message, reason = reader:read("Hugh Jass", "3:C:1:1:2:x")
			assert.is_nil(message)
			assert.equal("newer", reason)
		end)

		it("drops a chunk from version 1, which had no message id", function()
			local message, reason = reader:read("Hugh Jass", "1:C:1:2:x")
			assert.is_nil(message)
			assert.equal("version", reason)
		end)
	end)
end)

describe("Protocol for news", function()
	it("carries one identity, a nickname or a removal, and its GUID when known", function()
		for _, identity in ipairs({
			{ name = "Hugh Jass", nickname = "Tony: the tank", revision = 900 },
			{ name = "Anna Conda", revision = 901 },
			{ name = "Cole Slaw", nickname = "Cole", revision = 902, guid = "Player-1-0A1B2C3D" },
			{ name = "Barb Dwyer", revision = 903, guid = "Player-4184-00000001" },
		}) do
			local message = { kind = "news", identity = identity }
			assert.same(message, roundTrip(message))
		end
		assert.equal(
			"2:P:900:Hugh Jass:Tony",
			Protocol.write({
				kind = "news",
				identity = { name = "Hugh Jass", nickname = "Tony", revision = 900 },
			})
		)
		assert.equal(
			"2:P:900:Hugh Jass:Tony\nG:Player-1-0A1B2C3D",
			Protocol.write({
				kind = "news",
				identity = { name = "Hugh Jass", nickname = "Tony", revision = 900, guid = "Player-1-0A1B2C3D" },
			})
		)
	end)

	it("keeps the news kind apart from the GUID lines of identities: 1:G is no message", function()
		local message, why = Protocol.read("2:G:900:Hugh Jass:Tony")
		assert.is_nil(message)
		assert.equal("malformed", why)
	end)

	it("fits the longest identity and GUID in one message", function()
		local text = Protocol.write({
			kind = "news",
			identity = {
				name = "Hugh " .. string.rep("a", 59),
				nickname = string.rep("😀", 32),
				revision = 99999999999999,
				guid = "Player-1-" .. string.rep("F", Protocol.MAX_GUID_BYTES - #"Player-1-"),
			},
		})
		assert.is_true(#text <= Protocol.MAX_MESSAGE_BYTES)
	end)

	it("drops a GUID in news that does not look like a character's, and keeps its identity", function()
		for _, guid in ipairs({ "", "Creature-0-1-2-3-4-5", "Player-1-|cffff0000", "Player-1-" .. string.rep("0", 30) }) do
			assert.same(
				{ kind = "news", identity = { name = "Hugh Jass", revision = 900 } },
				Protocol.read("2:P:900:Hugh Jass\nG:" .. guid),
				guid
			)
		end
	end)

	it("drops news that does not hold exactly one valid identity", function()
		for text, reason in pairs({
			["2:P"] = "malformed",
			["2:P:"] = "malformed",
			["2:P:900"] = "malformed",
			["2:P:0:Hugh Jass:Tony"] = "malformed",
			["2:P:900:Hugh:Tony"] = "malformed",
			["2:P:900:Hugh Jass:"] = "nickname",
			["2:P:900:Hugh Jass:|cffff0000Tony|r"] = "nickname",
			["2:P:900:Hugh Jass:Tony\n901:Anna Conda"] = "nickname",
			["2:P:G:Player-1-00000001"] = "malformed",
		}) do
			local message, why = Protocol.read(text)
			assert.is_nil(message, text)
			assert.equal(reason, why, text)
		end
	end)
end)

describe("Protocol for professions", function()
	local function readWhole(text)
		local reader = Protocol.newReader(function()
			return 0
		end)
		local message, why
		for _, chunk in ipairs(Protocol.newWriter():split(text)) do
			message, why = reader:read("Anna Conda", chunk)
		end
		return message, why
	end

	local tailoring = {
		name = "Hugh Jass",
		skillLine = 197,
		revision = 1731500000,
		level = 75,
		maxLevel = 150,
		recipes = { 2385, 2386, 1263032 },
	}

	it("carries a digest of professions", function()
		local digest = string.rep("0123456789abcdef", Protocol.DIGEST_LENGTH / 16)
		local message = { kind = "professionDigest", digest = digest }
		assert.same(message, readWhole(Protocol.write(message)))
		assert.equal("2:H:", Protocol.write(message):sub(1, 4))
	end)

	it("carries professions, a removal and one never opened included, with a GUID", function()
		local message = {
			kind = "professions",
			professions = {
				tailoring,
				{ name = "Anna Conda", skillLine = 171, revision = 7, level = 1, maxLevel = 75 },
				{ name = "Cole Slaw", skillLine = 171, revision = 8, guid = "Player-1-0000ABCD" },
				{ name = "Dee Zaster", skillLine = 171, revision = 9, level = 0, maxLevel = 75, recipes = {} },
			},
		}
		assert.same(message, readWhole(Protocol.write(message)))
	end)

	it("writes recipe IDs sorted, as base-36 differences", function()
		assert.equal("1731500000:Hugh Jass:197:75:150:1u9,1,r0py", Protocol.writeProfession(tailoring))
	end)

	it("batches professions in messages a peer reads whole", function()
		local list = {}
		local recipes = {}
		for i = 1, 400 do
			recipes[i] = 1000000 + i * 997
		end
		for i = 1, 20 do
			list[i] =
				{ name = "Name Number" .. i, skillLine = 171, revision = 9, level = 1, maxLevel = 9, recipes = recipes }
		end
		local batches = Protocol.batchProfessions(list)
		local count = 0
		for _, batch in ipairs(batches) do
			local text = Protocol.write({ kind = "professions", professions = batch })
			assert.is_true(#text <= Protocol.MAX_CHUNKED_BYTES)
			count = count + #readWhole(text).professions
		end
		assert.equal(20, count)
	end)

	describe("drops what it cannot trust", function()
		local function kept(line)
			local message = readWhole("2:K:" .. line .. "\n1:Anna Conda:171")
			return message and #message.professions == 2
		end

		it("keeps a well-formed line", function()
			assert.is_true(kept("1:Hugh Jass:171:1:75:1,2"))
		end)

		it("drops a line that does not parse, and keeps the others", function()
			for _, line in ipairs({
				"",
				"1:Hugh Jass",
				"0:Hugh Jass:171",
				"01:Hugh Jass:171",
				"1:Hugh:171",
				"1:Hugh Jass:0",
				"1:Hugh Jass:1234567",
				"1:Hugh Jass:171:1",
				"1:Hugh Jass:171:76:75",
				"1:Hugh Jass:171:1:0",
				"1:Hugh Jass:171:01:75",
				"1:Hugh Jass:171:1:10000",
				"1:Hugh Jass:171:1:75:0",
				"1:Hugh Jass:171:1:75:1,0",
				"1:Hugh Jass:171:1:75:01",
				"1:Hugh Jass:171:1:75:A",
				"1:Hugh Jass:171:1:75:1,,2",
				"1:Hugh Jass:171:1:75:1,",
				"1:Hugh Jass:171:1:75:1234567",
				"1:Hugh Jass:171:1:75:zzzzzz,zzzzzz",
				"1:Hugh Jass:171:1:75:1:2",
				"1:Hugh|cff Jass:171",
				"1:Hugh\1 Jass:171",
				"1:Hugh Jass:171\r",
				"F",
			}) do
				assert.is_false(kept(line), line)
			end
		end)

		it("drops a GUID that is not a character's, and keeps its profession", function()
			local message = readWhole("2:K:1:Hugh Jass:171\nG:Creature-1-2")
			assert.same({ { name = "Hugh Jass", skillLine = 171, revision = 1 } }, message.professions)
		end)

		it("drops more recipes than a profession can hold: 600, Tailoring's 471 and headroom", function()
			local tokens = {}
			for i = 1, 600 do
				tokens[i] = "1"
			end
			assert.equal(
				600,
				#readWhole("2:K:1:Hugh Jass:171:1:75:" .. table.concat(tokens, ",")).professions[1].recipes
			)
			tokens[601] = "1"
			assert.is_nil(readWhole("2:K:1:Hugh Jass:171:1:75:" .. table.concat(tokens, ",")))
		end)

		it("drops a message with no profession it can read, or longer than a chunked message", function()
			assert.is_nil(readWhole("2:K"))
			assert.is_nil(readWhole("2:K:"))
			assert.is_nil(readWhole("2:K:G:Player-1-2"))
			assert.is_nil(Protocol.read("2:H:" .. string.rep("0", Protocol.DIGEST_LENGTH - 1)))
			local long = "2:K:" .. string.rep("1:Hugh Jass:171\n", 300)
			assert.is_nil(readWhole(long))
		end)
	end)
end)
