local ns = require("spec.helpers.addon")("Protocol", "Memory", "Professions")
local Memory, Professions, Protocol = ns.Memory, ns.Professions, ns.Protocol

describe("Professions", function()
	local DAY = 24 * 60 * 60
	local ALCHEMY, TAILORING = 171, 197
	local now, saved, memory, characters, settings, professions

	local function clock()
		return now
	end

	-- This account's characters, as Self gives them (the contract of #91): each
	-- name's professions as stamped (owned, a removal without a level) and as
	-- read now (current).
	local function newCharacters()
		local stub = { owned = {}, current = {}, registered = {}, stamped = {} }
		function stub:withProfessions()
			local found = {}
			for name, list in pairs(self.current) do
				if list[1] then
					found[#found + 1] = name
				end
			end
			table.sort(found)
			return found
		end
		function stub:currentProfessions(name)
			return self.current[name] or {}
		end
		function stub:registration(name)
			return self.registered[name] and { nickname = self.registered[name], revision = 1 }
		end
		function stub:list()
			local found = {}
			for name, nickname in pairs(self.registered) do
				found[#found + 1] = { name = name, nickname = nickname }
			end
			return found
		end
		function stub:stampProfessions(name)
			self.stamped[#self.stamped + 1] = name
		end
		function stub:professions(name)
			return self.owned[name] or {}
		end
		return stub
	end

	before_each(function()
		now = 1000000
		saved = {}
		memory = Memory.new({}, clock)
		characters = newCharacters()
		settings = { passOn = true }
		professions = Professions.new(saved, clock, memory, characters, settings)
		professions:seeLists({ "Bo Nanza" }, { "Hugh Jass", "Anna Conda", "Cole Slaw" })
	end)

	local function alchemy(revision, recipes)
		return {
			name = "Hugh Jass",
			skillLine = ALCHEMY,
			level = 75,
			maxLevel = 150,
			recipes = recipes or { 2329, 2330 },
			revision = revision or 900,
		}
	end

	local function shown(name)
		local found = {}
		for _, profession in ipairs(professions:list()) do
			if profession.name == name then
				found[#found + 1] = profession
			end
		end
		return found
	end

	it("keeps a profession heard first-hand, with its skill level and recipes", function()
		assert.is_true(professions:hear("Hugh Jass", alchemy()))
		assert.same({
			{
				name = "Hugh Jass",
				skillLine = ALCHEMY,
				level = 75,
				maxLevel = 150,
				recipes = { 2329, 2330 },
				revision = 900,
				firstHand = true,
				heard = now,
			},
		}, professions:list())
	end)

	it("keeps a profession heard second-hand with its source", function()
		professions:hear("Anna Conda", alchemy())
		local profession = shown("Hugh Jass")[1]
		assert.is_false(profession.firstHand)
		assert.equal("Anna Conda", profession.source)
	end)

	it("keeps each of a character's professions apart, each with its own revision", function()
		professions:hear("Hugh Jass", alchemy(900))
		professions:hear(
			"Hugh Jass",
			{ name = "Hugh Jass", skillLine = TAILORING, level = 10, maxLevel = 75, revision = 800 }
		)
		local list = shown("Hugh Jass")
		assert.equal(2, #list)
		assert.equal(ALCHEMY, list[1].skillLine)
		assert.equal(TAILORING, list[2].skillLine)
		assert.is_nil(list[2].recipes)
	end)

	it("lets a later revision win among second-hand copies, never an older one", function()
		professions:hear("Anna Conda", alchemy(900))
		assert.is_true(professions:hear("Cole Slaw", alchemy(950, { 2329 })))
		assert.is_false(professions:hear("Anna Conda", alchemy(900)))
		assert.same({ 2329 }, shown("Hugh Jass")[1].recipes)
	end)

	it("never lets a second-hand copy replace a first-hand profession", function()
		professions:hear("Hugh Jass", alchemy(900))
		assert.is_false(professions:hear("Anna Conda", alchemy(5000, { 1 })))
		assert.is_true(shown("Hugh Jass")[1].firstHand)
	end)

	it("lets a first-hand profession replace a second-hand copy", function()
		professions:hear("Anna Conda", alchemy(5000))
		assert.is_true(professions:hear("Hugh Jass", alchemy(900, { 3 })))
		assert.same({ 3 }, shown("Hugh Jass")[1].recipes)
	end)

	it("hides a profession two peers pass on at the same revision with different content", function()
		professions:hear("Anna Conda", alchemy(900))
		assert.is_true(professions:hear("Cole Slaw", alchemy(900, { 1 })))
		assert.same({ { name = "Hugh Jass", skillLine = ALCHEMY, disputed = true } }, professions:list())
		assert.is_true(professions:hear("Hugh Jass", alchemy(800)))
		assert.equal(800, shown("Hugh Jass")[1].revision)
	end)

	it("takes a removal: the profession no longer shows, and an older copy does not bring it back", function()
		professions:hear("Anna Conda", alchemy(900))
		assert.is_true(professions:hear("Cole Slaw", { name = "Hugh Jass", skillLine = ALCHEMY, revision = 950 }))
		assert.same({}, professions:list())
		assert.is_false(professions:hear("Anna Conda", alchemy(900)))
		assert.same({}, professions:list())
	end)

	it("refuses a revision more than a day ahead of the clock", function()
		assert.is_false(professions:hear("Anna Conda", alchemy(now + DAY + 1)))
	end)

	it("keeps professions only for the guild roster and friends' characters", function()
		assert.is_false(
			professions:hear(
				"Anna Conda",
				{ name = "Zed Ex", skillLine = ALCHEMY, revision = 900, level = 1, maxLevel = 75 }
			)
		)
		assert.is_true(
			professions:hear(
				"Anna Conda",
				{ name = "Bo Nanza", skillLine = ALCHEMY, revision = 900, level = 1, maxLevel = 75 }
			)
		)
	end)

	it("drops quietly a friend's character's professions 30 days after it was last seen online", function()
		professions:hear(
			"Bo Nanza",
			{ name = "Bo Nanza", skillLine = ALCHEMY, revision = 900, level = 1, maxLevel = 75 }
		)
		now = now + 29 * DAY
		professions:seeLists({}, { "Hugh Jass" })
		assert.equal(1, #shown("Bo Nanza"))
		now = now + 2 * DAY
		professions:seeLists({}, { "Hugh Jass" })
		assert.same({}, shown("Bo Nanza"))
		assert.is_nil(saved.held["Bo Nanza"])
	end)

	it("drops and refuses a forgotten character's second-hand professions, until unforgotten", function()
		professions:hear("Anna Conda", alchemy())
		memory:forget("Hugh Jass")
		assert.same({}, professions:list())
		professions:prune()
		assert.is_nil(saved.held["Hugh Jass"])
		assert.is_false(professions:hear("Cole Slaw", alchemy(950)))
		memory:unforget("Hugh Jass")
		assert.is_true(professions:hear("Cole Slaw", alchemy(950)))
	end)

	it("lets a forgotten character's first-hand profession through, and keeps it", function()
		memory:forget("Hugh Jass")
		assert.is_true(professions:hear("Hugh Jass", alchemy(950)))
		professions:prune()
		assert.is_true(shown("Hugh Jass")[1].firstHand)
		assert.is_false(professions:hear("Cole Slaw", alchemy(5000)))
	end)

	it(
		"refuses and drops the professions of a character whose identity it holds as a removal, until it shows",
		function()
			professions:hear("Anna Conda", alchemy())
			memory:hear("Hugh Jass", { revision = 900 }) -- anonymous
			assert.same({}, professions:list())
			assert.is_false(professions:hear("Cole Slaw", alchemy(950)))
			professions:prune()
			assert.is_nil(saved.held["Hugh Jass"])
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 1000 })
			assert.is_true(professions:hear("Cole Slaw", alchemy(950)))
		end
	)

	it("refuses the professions of a character whose removal is disputed", function()
		professions:hear("Anna Conda", alchemy())
		memory:hear("Hugh Jass", { revision = 900, source = "Cole Slaw" })
		memory:hear("Hugh Jass", { nickname = "Mallory", revision = 900, source = "Bo Nanza" })
		assert.same({}, professions:list())
		assert.is_false(professions:hear("Cole Slaw", alchemy(950)))
	end)

	it("shows a character's professions when its identity is unknown", function()
		professions:hear("Anna Conda", alchemy())
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.equal(1, #shown("Hugh Jass"))
	end)

	it("hides a reused name's professions until the character that took it shares first-hand", function()
		professions:hear("Anna Conda", alchemy())
		professions:see("Hugh Jass", "Player-1-00000001")
		assert.equal(1, #shown("Hugh Jass"))
		professions:see("Hugh Jass", "Player-1-00000002")
		assert.same({}, shown("Hugh Jass"))
		assert.is_false(professions:hear("Cole Slaw", alchemy(5000)))
		assert.is_true(
			professions:hear(
				"Hugh Jass",
				{ name = "Hugh Jass", skillLine = TAILORING, level = 1, maxLevel = 75, revision = 6000 }
			)
		)
		local list = shown("Hugh Jass")
		assert.equal(1, #list)
		assert.equal(TAILORING, list[1].skillLine)
	end)

	it("never adopts what peers say of this account's own characters", function()
		characters.registered["Hugh Jass"] = "Tony"
		assert.is_false(professions:hear("Anna Conda", alchemy()))
	end)

	it("takes at most 2,000 second-hand changes a day from one peer, first-hand ones aside", function()
		local roster = {}
		for i = 1, Professions.MAX_CHANGES_PER_PEER + 10 do
			roster[i] = "Name Number" .. i
		end
		roster[#roster + 1] = "Anna Conda"
		professions:seeLists({}, roster)
		local taken = 0
		for i = 1, Professions.MAX_CHANGES_PER_PEER + 10 do
			local heard = { name = "Name Number" .. i, skillLine = ALCHEMY, revision = 900, level = 1, maxLevel = 75 }
			taken = taken + (professions:hear("Anna Conda", heard) and 1 or 0)
		end
		assert.equal(Professions.MAX_CHANGES_PER_PEER, taken)
		assert.is_true(professions:hear("Anna Conda", { name = "Anna Conda", skillLine = ALCHEMY, revision = 900 }))
		assert.is_true(professions:hear("Cole Slaw", { name = "Name Number1", skillLine = ALCHEMY, revision = 950 }))
		now = now + DAY
		assert.is_true(
			professions:hear("Anna Conda", { name = "Name Number2001", skillLine = ALCHEMY, revision = 950 })
		)
	end)

	it("takes only the game's skill lines, first-hand or second-hand", function()
		assert.is_false(professions:hear("Hugh Jass", { name = "Hugh Jass", skillLine = 1, revision = 900 }))
		assert.is_false(professions:hear("Anna Conda", { name = "Hugh Jass", skillLine = 1, revision = 900 }))
		assert.is_nil(saved.held["Hugh Jass"])
	end)

	it("shows this account's characters' professions before any sync, registered or not", function()
		settings.shareProfessions = false
		characters.current["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, recipes = { 2329 } } }
		assert.same({
			{
				name = "Dee Zaster",
				skillLine = ALCHEMY,
				level = 5,
				maxLevel = 75,
				recipes = { 2329 },
				firstHand = true,
				own = true,
			},
		}, professions:list())
		assert.same(
			{ { recipe = 2329, knownBy = { { name = "Dee Zaster", firstHand = true } } } },
			professions:recipes(ALCHEMY)
		)
	end)

	it("counts the changes heard from peers, for the window to redraw", function()
		assert.equal(0, professions.changes)
		professions:hear("Anna Conda", alchemy())
		professions:hear("Anna Conda", alchemy())
		assert.equal(1, professions.changes)
		professions:hear("Cole Slaw", alchemy(900, { 1 }))
		assert.equal(2, professions.changes)
	end)

	it("lists who knows each recipe of a profession", function()
		professions:hear("Hugh Jass", alchemy(900, { 2329, 2330 }))
		professions:hear(
			"Anna Conda",
			{ name = "Cole Slaw", skillLine = ALCHEMY, level = 1, maxLevel = 75, recipes = { 2330 }, revision = 900 }
		)
		assert.same({
			{ recipe = 2329, knownBy = { { name = "Hugh Jass", firstHand = true } } },
			{
				recipe = 2330,
				knownBy = {
					{ name = "Cole Slaw", firstHand = false, source = "Anna Conda" },
					{ name = "Hugh Jass", firstHand = true },
				},
			},
		}, professions:recipes(ALCHEMY))
	end)

	describe("in a sync", function()
		local function other(roster)
			local theirs = Professions.new({}, clock, Memory.new({}, clock), newCharacters(), { passOn = true })
			theirs:seeLists({}, roster or { "Hugh Jass", "Anna Conda", "Cole Slaw" })
			return theirs
		end

		local function names(list)
			local found = {}
			for _, profession in ipairs(list) do
				found[#found + 1] = profession.name .. " " .. profession.skillLine
			end
			table.sort(found)
			return found
		end

		it("stamps and reads this account's characters' professions as first-hand", function()
			characters.registered["Dee Zaster"] = "Dee"
			characters.owned["Dee Zaster"] = {
				{ skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 },
				{ skillLine = TAILORING, revision = 950 },
			}
			professions:prepare()
			assert.same({ "Dee Zaster" }, characters.stamped)
			assert.same(
				{ "Dee Zaster 171", "Dee Zaster 197" },
				names(professions:answer("Anna Conda", other():digest("Barb Dwyer")))
			)
		end)

		it("shows this account's characters' professions as read now, never their stamped copies", function()
			characters.registered["Dee Zaster"] = "Dee"
			characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
			professions:prepare()
			characters.current["Dee Zaster"] = { { skillLine = ALCHEMY, level = 6, maxLevel = 75, recipes = { 7 } } }
			assert.same({
				{
					name = "Dee Zaster",
					skillLine = ALCHEMY,
					level = 6,
					maxLevel = 75,
					recipes = { 7 },
					firstHand = true,
					own = true,
				},
			}, shown("Dee Zaster"))
		end)

		it("passes on what the peer lacks, a removal included, with the GUID it knows", function()
			professions:hear("Anna Conda", alchemy())
			professions:see("Hugh Jass", "Player-1-00000001")
			professions:hear("Anna Conda", { name = "Cole Slaw", skillLine = ALCHEMY, revision = 900 })
			local passed = professions:answer("Anna Conda", other():digest("Barb Dwyer"))
			assert.same({ "Cole Slaw 171", "Hugh Jass 171" }, names(passed))
			local hugh = passed[1].name == "Hugh Jass" and passed[1] or passed[2]
			assert.equal("Player-1-00000001", hugh.guid)
			assert.same({ 2329, 2330 }, hugh.recipes)
		end)

		it("passes on nothing a peer with the same professions holds", function()
			professions:hear("Anna Conda", alchemy())
			local theirs = other()
			theirs:hear("Cole Slaw", alchemy())
			assert.same({}, professions:answer("Anna Conda", theirs:digest("Cole Slaw")))
		end)

		it("passes on to a friend outside the guild only this account's characters' professions", function()
			characters.registered["Dee Zaster"] = "Dee"
			characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
			professions:hear("Anna Conda", alchemy())
			professions:prepare()
			assert.same({ "Dee Zaster 171" }, names(professions:answer("Bo Nanza", other():digest("Bo Nanza"))))
			assert.same(
				{ "Dee Zaster 171", "Hugh Jass 171" },
				names(professions:answer("Anna Conda", other():digest("Barb Dwyer")))
			)
		end)

		it("passes on nothing to a peer neither on the roster nor a friend, which would refuse it", function()
			characters.registered["Dee Zaster"] = "Dee"
			characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
			professions:prepare()
			assert.same({}, professions:answer("Barb Dwyer", other():digest("Barb Dwyer")))
		end)

		it("passes on its own characters' professions, but no other, once passing on is off", function()
			characters.registered["Dee Zaster"] = "Dee"
			characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
			professions:hear("Anna Conda", alchemy())
			professions:prepare()
			settings.passOn = false
			assert.same({ "Dee Zaster 171" }, names(professions:answer("Anna Conda", other():digest("Barb Dwyer"))))
		end)

		it("never passes on a disputed or stale profession", function()
			professions:hear("Anna Conda", alchemy(900))
			professions:hear("Cole Slaw", alchemy(900, { 1 }))
			professions:hear("Anna Conda", { name = "Cole Slaw", skillLine = ALCHEMY, revision = 900 })
			professions:see("Cole Slaw", "Player-1-00000001")
			professions:see("Cole Slaw", "Player-1-00000002")
			assert.same({}, professions:answer("Anna Conda", other():digest("Barb Dwyer")))
		end)

		it("passes on at most 100 KB, first-hand changes of the past day first", function()
			local roster = { "Anna Conda" }
			local recipes = {}
			for i = 1, 300 do
				recipes[i] = 1000000 + i * 1000
			end
			for i = 1, 200 do
				roster[#roster + 1] = "Name Number" .. i
			end
			professions:seeLists({}, roster)
			for i = 1, 200 do
				local name = "Name Number" .. i
				-- The last ten heard first-hand today, the rest second-hand, long ago.
				local peer = i > 190 and name or "Anna Conda"
				local revision = i > 190 and now - i or 900
				professions:hear(peer, {
					name = name,
					skillLine = ALCHEMY,
					level = 1,
					maxLevel = 75,
					recipes = recipes,
					revision = revision,
				})
			end
			local passed = professions:answer("Anna Conda", other(roster):digest("Barb Dwyer"))
			local bytes = 0
			for _, profession in ipairs(passed) do
				bytes = bytes + #Protocol.writeProfession(profession) + 1
			end
			assert.is_true(bytes <= Professions.MAX_SYNC_BYTES)
			assert.is_true(#passed < 200)
			assert.equal("Name Number191", passed[1].name)
			assert.equal("Name Number200", passed[10].name)
		end)
	end)

	it("loads what it saved", function()
		professions:hear("Anna Conda", alchemy())
		local loaded = Professions.new(saved, clock, memory, characters, settings)
		assert.equal("Anna Conda", loaded:list()[1].source)
	end)
end)
