local ns = require("spec.helpers.addon")("Scope")
local Scope = ns.Scope

describe("Scope", function()
	local settings, scope

	before_each(function()
		settings = { everyone = false }
		scope = Scope.new(settings)
		scope:add("Mip Wiq")
	end)

	it("talks with a friend or a guildmate", function()
		assert.is_true(scope:allows("Mip Wiq"))
	end)

	it("does not talk with a character outside the scope while everyone is off", function()
		assert.is_false(scope:allows("Anna Conda"))
	end)

	it("talks with anyone while everyone is on", function()
		settings.everyone = true
		assert.is_true(scope:allows("Anna Conda"))
	end)

	it("matches a name with or without its realm", function()
		scope:add("Hugh Jass-Other Realm")
		assert.is_true(scope:allows("Hugh Jass"))
		assert.is_true(scope:allows("Mip Wiq-Other Realm"))
	end)

	it("forgets every name on reset, as the lists are read again", function()
		scope:reset()
		assert.is_false(scope:allows("Mip Wiq"))
	end)

	it("ignores a name that is missing or empty", function()
		scope:add(nil)
		scope:add("")
		assert.is_false(scope:allows(""))
	end)
end)
