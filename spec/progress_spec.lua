local addon = require("spec.helpers.addon")
local ns = addon("Protocol", "Digest", "Memory", "Scope", "Self", "Copies", "Milestones", "Progress")
local Memory, Progress, Scope, Self = ns.Memory, ns.Progress, ns.Scope, ns.Self

-- Progress spreads by the rules of Copies (spec/copies_spec.lua): these test
-- through Progress' interface what matters for it, this account's characters'
-- progress read and stamped by the real Self.
describe("Progress", function()
	local DAY = 24 * 60 * 60
	local ONYXIA, MOLTEN_CORE, DIRE_MAUL, THELDREN = 1, 2, 4, 8
	local now, saved, memory, characters, settings, scope, progress, played

	local function clock()
		return now
	end

	-- Reads the friends and the guild roster as Client does.
	local function seeLists(of, ofScope, friends, roster)
		ofScope:see(friends, roster)
		of:seeLists()
	end

	before_each(function()
		now = 1000000
		saved = {}
		memory = Memory.new({}, clock)
		settings = { passOn = true }
		characters = Self.new({}, clock, settings)
		played = "Bea Bop" -- the character logged on, which syncs: registered, without progress
		characters:register(played, "Bea")
		scope = Scope.new(settings)
		progress = Progress.new(saved, clock, memory, characters, settings, scope, function()
			return played
		end)
		seeLists(progress, scope, { "Bo Nanza" }, { "Hugh Jass", "Anna Conda", "Cole Slaw" })
	end)

	-- Hugh Jass's Crescent Key held, as a peer passes it on.
	local function direMaul(revision, cell)
		local heard = { name = "Hugh Jass", milestone = DIRE_MAUL, revision = revision or 900 }
		for field, value in pairs(cell or { state = "done", item = 18249 }) do
			heard[field] = value
		end
		return heard
	end

	local function shown(name)
		local found = {}
		for _, milestone in ipairs(progress:list()) do
			if milestone.name == name then
				found[#found + 1] = milestone
			end
		end
		return found
	end

	it("keeps a milestone heard first-hand, with its cell", function()
		assert.is_true(progress:hear("Hugh Jass", direMaul()))
		assert.same({
			{
				name = "Hugh Jass",
				milestone = DIRE_MAUL,
				state = "done",
				item = 18249,
				revision = 900,
				firstHand = true,
				heard = now,
			},
		}, progress:list())
	end)

	it("keeps a milestone heard second-hand with its source", function()
		progress:hear("Anna Conda", direMaul())
		local milestone = shown("Hugh Jass")[1]
		assert.is_false(milestone.firstHand)
		assert.equal("Anna Conda", milestone.source)
	end)

	it("lets a later revision win among second-hand copies, never an older one", function()
		progress:hear("Anna Conda", direMaul(900))
		assert.is_true(progress:hear("Cole Slaw", direMaul(950, { state = "done" })))
		assert.is_false(progress:hear("Anna Conda", direMaul(900)))
		assert.is_nil(shown("Hugh Jass")[1].item)
	end)

	it("never lets a second-hand copy replace a first-hand milestone", function()
		progress:hear("Hugh Jass", direMaul(900))
		assert.is_false(progress:hear("Anna Conda", direMaul(5000, { state = "done" })))
		assert.is_true(shown("Hugh Jass")[1].firstHand)
		assert.equal(18249, shown("Hugh Jass")[1].item)
	end)

	it("hides a milestone two peers pass on at the same revision with different content", function()
		progress:hear("Anna Conda", direMaul(900))
		assert.is_true(progress:hear("Cole Slaw", direMaul(900, { state = "done" })))
		assert.same({ { name = "Hugh Jass", milestone = DIRE_MAUL, disputed = true } }, progress:list())
		assert.is_true(progress:hear("Hugh Jass", direMaul(800)))
		assert.equal(800, shown("Hugh Jass")[1].revision)
	end)

	it("takes a removal: the milestone no longer shows, and an older copy does not bring it back", function()
		progress:hear("Anna Conda", direMaul(900))
		assert.is_true(progress:hear("Cole Slaw", { name = "Hugh Jass", milestone = DIRE_MAUL, revision = 950 }))
		assert.same({}, progress:list())
		assert.is_false(progress:hear("Anna Conda", direMaul(900)))
		assert.same({}, progress:list())
	end)

	it("drops a milestone it does not know, or a placeholder, even as a removal", function()
		assert.is_false(
			progress:hear("Hugh Jass", { name = "Hugh Jass", milestone = 99, revision = 900, state = "done" })
		)
		assert.is_false(
			progress:hear("Hugh Jass", { name = "Hugh Jass", milestone = MOLTEN_CORE, revision = 900, state = "done" })
		)
		assert.is_false(progress:hear("Hugh Jass", { name = "Hugh Jass", milestone = MOLTEN_CORE, revision = 900 }))
		assert.is_nil(saved.held["Hugh Jass"])
	end)

	it("drops a malformed cell whole, keeping the copy it held", function()
		assert.is_false(progress:hear("Anna Conda", direMaul(900, { state = "bogus", item = 18249 })))
		assert.is_false(
			progress:hear(
				"Anna Conda",
				{ name = "Hugh Jass", milestone = THELDREN, revision = 900, state = "progress" }
			)
		)
		assert.is_nil(saved.held["Hugh Jass"])
		progress:hear("Anna Conda", direMaul(900))
		assert.is_false(progress:hear("Cole Slaw", direMaul(950, { state = 1 })))
		assert.same({ "done", 900 }, { shown("Hugh Jass")[1].state, shown("Hugh Jass")[1].revision })
	end)

	it("drops a copy with a field that is not its milestone's whole, never trimmed", function()
		assert.is_false(progress:hear("Anna Conda", direMaul(900, { state = "done", item = 1 })))
		assert.is_false(progress:hear("Anna Conda", {
			name = "Cole Slaw",
			milestone = ONYXIA,
			revision = 900,
			state = "progress",
			quest = 6403,
			gems = 3,
		}))
		assert.is_nil(saved.held["Hugh Jass"])
		assert.is_nil(saved.held["Cole Slaw"])
	end)

	it("keeps progress only for the guild roster, friends' characters and its own", function()
		local function keyOf(name)
			return { name = name, milestone = DIRE_MAUL, revision = 900, state = "done" }
		end
		assert.is_false(progress:hear("Anna Conda", keyOf("Zed Ex")))
		assert.is_true(progress:hear("Anna Conda", keyOf("Bo Nanza")))
		characters:seeProgress("Ella Vator", { [DIRE_MAUL] = { state = "done", item = 18249 } })
		assert.same({ "Bo Nanza", "Ella Vator" }, { progress:list()[1].name, progress:list()[2].name })
	end)

	it("never adopts what peers say of this account's own characters", function()
		characters:register("Hugh Jass", "Tony")
		assert.is_false(progress:hear("Anna Conda", direMaul()))
	end)

	it("takes at most 2,000 second-hand milestones a day from one peer, first-hand ones aside", function()
		local roster = { "Anna Conda" }
		for i = 1, Progress.MAX_CHANGES_PER_PEER + 10 do
			roster[#roster + 1] = "Name Number" .. i
		end
		seeLists(progress, scope, {}, roster)
		local taken = 0
		for i = 1, Progress.MAX_CHANGES_PER_PEER + 10 do
			local heard = { name = "Name Number" .. i, milestone = DIRE_MAUL, revision = 900, state = "done" }
			taken = taken + (progress:hear("Anna Conda", heard) and 1 or 0)
		end
		assert.equal(Progress.MAX_CHANGES_PER_PEER, taken)
		assert.is_true(progress:hear("Anna Conda", { name = "Anna Conda", milestone = DIRE_MAUL, revision = 900 }))
		now = now + DAY
		assert.is_true(progress:hear("Anna Conda", { name = "Name Number2001", milestone = DIRE_MAUL, revision = 950 }))
	end)

	it("shows this account's characters' progress as read now, whatever is shared", function()
		settings.shareProgress = false
		characters:seeProgress("Dee Zaster", { [DIRE_MAUL] = { state = "done", item = 18249 } })
		assert.same({
			{ name = "Dee Zaster", milestone = DIRE_MAUL, state = "done", item = 18249, firstHand = true, own = true },
		}, progress:list())
	end)

	describe("in a sync", function()
		-- A peer on the roster, with an account of its own.
		local function other()
			local theirScope = Scope.new({})
			local theirs = Progress.new(
				{},
				clock,
				Memory.new({}, clock),
				Self.new({}, clock, {}),
				{ passOn = true },
				theirScope
			)
			seeLists(theirs, theirScope, {}, { "Dee Zaster", "Anna Conda", "Cole Slaw" })
			return theirs
		end

		-- What goes to Anna Conda of a character: { [milestone] = { state, revision } }.
		local function passed(name)
			local found = {}
			for _, milestone in ipairs(progress:answer("Anna Conda", other():digest("Barb Dwyer"))) do
				if milestone.name == name then
					found[milestone.milestone] = { state = milestone.state, revision = milestone.revision }
				end
			end
			return found
		end

		local function count(map)
			local n = 0
			for _ in pairs(map) do
				n = n + 1
			end
			return n
		end

		before_each(function()
			characters:register("Dee Zaster", "Dee")
			characters:seeProgress("Dee Zaster", { [DIRE_MAUL] = { state = "done", item = 18249 } })
		end)

		it("passes on a registered character's milestones first-hand, and a removal of each it lacks", function()
			progress:prepare()
			local dee = passed("Dee Zaster")
			assert.same({ state = "done", revision = now }, dee[DIRE_MAUL])
			assert.same({ revision = now }, dee[ONYXIA])
			assert.is_nil(dee[MOLTEN_CORE]) -- a placeholder tracks nothing
			local tracked = 0
			for _ in pairs(Progress.KEYS) do
				tracked = tracked + 1
			end
			assert.equal(tracked, count(dee))
		end)

		it("gives a milestone a new revision only when its cell changed", function()
			progress:prepare()
			now = now + 60
			characters:seeProgress("Dee Zaster", { [DIRE_MAUL] = { state = "done", item = 18249 } })
			progress:prepare()
			assert.equal(now - 60, passed("Dee Zaster")[DIRE_MAUL].revision)
			characters:seeProgress("Dee Zaster", {})
			progress:prepare()
			assert.same({ revision = now }, passed("Dee Zaster")[DIRE_MAUL])
		end)

		it("spreads removals once sharing progress is off", function()
			progress:prepare()
			now = now + 60
			settings.shareProgress = false
			progress:prepare()
			assert.same({ revision = now }, passed("Dee Zaster")[DIRE_MAUL])
		end)

		it("passes on only removals of a character kept anonymous, and only while it syncs itself", function()
			played = "Dee Zaster"
			progress:prepare()
			now = now + 60
			characters:keepAnonymous("Dee Zaster")
			progress:prepare()
			assert.same({ revision = now }, passed("Dee Zaster")[DIRE_MAUL])
			played = "Bea Bop"
			progress:prepare()
			assert.same({}, passed("Dee Zaster"))
		end)

		it("shares nothing of a character never registered", function()
			characters:seeProgress("Ella Vator", { [DIRE_MAUL] = { state = "done", item = 18249 } })
			played = "Ella Vator"
			progress:prepare()
			assert.same({}, passed("Ella Vator"))
		end)
	end)
end)
