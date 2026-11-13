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

		it("carries an anonymous character's answer", function()
			local message = { kind = "anonymous", revision = 1731500001 }
			assert.same(message, roundTrip(message))
			assert.equal("1:N:1731500001", Protocol.write(message))
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
		end)

		it("drops a message from a newer version, and says it is newer", function()
			assertDropped("2:A:5:Tony", "newer")
			assertDropped("10:Q", "newer")
		end)

		it("drops a message without a version", function()
			for _, text in ipairs({ "", "Q", "A:5:Tony", ":Q", "hello", "1", "1Q" }) do
				assertDropped(text, "malformed")
			end
		end)

		it("drops a message longer than 255 bytes", function()
			assertDropped("1:A:5:" .. string.rep("a", 250), "oversized")
		end)

		it("drops a message that is not text", function()
			assertDropped(nil, "malformed")
			assertDropped(42, "malformed")
			assertDropped({}, "malformed")
		end)

		it("drops a message of an unknown kind", function()
			assertDropped("1:Z:5:Tony", "malformed")
			assertDropped("1:a:5:Tony", "malformed")
			assertDropped("1:AA:5:Tony", "malformed")
		end)

		it("drops an announcement or answer without a valid revision", function()
			for _, kind in ipairs({ "A", "R" }) do
				for _, revision in ipairs({ "", "abc", "0", "-5", "1.5", "1e9", "007", "123456789012345", " 5" }) do
					assertDropped("1:" .. kind .. ":" .. revision .. ":Tony", "malformed")
				end
				assertDropped("1:" .. kind .. ":5", "malformed")
			end
		end)

		it("drops a removal without a valid revision, or with a nickname", function()
			assertDropped("1:U", "malformed")
			assertDropped("1:U:", "malformed")
			assertDropped("1:U:abc", "malformed")
			assertDropped("1:U:5:Tony", "malformed")
		end)

		it("drops an anonymous answer without a valid revision, or with a nickname", function()
			assertDropped("1:N", "malformed")
			assertDropped("1:N:", "malformed")
			assertDropped("1:N:0", "malformed")
			assertDropped("1:N:abc", "malformed")
			assertDropped("1:N:5:Tony", "malformed")
		end)

		it("drops an ask with anything after it", function()
			assertDropped("1:Q:", "malformed")
			assertDropped("1:Q:Tony", "malformed")
		end)

		it("drops a nickname with an escape sequence", function()
			for _, nickname in ipairs({
				"|cffff0000Tony|r",
				"|Hplayer:Tony|h[Tony]|h",
				"|TInterface\\Icons\\X:0|t",
				"|",
			}) do
				assertDropped("1:A:5:" .. nickname, "nickname")
				assertDropped("1:R:5:" .. nickname, "nickname")
			end
		end)

		it("drops a nickname with a control character", function()
			for _, nickname in ipairs({ "To\nny", "To\0ny", "Tony\r", "\tTony", "To\127ny", "To\194\133ny" }) do
				assertDropped("1:A:5:" .. nickname, "nickname")
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
				assertDropped("1:A:5:" .. nickname, "nickname")
			end
		end)

		it("drops a nickname longer than 32 characters", function()
			assertDropped("1:A:5:" .. string.rep("é", 33), "nickname")
		end)

		it("drops an empty nickname", function()
			assertDropped("1:A:5:", "nickname")
		end)
	end)

	describe("checks a nickname", function()
		it("accepts 32 characters, counted as characters and not bytes", function()
			assert.is_true(Protocol.checkNickname(string.rep("é", 32)))
			assert.is_true(Protocol.checkNickname(string.rep("😀", 32)))
		end)

		it("says why it refuses a nickname", function()
			local cases = {
				[""] = "empty",
				[string.rep("a", 33)] = "long",
				["|cffTony"] = "escape",
				["To\nny"] = "control",
				["To\255ny"] = "encoding",
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
			assert.equal("1:A:5:||cffff0000Tony||r", Protocol.printable("1:A:5:|cffff0000Tony|r"))
			assert.equal("||Hplayer:X||h[X]||h", Protocol.printable("|Hplayer:X|h[X]|h"))
		end)

		it("replaces control characters", function()
			assert.equal("To?ny?", Protocol.printable("To\nny\0"))
		end)

		it("keeps other text as it is", function()
			assert.equal("1:R:5:Éloïse: the tank", Protocol.printable("1:R:5:Éloïse: the tank"))
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
		for _, chunk in ipairs(Protocol.split(text)) do
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
			assert.equal("1:I:900:Hugh Jass:Tony\nG:Player-1-0A1B2C3D", text)
			assert.is_nil(("G:Player-1-0A1B2C3D"):match("^[1-9]%d*:"))
		end)

		it("carries the end of a sync", function()
			assert.same({ kind = "done" }, roundTripSplit({ kind = "done" }))
		end)
	end)

	describe("drops what it cannot trust", function()
		it("drops a digest of the wrong size or not in hexadecimal", function()
			assertDropped("1:D", "malformed")
			assertDropped("1:D:" .. DIGEST:sub(2), "malformed")
			assertDropped("1:D:" .. DIGEST .. "0", "malformed")
			assertDropped("1:D:" .. DIGEST:upper(), "malformed")
			assertDropped("1:D:" .. DIGEST:sub(2) .. "g", "malformed")
		end)

		it("drops identities without any", function()
			assertDropped("1:I", "malformed")
			assertDropped("1:I:", "malformed")
		end)

		it("drops an identity without a valid revision", function()
			assertDropped("1:I:0:Anna Conda", "malformed")
			assertDropped("1:I:abc:Hugh Jass:Tony", "malformed")
			assertDropped("1:I:Hugh Jass:Tony", "malformed")
		end)

		it("drops identities that hold more than a batch, so one message never costs more than 16", function()
			local lines = {}
			for i = 1, Protocol.MAX_LINES + 1 do
				lines[i] = "1:Peer" .. i .. " Last"
			end
			assertDropped("1:I:" .. table.concat(lines, "\n"), "oversized")
			lines[#lines] = nil
			assert.equal(Protocol.MAX_LINES, #readSplit("1:I:" .. table.concat(lines, "\n")).identities)
		end)

		it("counts a GUID's line toward the 16 lines of a batch", function()
			local lines = {}
			for i = 1, Protocol.MAX_LINES / 2 do
				lines[#lines + 1] = "1:Peer" .. i .. " Last"
				lines[#lines + 1] = "G:Player-1-0000000" .. i
			end
			assert.equal(Protocol.MAX_LINES / 2, #readSplit("1:I:" .. table.concat(lines, "\n")).identities)
			lines[#lines + 1] = "1:Hugh Jass"
			assertDropped("1:I:" .. table.concat(lines, "\n"), "oversized")
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
					readSplit("1:I:900:Hugh Jass\nG:" .. guid),
					guid
				)
			end
		end)

		it("gives a GUID only to the identity on the line just before it", function()
			assert.same(
				{ kind = "identities", identities = { { name = "Hugh Jass", revision = 900 } } },
				readSplit("1:I:G:Player-1-00000001\n900:Hugh Jass\n0:Anna Conda\nG:Player-1-00000002")
			)
			assert.same({
				kind = "identities",
				identities = { { name = "Hugh Jass", revision = 900, guid = "Player-1-00000001" } },
			}, readSplit("1:I:900:Hugh Jass\nG:Player-1-00000001\nG:Player-1-00000002"))
		end)

		it("drops identities made of GUIDs alone", function()
			assertDropped("1:I:G:Player-1-00000001", "malformed")
		end)

		it("drops only the identities that do not parse, and keeps the others", function()
			assert.same(
				{ kind = "identities", identities = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } } },
				readSplit("1:I:0:Anna Conda\n900:Hugh Jass:Tony\n900:Cole Slaw:|cffff0000Cole|r\n\n900:Barb")
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
				assertDropped("1:I:900:" .. name .. ":Tony", "malformed")
			end
		end)

		it("drops an identity whose nickname breaks the rules", function()
			assertDropped("1:I:900:Hugh Jass:", "nickname")
			assertDropped("1:I:900:Hugh Jass:|cffff0000Tony|r", "nickname")
			assertDropped("1:I:900:Hugh Jass:" .. string.rep("a", 33), "nickname")
		end)

		it("drops the end of a sync with anything after it", function()
			assertDropped("1:E:", "malformed")
			assertDropped("1:E:Tony", "malformed")
		end)
	end)

	describe("splits a long message into chunks", function()
		local now, reader

		before_each(function()
			now = 1000
			reader = Protocol.newReader(function()
				return now
			end)
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
			assert.same({ "1:Q" }, Protocol.split("1:Q"))
			assert.same({ kind = "ask" }, reader:read("Hugh Jass", "1:Q"))
		end)

		it("splits a long message into chunks of at most 255 bytes, and reassembles them", function()
			local message = identities(16, true)
			local chunks = Protocol.split(Protocol.write(message))
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
			local a = Protocol.split(Protocol.write(identities(16, true)))
			local b = Protocol.split(Protocol.write(identities(16)))
			for i = 1, #b - 1 do
				reader:read("Anna Conda", a[i])
				reader:read("Barb Dwyer", b[i])
			end
			assert.same(identities(16), reader:read("Barb Dwyer", b[#b]))
			assert.same(identities(16, true), deliver("Anna Conda", { unpack(a, #b) }))
		end)

		it("drops a message whose chunks come out of order", function()
			local chunks = Protocol.split(Protocol.write(identities(16, true)))
			chunks[2], chunks[3] = chunks[3], chunks[2]
			local message, reason = deliver("Hugh Jass", chunks)
			assert.is_nil(message)
			assert.equal("incomplete", reason)
		end)

		it("drops a message cut short when the sender starts another one", function()
			local cut = Protocol.split(Protocol.write(identities(16, true)))
			reader:read("Hugh Jass", cut[1])
			reader:read("Hugh Jass", cut[2])
			assert.same(identities(16), deliver("Hugh Jass", Protocol.split(Protocol.write(identities(16)))))
		end)

		it("drops a message whose last chunks never come", function()
			local chunks = Protocol.split(Protocol.write(identities(16, true)))
			for i = 1, #chunks - 1 do
				reader:read("Hugh Jass", chunks[i])
			end
			now = now + 61
			local message, reason = reader:read("Hugh Jass", chunks[#chunks])
			assert.is_nil(message)
			assert.equal("incomplete", reason)
		end)

		it("drops a message announced longer than it may be", function()
			local message, reason = reader:read("Hugh Jass", "1:C:1:99:1:Q")
			assert.is_nil(message)
			assert.equal("oversized", reason)
		end)

		it("drops a chunk that does not parse", function()
			for _, text in ipairs({ "1:C", "1:C:1", "1:C:0:2:x", "1:C:3:2:x", "1:C:a:2:x", "1:C:01:2:x" }) do
				local message, reason = reader:read("Hugh Jass", text)
				assert.is_nil(message, text)
				assert.equal("malformed", reason, text)
			end
		end)

		it("drops a reassembled message that does not parse", function()
			local message, reason = deliver("Hugh Jass", { "1:C:1:2:1:I:900:Hugh", "1:C:2:2:" })
			assert.is_nil(message)
			assert.equal("malformed", reason)
		end)

		it("never reassembles a chunk inside a chunk", function()
			local message, reason = deliver("Hugh Jass", { "1:C:1:2:1:C:1:", "1:C:2:2:1:1:Q" })
			assert.is_nil(message)
			assert.equal("malformed", reason)
		end)

		it("drops a chunk from a newer version, and says it is newer", function()
			local message, reason = reader:read("Hugh Jass", "2:C:1:2:x")
			assert.is_nil(message)
			assert.equal("newer", reason)
		end)
	end)
end)
