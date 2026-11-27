local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Scope", "Professions")
local Memory, Professions, Protocol, Scope = ns.Memory, ns.Professions, ns.Protocol, ns.Scope

describe("Professions", function()
	local DAY = 24 * 60 * 60
	local ALCHEMY, TAILORING, ENCHANTING = 171, 197, 333
	local now, saved, memory, characters, settings, scope, professions, recipeLines, played

	-- The game's skill line of each recipe, as Client looks it up; nil when the
	-- game cannot place it.
	local function recipeSkillLine(recipe)
		return recipeLines[recipe]
	end

	local function clock()
		return now
	end

	-- This account's characters, as Self gives them (the contract of #91): each
	-- name's registration (registered with a nickname, anonymous or
	-- unregistered), its professions as stamped (owned, a removal without a
	-- level) and as read now (current), and the GUID it was played with (guids).
	local function newCharacters()
		local stub =
			{ owned = {}, current = {}, registered = {}, anonymous = {}, unregistered = {}, stamped = {}, guids = {} }
		function stub:guid(name)
			return self.guids[name]
		end
		function stub:owns(name, guid)
			local mine = self.registered[name] or self.anonymous[name] or self.unregistered[name] or self.guids[name]
			return mine ~= nil and not (guid and self.guids[name] and guid ~= self.guids[name])
		end
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
			if self.registered[name] then
				return { nickname = self.registered[name], revision = 1 }
			elseif self.anonymous[name] then
				return { anonymous = true, revision = 1 }
			elseif self.unregistered[name] then
				return { revision = 1 }
			end
		end
		function stub:list()
			local found = {}
			for name, nickname in pairs(self.registered) do
				found[#found + 1] = { name = name, nickname = nickname }
			end
			for name in pairs(self.anonymous) do
				found[#found + 1] = { name = name }
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

	-- Reads the friends and the guild roster as Client does: into a Professions'
	-- scope, then it sees them.
	local function seeLists(of, ofScope, friends, roster)
		ofScope:see(friends, roster)
		of:seeLists()
	end

	before_each(function()
		now = 1000000
		saved = {}
		memory = Memory.new({}, clock)
		characters = newCharacters()
		settings = { passOn = true }
		recipeLines = { [2329] = ALCHEMY, [2330] = ALCHEMY, [7421] = ENCHANTING }
		played = "Bea Bop" -- the character logged on, which syncs: registered, without professions
		characters.registered[played] = "Bea"
		scope = Scope.new(settings)
		professions = Professions.new(saved, clock, memory, characters, settings, scope, recipeSkillLine, function()
			return played
		end)
		seeLists(professions, scope, { "Bo Nanza" }, { "Hugh Jass", "Anna Conda", "Cole Slaw" })
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

	it("ignores a profession its character shares again at an older or the same revision", function()
		professions:hear("Hugh Jass", alchemy(900))
		local heard = now
		now = now + 60
		assert.is_false(professions:hear("Hugh Jass", alchemy(800, { 1 })))
		assert.is_false(professions:hear("Hugh Jass", alchemy(900)))
		assert.same({ 2329, 2330 }, shown("Hugh Jass")[1].recipes)
		assert.equal(heard, shown("Hugh Jass")[1].heard)
	end)

	it("lets a first-hand profession replace a second-hand copy", function()
		professions:hear("Anna Conda", alchemy(5000))
		assert.is_true(professions:hear("Hugh Jass", alchemy(900, { 2330 })))
		assert.same({ 2330 }, shown("Hugh Jass")[1].recipes)
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
		seeLists(professions, scope, {}, { "Hugh Jass" })
		assert.equal(1, #shown("Bo Nanza"))
		now = now + 2 * DAY
		seeLists(professions, scope, {}, { "Hugh Jass" })
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

	it("refuses the professions of a character whose removal came after a disputing nickname", function()
		professions:hear("Anna Conda", alchemy())
		memory:hear("Hugh Jass", { nickname = "Mallory", revision = 900, source = "Bo Nanza" })
		memory:hear("Hugh Jass", { revision = 900, source = "Cole Slaw" })
		assert.same({}, professions:list())
		assert.is_false(professions:hear("Cole Slaw", alchemy(950)))
	end)

	it("drops what a character shared itself once its removal comes undisputed", function()
		professions:hear("Hugh Jass", alchemy(950))
		memory:hear("Hugh Jass", { revision = 1000, source = "Cole Slaw" })
		professions:prune()
		assert.same({}, professions:list())
		assert.is_false(professions:hear("Hugh Jass", alchemy(960)))
	end)

	it("keeps what a character shares itself when a removal disputes its nickname", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Bo Nanza" })
		professions:hear("Hugh Jass", alchemy(950))
		-- A removal at the revision held, which any peer can forge: it disputes the nickname.
		memory:hear("Hugh Jass", { revision = 900, source = "Cole Slaw" })
		local tailoring = alchemy(960)
		tailoring.skillLine = TAILORING
		assert.is_true(professions:hear("Hugh Jass", tailoring))
		professions:prune()
		assert.same({ ALCHEMY, TAILORING }, { shown("Hugh Jass")[1].skillLine, shown("Hugh Jass")[2].skillLine })
		assert.is_false(professions:hear("Cole Slaw", alchemy(970)))
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
		seeLists(professions, scope, {}, roster)
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

	it("drops Jewelcrafting, Inscription and Archaeology, which Forever does not have", function()
		for _, skillLine in ipairs({ 755, 773, 794 }) do
			assert.is_false(
				professions:hear("Hugh Jass", { name = "Hugh Jass", skillLine = skillLine, revision = 900, level = 1 })
			)
		end
		assert.is_nil(saved.held["Hugh Jass"])
	end)

	it("drops a peer's recipe the game places in another profession", function()
		assert.is_true(professions:hear("Anna Conda", alchemy(900, { 2329, 7421, 2330 })))
		assert.same({ 2329, 2330 }, shown("Hugh Jass")[1].recipes)
	end)

	it("drops a peer's recipe the game cannot place", function()
		professions:hear("Hugh Jass", alchemy(900, { 2329, 99999, 2147483647, 2330 }))
		assert.same({ 2329, 2330 }, shown("Hugh Jass")[1].recipes)
	end)

	it("keeps a peer's recipes while the game has placed none this session", function()
		recipeLines = {}
		professions:hear("Hugh Jass", alchemy(900, { 2329, 99999 }))
		assert.same({ 2329, 99999 }, shown("Hugh Jass")[1].recipes)
	end)

	it("keeps a peer's recipe the game places in a skill line it has no profession for", function()
		recipeLines[3000] = 2540
		professions:hear("Hugh Jass", alchemy(900, { 2329, 3000 }))
		assert.same({ 2329, 3000 }, shown("Hugh Jass")[1].recipes)
	end)

	it("hears again a copy with another profession's recipe without disputing it", function()
		professions:hear("Anna Conda", alchemy(900, { 2329, 7421 }))
		assert.is_false(professions:hear("Cole Slaw", alchemy(900, { 2329, 7421 })))
		assert.same({ 2329 }, shown("Hugh Jass")[1].recipes)
	end)

	it("drops from the copies it holds the recipes the game places in another profession", function()
		recipeLines = {}
		professions:hear("Anna Conda", alchemy(900, { 2329, 7421 }))
		recipeLines = { [2329] = ALCHEMY, [7421] = ENCHANTING }
		professions:prune()
		assert.same({ 2329 }, shown("Hugh Jass")[1].recipes)
	end)

	it("drops from the copies it holds the recipes the game cannot place, once it places one", function()
		recipeLines = {}
		professions:hear("Anna Conda", alchemy(900, { 2329, 99999 }))
		recipeLines = { [2329] = ALCHEMY }
		professions:prune()
		assert.same({ 2329 }, shown("Hugh Jass")[1].recipes)
	end)

	it("says a recipe belongs to a profession unless the game places it in another or cannot place it", function()
		assert.is_true(Professions.belongsTo(ALCHEMY, ALCHEMY))
		assert.is_false(Professions.belongsTo(ENCHANTING, ALCHEMY))
		assert.is_false(Professions.belongsTo(nil, ALCHEMY))
		assert.is_true(Professions.belongsTo(2540, ALCHEMY)) -- a skill line not of the game's
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

	describe("the recipes to look for", function()
		local function tailoring(name, recipes)
			return { name = name, skillLine = TAILORING, level = 50, maxLevel = 75, recipes = recipes, revision = 900 }
		end

		it("gives the recipes others know of each of a character's professions that it has not learned", function()
			characters.current["Ann Thrax"] = { { skillLine = TAILORING, level = 10, maxLevel = 75, recipes = { 10 } } }
			professions:hear("Anna Conda", tailoring("Anna Conda", { 30, 10, 20 }))
			professions:hear("Cole Slaw", tailoring("Cole Slaw", { 20, 40 }))
			professions:hear("Hugh Jass", alchemy())
			assert.same({ [TAILORING] = { 20, 30, 40 } }, professions:recipesToFind("Ann Thrax"))
		end)

		it("gives none for a character without professions, or when no one knows more", function()
			professions:hear("Anna Conda", tailoring("Anna Conda", { 10 }))
			assert.same({}, professions:recipesToFind("Ann Thrax"))
			characters.current["Ann Thrax"] = { { skillLine = TAILORING, level = 10, maxLevel = 75, recipes = { 10 } } }
			assert.same({}, professions:recipesToFind("Ann Thrax"))
		end)
	end)

	describe("in a sync", function()
		local function other(roster)
			local theirScope = Scope.new({})
			local theirs = Professions.new(
				{},
				clock,
				Memory.new({}, clock),
				newCharacters(),
				{ passOn = true },
				theirScope
			)
			seeLists(theirs, theirScope, {}, roster or { "Hugh Jass", "Anna Conda", "Cole Slaw" })
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
			table.sort(characters.stamped)
			assert.same({ "Bea Bop", "Dee Zaster" }, characters.stamped)
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

		it("passes on your character's professions with its own GUID, never a peer's, once seen with it", function()
			professions:hear("Anna Conda", alchemy(900)) -- the name's former owner's, passed on with its GUID
			professions:hear(
				"Anna Conda",
				{ name = "Hugh Jass", skillLine = TAILORING, revision = 900, guid = "Player-1-0000000A" }
			)
			characters.registered["Hugh Jass"] = "Tony"
			characters.guids["Hugh Jass"] = "Player-1-0000000B"
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, level = 100, maxLevel = 150, revision = 1500 } }
			professions:prepare()
			professions:see("Hugh Jass", "Player-1-0000000B") -- it speaks in chat
			professions:prepare()
			local passed = professions:answer("Anna Conda", other():digest("Barb Dwyer"))
			assert.same({ "Hugh Jass 171" }, names(passed))
			assert.same({ "Player-1-0000000B", 100 }, { passed[1].guid, passed[1].level })
		end)

		it("passes on again your character's professions an earlier version hid as stale", function()
			saved.held["Hugh Jass"] = {
				own = true,
				guid = "Player-1-0000000A",
				skills = {
					[ALCHEMY] = {
						revision = 1500,
						level = 100,
						maxLevel = 150,
						firstHand = true,
						heard = 1500,
						stale = true,
					},
				},
			}
			characters.registered["Hugh Jass"] = "Tony"
			characters.guids["Hugh Jass"] = "Player-1-0000000B"
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, level = 100, maxLevel = 150, revision = 1500 } }
			professions:prepare()
			local passed = professions:answer("Anna Conda", other():digest("Barb Dwyer"))
			assert.same({ "Hugh Jass 171" }, names(passed))
			assert.equal("Player-1-0000000B", passed[1].guid)
		end)

		it("holds as theirs the professions another player's character tells itself on a name yours had", function()
			characters.registered["Hugh Jass"] = "Tony"
			characters.guids["Hugh Jass"] = "Player-1-0000000A"
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, level = 300, maxLevel = 300, revision = 2000 } }
			professions:prepare()
			local told = alchemy(1900)
			told.guid = "Player-1-0000000B"
			assert.is_true(professions:hear("Hugh Jass", told))
			professions:prepare()
			local found = shown("Hugh Jass")
			assert.same({ 1, 75, true }, { #found, found[1] and found[1].level, found[1] and found[1].firstHand })
			assert.is_nil(found[1].own)
		end)

		it("gives the digest peers on 1.4.0 give for the same professions", function()
			professions:hear("Anna Conda", alchemy())
			professions:hear("Anna Conda", { name = "Cole Slaw", skillLine = ALCHEMY, revision = 900 })
			local buckets = { [96] = "334c8ac3", [99] = "158eb9cc" }
			local expected = {}
			for bucket = 1, Protocol.DIGEST_LENGTH / 8 do
				expected[bucket] = buckets[bucket] or "00000000"
			end
			assert.equal(table.concat(expected), professions:digest("Anna Conda"))
		end)

		it("passes on nothing a peer with the same professions holds", function()
			professions:hear("Anna Conda", alchemy())
			local theirs = other()
			theirs:hear("Cole Slaw", alchemy())
			assert.same({}, professions:answer("Anna Conda", theirs:digest("Cole Slaw")))
		end)

		it("passes on nothing to a peer that dropped the same recipes from a copy", function()
			professions:hear("Anna Conda", alchemy(900, { 2329, 7421 }))
			local theirs = other()
			theirs:hear("Cole Slaw", alchemy(900, { 2329 }))
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

		-- Dee Zaster kept anonymous and Ella Vator unregistered, after both shared
		-- alchemy: Self stamps their professions as removals.
		local function withdrawTwo()
			for name, nickname in pairs({ ["Dee Zaster"] = "Dee", ["Ella Vator"] = "Ella" }) do
				characters.registered[name] = nickname
				characters.owned[name] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
			end
			professions:prepare()
			characters.registered["Dee Zaster"], characters.anonymous["Dee Zaster"] = nil, true
			characters.registered["Ella Vator"], characters.unregistered["Ella Vator"] = nil, true
			for _, name in ipairs({ "Dee Zaster", "Ella Vator" }) do
				characters.owned[name] = { { skillLine = ALCHEMY, revision = 950 } }
			end
			professions:prepare()
		end

		it("passes on nothing of its anonymous or unregistered characters while another one syncs", function()
			withdrawTwo()
			assert.same({}, professions:answer("Anna Conda", other():digest("Barb Dwyer")))
			assert.equal(other():digest("Barb Dwyer"), professions:digest("Anna Conda"))
		end)

		it("passes on an anonymous or unregistered character's removals while it syncs itself", function()
			withdrawTwo()
			played = "Dee Zaster"
			assert.same({ "Dee Zaster 171" }, names(professions:answer("Anna Conda", other():digest("Barb Dwyer"))))
			played = "Ella Vator"
			assert.same({ "Ella Vator 171" }, names(professions:answer("Anna Conda", other():digest("Barb Dwyer"))))
		end)

		it("makes a peer that heard a character first-hand drop its professions once it syncs anonymous", function()
			characters.registered["Hugh Jass"] = "Hugh"
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, level = 75, maxLevel = 150, revision = 900 } }
			played = "Hugh Jass"
			professions:prepare()
			local theirMemory = Memory.new({}, clock)
			local theirScope = Scope.new({})
			local theirs = Professions.new({}, clock, theirMemory, newCharacters(), { passOn = true }, theirScope)
			seeLists(theirs, theirScope, {}, { "Hugh Jass", "Anna Conda", "Cole Slaw" })
			local function sync()
				for _, profession in ipairs(professions:answer("Anna Conda", theirs:digest("Hugh Jass"))) do
					theirs:hear("Hugh Jass", profession)
				end
				theirs:prepare()
			end
			-- The peer heard Hugh Jass's registration and alchemy from it.
			theirMemory:hear("Hugh Jass", { nickname = "Hugh", revision = 1 })
			sync()
			assert.equal(1, #theirs:list())
			-- Kept anonymous while the peer was away: the removal passed on later is
			-- second-hand, and the first-hand registration wins over it.
			characters.registered["Hugh Jass"], characters.anonymous["Hugh Jass"] = nil, true
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, revision = 950 } }
			assert.is_false(theirMemory:hear("Hugh Jass", { revision = 2, source = "Cole Slaw" }))
			professions:prepare()
			sync()
			assert.same({}, theirs:list())
		end)

		it("passes on as a character's own only what it reads, not what peers said before it registered", function()
			professions:hear(
				"Anna Conda",
				{ name = "Hugh Jass", skillLine = 182, revision = 900, level = 200, maxLevel = 300 }
			)
			professions:hear("Anna Conda", alchemy(900))
			characters.registered["Hugh Jass"] = "Hugh"
			characters.owned["Hugh Jass"] = { { skillLine = ALCHEMY, level = 120, maxLevel = 150, revision = 950 } }
			professions:prepare()
			settings.passOn = false
			local passed = professions:answer("Anna Conda", other():digest("Barb Dwyer"))
			assert.same({ "Hugh Jass 171" }, names(passed))
			assert.equal(120, passed[1].level)
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

		it("digests the roster's professions with passing on off, so a guildmate sends none it holds", function()
			local mine = other()
			local theirScope = Scope.new({})
			local theirs = Professions.new(
				{},
				clock,
				Memory.new({}, clock),
				newCharacters(),
				{ passOn = false },
				theirScope
			)
			seeLists(theirs, theirScope, {}, { "Hugh Jass", "Anna Conda", "Cole Slaw" })
			mine:hear("Hugh Jass", alchemy())
			theirs:hear("Anna Conda", alchemy())
			assert.same({}, mine:answer("Cole Slaw", theirs:digest("Anna Conda")))
			assert.same({}, theirs:answer("Anna Conda", other():digest("Cole Slaw")))
		end)

		-- An anonymous character's sync that passed on what only its account holds
		-- of the account's other characters would link it to them (decision 0001).
		describe("while a character that is not registered plays", function()
			local ROSTER = { "Hugh Jass", "Anna Conda", "Cole Slaw", "Dee Zaster" }

			before_each(function()
				-- Dee Zaster, registered, shared alchemy while it played, off the roster.
				characters.registered["Dee Zaster"] = "Dee"
				characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 5, maxLevel = 75, revision = 900 } }
				played = "Dee Zaster"
				professions:prepare()
				played = "Bea Bop"
				characters.registered[played], characters.anonymous[played] = nil, true
				characters.stamped = {}
			end)

			it(
				"passes on the account's other characters' professions as anyone's: only the roster's, to a guildmate",
				function()
					assert.same({}, professions:answer("Anna Conda", other():digest("Barb Dwyer")))
					assert.equal(other():digest("Barb Dwyer"), professions:digest("Anna Conda"))
					seeLists(professions, scope, {}, ROSTER)
					assert.same({}, professions:answer("Bo Nanza", other():digest("Bo Nanza")))
					assert.same(
						{ "Dee Zaster 171" },
						names(professions:answer("Anna Conda", other(ROSTER):digest("Barb Dwyer")))
					)
				end
			)

			it("passes on the account's other characters' professions only while passing on is on", function()
				seeLists(professions, scope, {}, ROSTER)
				settings.passOn = false
				assert.same({}, professions:answer("Anna Conda", other(ROSTER):digest("Barb Dwyer")))
			end)

			it("leaves out of its digest the account's character whose identity it holds as a removal", function()
				seeLists(professions, scope, {}, ROSTER)
				memory:hear("Dee Zaster", { revision = 2000, source = "Cole Slaw" })
				assert.equal(other(ROSTER):digest("Barb Dwyer"), professions:digest("Anna Conda"))
			end)

			it("takes peers' copies of the account's other characters' professions as anyone's", function()
				seeLists(professions, scope, {}, ROSTER)
				local tailoring =
					{ name = "Dee Zaster", skillLine = TAILORING, level = 1, maxLevel = 75, revision = 900 }
				assert.is_true(professions:hear("Anna Conda", tailoring))
				-- As a peer that heard Dee Zaster's alchemy from it: first-hand wins.
				assert.is_false(professions:hear("Anna Conda", {
					name = "Dee Zaster",
					skillLine = ALCHEMY,
					level = 9,
					maxLevel = 75,
					revision = 950,
				}))
			end)

			it("never gives the account's other characters' professions a new revision", function()
				seeLists(professions, scope, {}, ROSTER)
				characters.owned["Dee Zaster"] = { { skillLine = ALCHEMY, level = 6, maxLevel = 75, revision = 1000 } }
				professions:prepare()
				assert.same({ "Bea Bop" }, characters.stamped)
				local passed = professions:answer("Anna Conda", other(ROSTER):digest("Barb Dwyer"))
				assert.same({ 900, 5 }, { passed[1].revision, passed[1].level })
			end)
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
			seeLists(professions, scope, {}, roster)
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

	it("checks the recipes of a copy it holds against the game once a session, not at each roster read", function()
		professions:hear("Anna Conda", alchemy())
		local lookups = 0
		local loaded = Professions.new(saved, clock, memory, characters, settings, scope, function(recipe)
			lookups = lookups + 1
			return recipeLines[recipe]
		end)
		seeLists(loaded, scope, {}, { "Hugh Jass", "Anna Conda" })
		assert.equal(2, lookups)
		seeLists(loaded, scope, {}, { "Hugh Jass", "Anna Conda" })
		loaded:prepare()
		assert.equal(2, lookups)
	end)

	it("checks a held copy again while the game could not place all its recipes", function()
		recipeLines = {}
		professions:hear("Anna Conda", alchemy(900, { 2329, 7421 }))
		professions:prune()
		recipeLines = { [2329] = ALCHEMY, [7421] = ENCHANTING }
		professions:prune()
		assert.same({ 2329 }, shown("Hugh Jass")[1].recipes)
	end)

	it("lets go at load the counts of a peer's changes older than a day", function()
		professions:hear("Anna Conda", alchemy())
		now = now + DAY
		professions:hear("Cole Slaw", alchemy(950))
		Professions.new(saved, clock, memory, characters, settings, scope)
		assert.is_nil(saved.newFrom["Anna Conda"])
		assert.is_not_nil(saved.newFrom["Cole Slaw"])
	end)

	it("loads what it saved", function()
		professions:hear("Anna Conda", alchemy())
		local loaded = Professions.new(saved, clock, memory, characters, settings, scope)
		assert.equal("Anna Conda", loaded:list()[1].source)
	end)
end)
