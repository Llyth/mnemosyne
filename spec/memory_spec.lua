local ns = require("spec.helpers.addon")("Protocol", "Memory")
local Memory, Protocol = ns.Memory, ns.Protocol

describe("Memory", function()
	local now, saved, memory

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		memory = Memory.new(saved, clock)
	end)

	it("recalls nothing about a character it never heard", function()
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("recalls an identity heard first-hand, with when it was heard", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.same({ nickname = "Tony", revision = 900, firstHand = true, heard = 1000 }, memory:recall("Hugh Jass"))
	end)

	it("keeps each character's identity apart", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
		assert.is_nil(memory:recall("Hugh"))
	end)

	it("lets a later revision change the nickname", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		now = 2000
		memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
		assert.same(
			{ nickname = "Antoine", revision = 1900, firstHand = true, heard = 2000 },
			memory:recall("Hugh Jass")
		)
	end)

	it("keeps the later revision when an earlier one arrives late", function()
		memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.equal("Antoine", memory:recall("Hugh Jass").nickname)
	end)

	it("forgets a character's identity when the character unregisters", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 901 })
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("forgets a character's identity when the character answers that it is anonymous", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		local message = Protocol.read("1:N:901")
		memory:hear("Hugh Jass", { nickname = message.nickname, revision = message.revision })
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("ignores an unregistering older than the identity it holds", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 800 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("learns the identity again when the character registers after unregistering", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 901 })
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 902 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("keeps what it heard in its saved table", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		local reloaded = Memory.new(saved, clock)
		assert.equal("Tony", reloaded:recall("Hugh Jass").nickname)
	end)

	it("knows a character it heard of, registered or not", function()
		assert.is_false(memory:knows("Hugh Jass"))
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Anna Conda", { revision = 900 })
		assert.is_true(memory:knows("Hugh Jass"))
		assert.is_true(memory:knows("Anna Conda"))
	end)

	it("hands out copies, so a caller cannot change what it remembers", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:recall("Hugh Jass").nickname = "Mallory"
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	describe("search", function()
		before_each(function()
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			memory:hear("Anna Conda", { nickname = "Tony", revision = 900 })
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 900 })
			memory:hear("Barb Dwyer", { nickname = "Æsa Øyvind", revision = 900 })
		end)

		local function names(results)
			local list = {}
			for _, identity in ipairs(results) do
				list[#list + 1] = identity.name
			end
			return list
		end

		it("finds every character of a nickname, sorted by name", function()
			assert.same({ "Anna Conda", "Hugh Jass" }, names(memory:search("Tony")))
		end)

		it("finds a character by its name or part of it", function()
			assert.same({ "Hugh Jass" }, names(memory:search("jass")))
			assert.same({ "Anna Conda" }, names(memory:search("anna c")))
		end)

		it("ignores case", function()
			assert.same({ "Anna Conda", "Hugh Jass" }, names(memory:search("tONY")))
			assert.same({ "Élise Bérénice" }, names(memory:search("ÉLISE")))
		end)

		it("ignores accents, in the text and in the identities", function()
			assert.same({ "Élise Bérénice" }, names(memory:search("elise berenice")))
			assert.same({ "Élise Bérénice" }, names(memory:search("zoe")))
			assert.same({ "Élise Bérénice" }, names(memory:search("Zoë")))
			assert.same({ "Barb Dwyer" }, names(memory:search("aesa oyvind")))
		end)

		it("gives each identity found with its name", function()
			assert.same(
				{ { name = "Hugh Jass", nickname = "Tony", revision = 900, firstHand = true, heard = 1000 } },
				memory:search("Hugh")
			)
		end)

		it("finds nothing for a text no identity holds", function()
			assert.same({}, memory:search("Mallory"))
		end)

		it("reads the text as plain text, not as a pattern", function()
			assert.same({}, memory:search("."))
			assert.same({}, memory:search("%a"))
			assert.same({}, memory:search("["))
		end)

		it("does not find a character that unregistered", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.same({ "Anna Conda" }, names(memory:search("Tony")))
		end)

		it("counts the identities it holds", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.equal(3, memory:count())
		end)
	end)
end)
