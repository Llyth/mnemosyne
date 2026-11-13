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

		it("drops a message from another version", function()
			assertDropped("2:A:5:Tony", "version")
			assertDropped("0:Q", "version")
			assertDropped("10:Q", "version")
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
