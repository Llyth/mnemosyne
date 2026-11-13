local ns = require("spec.helpers.addon")("Memory", "Strangers")
local Memory, Strangers = ns.Memory, ns.Strangers

describe("Strangers", function()
	local DAY = 24 * 60 * 60
	local now, saved, memory, strangers

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		memory = Memory.new({}, clock)
		strangers = Strangers.new(saved, clock, memory)
	end)

	it("asks a character whose identity it does not know", function()
		assert.is_true(strangers:ask("Hugh Jass", "Anna Conda"))
	end)

	it("never asks the character being played", function()
		assert.is_false(strangers:ask("Anna Conda", "Anna Conda"))
	end)

	it("never asks a character whose identity it knows", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.is_false(strangers:ask("Hugh Jass", "Anna Conda"))
	end)

	it("never asks a character it knows has no nickname", function()
		memory:hear("Hugh Jass", { revision = 900 })
		assert.is_false(strangers:ask("Hugh Jass", "Anna Conda"))
	end)

	it("asks the same character at most once a day", function()
		assert.is_true(strangers:ask("Hugh Jass", "Anna Conda"))
		now = now + DAY - 1
		assert.is_false(strangers:ask("Hugh Jass", "Anna Conda"))
		now = now + 1
		assert.is_true(strangers:ask("Hugh Jass", "Anna Conda"))
	end)

	it("asks at most once every 2 seconds and drops the asks in between", function()
		assert.is_true(strangers:ask("Hugh Jass", "Anna Conda"))
		now = now + 1.9
		assert.is_false(strangers:ask("Jack Pott", "Anna Conda"))
		now = now + 0.1
		assert.is_true(strangers:ask("Barb Dwyer", "Anna Conda"))
		now = now + 2
		assert.is_true(strangers:ask("Jack Pott", "Anna Conda"))
	end)

	it("spends no turn on a character it may not ask", function()
		assert.is_false(strangers:ask("Anna Conda", "Anna Conda"))
		assert.is_true(strangers:ask("Hugh Jass", "Anna Conda"))
	end)

	it("remembers whom it asked in its saved table", function()
		strangers:ask("Hugh Jass", "Anna Conda")
		now = now + 60
		local reloaded = Strangers.new(saved, clock, memory)
		assert.is_false(reloaded:ask("Hugh Jass", "Anna Conda"))
	end)

	it("lets go of the asks older than a day when it starts", function()
		strangers:ask("Hugh Jass", "Anna Conda")
		now = now + 10
		strangers:ask("Jack Pott", "Anna Conda")
		now = now - 10 + DAY
		Strangers.new(saved, clock, memory)
		assert.same({ ["Jack Pott"] = 1010 }, saved)
	end)
end)
