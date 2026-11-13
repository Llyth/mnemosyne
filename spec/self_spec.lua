local Self = require("spec.helpers.addon")("Protocol", "Self").Self

describe("Self", function()
	local now, saved, characters

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		characters = Self.new(saved, clock)
	end)

	it("knows no registration for a character never registered", function()
		assert.is_nil(characters:registration("Hugh Jass"))
	end)

	it("registers a character with its nickname, at the server's time", function()
		assert.is_true(characters:register("Hugh Jass", "Tony"))
		assert.same({ nickname = "Tony", revision = 1000 }, characters:registration("Hugh Jass"))
	end)

	it("registers each character on its own", function()
		characters:register("Hugh Jass", "Tony")
		assert.is_nil(characters:registration("Anna Conda"))
	end)

	it("refuses a nickname that breaks the rules, and keeps the registration it had", function()
		characters:register("Hugh Jass", "Tony")
		now = 2000
		local ok, reason = characters:register("Hugh Jass", string.rep("a", 33))
		assert.is_false(ok)
		assert.equal("long", reason)
		assert.same({ nickname = "Tony", revision = 1000 }, characters:registration("Hugh Jass"))
	end)

	it("trims the spaces around a nickname and collapses the runs inside it", function()
		assert.is_true(characters:register("Hugh Jass", "  Tony   the  tank "))
		assert.equal("Tony the tank", characters:registration("Hugh Jass").nickname)
	end)

	it("refuses a nickname made only of spaces", function()
		local ok, reason = characters:register("Hugh Jass", "   ")
		assert.is_false(ok)
		assert.equal("empty", reason)
		assert.is_nil(characters:registration("Hugh Jass"))
	end)

	it("counts a nickname's length after trimming it", function()
		assert.is_true(characters:register("Hugh Jass", "  " .. string.rep("a", 32) .. "  "))
	end)

	it("changes the nickname with a later revision", function()
		characters:register("Hugh Jass", "Tony")
		now = 2000
		characters:register("Hugh Jass", "Antoine")
		assert.same({ nickname = "Antoine", revision = 2000 }, characters:registration("Hugh Jass"))
	end)

	it("moves the revision forward when the server time has not moved", function()
		characters:register("Hugh Jass", "Tony")
		characters:register("Hugh Jass", "Antoine")
		assert.equal(1001, characters:registration("Hugh Jass").revision)
	end)

	it("moves the revision forward when the server time goes back", function()
		characters:register("Hugh Jass", "Tony")
		now = 500
		characters:register("Hugh Jass", "Antoine")
		assert.equal(1001, characters:registration("Hugh Jass").revision)
	end)

	it("unregisters a character with a later revision", function()
		characters:register("Hugh Jass", "Tony")
		assert.is_true(characters:unregister("Hugh Jass"))
		assert.same({ revision = 1001 }, characters:registration("Hugh Jass"))
	end)

	it("does not unregister a character that is not registered", function()
		assert.is_false(characters:unregister("Hugh Jass"))
		assert.is_nil(characters:registration("Hugh Jass"))
		characters:register("Hugh Jass", "Tony")
		characters:unregister("Hugh Jass")
		assert.is_false(characters:unregister("Hugh Jass"))
		assert.equal(1001, characters:registration("Hugh Jass").revision)
	end)

	it("keeps registrations in its saved table", function()
		characters:register("Hugh Jass", "Tony")
		assert.same({ nickname = "Tony", revision = 1000 }, Self.new(saved, clock):registration("Hugh Jass"))
	end)

	describe("states", function()
		it("has not asked about a character never registered", function()
			assert.equal("notAsked", characters:state("Hugh Jass"))
		end)

		it("calls a character with a nickname registered", function()
			characters:register("Hugh Jass", "Tony")
			assert.equal("registered", characters:state("Hugh Jass"))
		end)

		it("keeps a character anonymous with a later revision", function()
			characters:register("Hugh Jass", "Tony")
			assert.is_true(characters:keepAnonymous("Hugh Jass"))
			assert.equal("anonymous", characters:state("Hugh Jass"))
			assert.same({ anonymous = true, revision = 1001 }, characters:registration("Hugh Jass"))
		end)

		it("keeps a character never registered anonymous, at the server's time", function()
			assert.is_true(characters:keepAnonymous("Hugh Jass"))
			assert.same({ anonymous = true, revision = 1000 }, characters:registration("Hugh Jass"))
		end)

		it("does not keep an anonymous character anonymous again", function()
			characters:keepAnonymous("Hugh Jass")
			now = 2000
			assert.is_false(characters:keepAnonymous("Hugh Jass"))
			assert.equal(1000, characters:registration("Hugh Jass").revision)
		end)

		it("registers an anonymous character when its player changes their mind", function()
			characters:keepAnonymous("Hugh Jass")
			characters:register("Hugh Jass", "Tony")
			assert.equal("registered", characters:state("Hugh Jass"))
			assert.same({ nickname = "Tony", revision = 1001 }, characters:registration("Hugh Jass"))
		end)

		it("does not unregister an anonymous character", function()
			characters:keepAnonymous("Hugh Jass")
			assert.is_false(characters:unregister("Hugh Jass"))
			assert.equal("anonymous", characters:state("Hugh Jass"))
		end)

		it("calls a character that withdrew its registration unregistered", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.equal("unregistered", characters:state("Hugh Jass"))
		end)

		it("registers a character again after it unregistered", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.is_true(characters:register("Hugh Jass", "Antoine"))
			assert.equal("registered", characters:state("Hugh Jass"))
		end)

		it("remembers an anonymous character in its saved table", function()
			characters:keepAnonymous("Hugh Jass")
			assert.equal("anonymous", Self.new(saved, clock):state("Hugh Jass"))
		end)

		it("counts the characters in each state", function()
			characters:register("Hugh Jass", "Tony")
			characters:register("Anna Conda", "Tony")
			characters:keepAnonymous("Barb Dwyer")
			assert.equal(2, characters:count("registered"))
			assert.equal(1, characters:count("anonymous"))
		end)
	end)

	describe("the message a character sends", function()
		it("announces and answers with the nickname of a registered character", function()
			characters:register("Hugh Jass", "Tony")
			local expected = { kind = "announcement", nickname = "Tony", revision = 1000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			expected.kind = "answer"
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("says an anonymous character is anonymous", function()
			characters:keepAnonymous("Hugh Jass")
			local expected = { kind = "anonymous", revision = 1000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("sends the removal of a character that unregistered", function()
			characters:register("Hugh Jass", "Tony")
			now = 2000
			characters:unregister("Hugh Jass")
			local expected = { kind = "removal", revision = 2000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("sends nothing about a character not asked yet", function()
			assert.is_nil(characters:message("Hugh Jass", "announce"))
			assert.is_nil(characters:message("Hugh Jass", "answer"))
		end)

		it("asks, whatever the character's state", function()
			assert.same({ kind = "ask" }, characters:message("Hugh Jass", "ask"))
			characters:register("Hugh Jass", "Tony")
			assert.same({ kind = "ask" }, characters:message("Hugh Jass", "ask"))
		end)
	end)

	describe("the registration prompt", function()
		it("prompts for a character not asked yet, with nothing to pre-fill", function()
			assert.same({}, characters:prompt("Hugh Jass"))
		end)

		it("does not prompt for a registered character", function()
			characters:register("Hugh Jass", "Tony")
			assert.is_nil(characters:prompt("Hugh Jass"))
		end)

		it("does not prompt for an anonymous character", function()
			characters:keepAnonymous("Hugh Jass")
			assert.is_nil(characters:prompt("Hugh Jass"))
			assert.is_nil(Self.new(saved, clock):prompt("Hugh Jass"))
		end)

		it("does not prompt for a character that unregistered, even at a later login", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.is_nil(characters:prompt("Hugh Jass"))
			assert.is_nil(Self.new(saved, clock):prompt("Hugh Jass"))
		end)

		it("prompts again at the next login when the player asked to be asked later", function()
			characters:prompt("Hugh Jass")
			assert.same({}, Self.new(saved, clock):prompt("Hugh Jass"))
		end)

		it("pre-fills the nickname of the player's latest registered character", function()
			characters:register("Anna Conda", "Tony")
			now = 2000
			characters:register("Barb Dwyer", "Antoine")
			characters:keepAnonymous("Paige Turner")
			assert.same({ nickname = "Antoine" }, characters:prompt("Hugh Jass"))
		end)

		it("pre-fills what peers say about the character when no other character is registered", function()
			local heard = { nickname = "Tony", revision = 900, firstHand = false, heard = 950 }
			assert.same({ nickname = "Tony", fromPeers = true }, characters:prompt("Hugh Jass", heard))
		end)

		it("prefers the player's other characters to what peers say", function()
			characters:register("Anna Conda", "Antoine")
			local heard = { nickname = "Tony", revision = 900, firstHand = false, heard = 950 }
			assert.same({ nickname = "Antoine" }, characters:prompt("Hugh Jass", heard))
		end)

		it("never adopts what peers say without the player's click", function()
			characters:prompt("Hugh Jass", { nickname = "Tony", revision = 900, firstHand = false, heard = 950 })
			assert.is_nil(characters:registration("Hugh Jass"))
			assert.equal("notAsked", characters:state("Hugh Jass"))
		end)
	end)
end)
