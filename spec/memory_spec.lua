local Memory = require("spec.helpers.addon")("Memory").Memory

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

	it("hands out copies, so a caller cannot change what it remembers", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:recall("Hugh Jass").nickname = "Mallory"
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)
end)
