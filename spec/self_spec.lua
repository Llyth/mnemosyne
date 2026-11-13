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
end)
