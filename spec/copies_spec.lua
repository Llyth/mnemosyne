local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Scope", "Self", "Copies")
local Copies, Memory, Scope, Self = ns.Copies, ns.Memory, ns.Scope, ns.Self

-- The rules every category spreads by are tested through Professions
-- (professions_spec); here, only what a category of its own sets: its keys,
-- the field they come under, and its content.
describe("Copies", function()
	local now = 1000000
	local Milestones = setmetatable({}, { __index = Copies })
	Milestones.__index = Milestones
	Milestones.KEYS = { onyxia = true, scholomance = true }
	Milestones.KEY = "milestone"
	Milestones.FIELDS = { "state" }
	function Milestones.content(name, key, copy)
		return table.concat({ name, key, copy.revision, copy.state or "" }, "\n")
	end
	function Milestones.write(passed)
		return Milestones.content(passed.name, passed.milestone, passed)
	end
	function Milestones.stamp() end
	function Milestones.stamped()
		return {}
	end
	function Milestones.withCurrent()
		return {}
	end
	function Milestones.current()
		return {}
	end

	local milestones

	before_each(function()
		local function clock()
			return now
		end
		local settings = { passOn = true }
		local scope = Scope.new(settings)
		milestones = Copies.new(
			Milestones,
			{},
			clock,
			Memory.new({}, clock),
			Self.new({}, clock, settings),
			settings,
			scope,
			function()
				return "Bea Bop"
			end
		)
		scope:see({}, { "Hugh Jass", "Anna Conda" })
		milestones:seeLists()
	end)

	it("keeps only its own keys, each with its content", function()
		assert.is_true(
			milestones:hear("Hugh Jass", { name = "Anna Conda", milestone = "onyxia", revision = 10, state = 2 })
		)
		assert.is_false(
			milestones:hear("Hugh Jass", { name = "Anna Conda", milestone = 171, revision = 10, state = 2 })
		)
		local shown = milestones:list()
		assert.equal(1, #shown)
		assert.equal("onyxia", shown[1].milestone)
		assert.equal(2, shown[1].state)
		assert.equal("Hugh Jass", shown[1].source)
	end)

	it("disputes the same revision of a milestone with another content", function()
		milestones:hear("Hugh Jass", { name = "Anna Conda", milestone = "onyxia", revision = 10, state = 2 })
		assert.is_true(
			milestones:hear("Bo Nanza", { name = "Anna Conda", milestone = "onyxia", revision = 10, state = 1 })
		)
		assert.same({ { name = "Anna Conda", milestone = "onyxia", disputed = true } }, milestones:list())
	end)
end)
