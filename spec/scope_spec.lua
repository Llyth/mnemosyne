local ns = require("spec.helpers.addon")("Scope")
local Scope = ns.Scope

describe("Scope", function()
	local settings, scope

	before_each(function()
		settings = { everyone = false }
		scope = Scope.new(settings)
		scope:see({ "Mip Wiq" }, { "Bo Nanza" })
	end)

	it("talks with a friend or a guildmate", function()
		assert.is_true(scope:allows("Mip Wiq"))
		assert.is_true(scope:allows("Bo Nanza"))
	end)

	it("does not talk with a character outside the scope while everyone is off", function()
		assert.is_false(scope:allows("Anna Conda"))
	end)

	it("talks with anyone while everyone is on", function()
		settings.everyone = true
		assert.is_true(scope:allows("Anna Conda"))
	end)

	it("matches a name with or without its realm", function()
		scope:see({ "Mip Wiq" }, { "Hugh Jass-Other Realm" })
		assert.is_true(scope:allows("Hugh Jass"))
		assert.is_true(scope:allows("Mip Wiq-Other Realm"))
		assert.is_true(scope:isGuildmate("Hugh Jass"))
	end)

	it("forgets every name when it sees the lists again", function()
		scope:see({}, {})
		assert.is_false(scope:allows("Mip Wiq"))
		assert.is_false(scope:isGuildmate("Bo Nanza"))
	end)

	it("ignores a name that is missing or empty", function()
		scope:see({ "" }, { false })
		assert.is_false(scope:allows(""))
	end)

	it("tells a guildmate from a friend, whether everyone is on or not", function()
		settings.everyone = true
		assert.is_true(scope:isGuildmate("Bo Nanza"))
		assert.is_false(scope:isGuildmate("Mip Wiq"))
		assert.is_false(scope:isGuildmate("Anna Conda"))
	end)

	it("tells a friend or a guildmate from anyone else, whether everyone is on or not", function()
		settings.everyone = true
		assert.is_true(scope:isListed("Mip Wiq"))
		assert.is_true(scope:isListed("Bo Nanza-Realm"))
		assert.is_false(scope:isListed("Anna Conda"))
	end)

	it("lists every friend and guildmate seen, as read", function()
		scope:see({ "Mip Wiq" }, { "Bo Nanza", "Hugh Jass" })
		local listed = scope:listed()
		table.sort(listed)
		assert.same({ "Bo Nanza", "Hugh Jass", "Mip Wiq" }, listed)
	end)

	it("tells which friends and guildmates are online", function()
		scope:see({ "Mip Wiq" }, { "Bo Nanza", "Hugh Jass" }, { ["Mip Wiq"] = true, ["Hugh Jass"] = true })
		assert.same({ ["Mip Wiq"] = true, ["Hugh Jass"] = true }, scope:online())
	end)

	it("gives a set of the online that the caller may change", function()
		scope:see({ "Mip Wiq" }, {}, { ["Mip Wiq"] = true })
		scope:online()["Bea Bop"] = true
		assert.same({ ["Mip Wiq"] = true }, scope:online())
	end)
end)
