local Self = require("spec.helpers.addon")("Protocol", "Milestones", "Self").Self

describe("Self", function()
	local now, saved, settings, characters

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		settings = {}
		characters = Self.new(saved, clock, settings)
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

	it("trims the spaces around a nickname and collapses the runs inside it", function()
		assert.is_true(characters:register("Hugh Jass", "  Tony   the  tank "))
		assert.equal("Tony the tank", characters:registration("Hugh Jass").nickname)
	end)

	it("refuses a nickname made only of spaces", function()
		local ok, reason = characters:register("Hugh Jass", "   ")
		assert.is_false(ok)
		assert.equal("empty", reason)
		assert.is_nil(characters:registration("Hugh Jass"))
	end)

	it("refuses no nickname at all, as empty", function()
		local ok, reason = characters:register("Hugh Jass", nil)
		assert.is_false(ok)
		assert.equal("empty", reason)
		assert.is_nil(characters:registration("Hugh Jass"))
	end)

	it("counts a nickname's length after trimming it", function()
		assert.is_true(characters:register("Hugh Jass", "  " .. string.rep("a", 32) .. "  "))
	end)

	it("registers a nickname without the emoji variation selectors, which show nothing", function()
		-- U+2764 U+FE0F, the red heart as phones type it, and U+FE0E.
		assert.is_true(characters:register("Hugh Jass", "Jo\226\157\164\239\184\143"))
		assert.equal("Jo\226\157\164", characters:registration("Hugh Jass").nickname)
		assert.is_true(characters:register("Anna Conda", "Ann\226\157\164\239\184\142"))
		assert.equal("Ann\226\157\164", characters:registration("Anna Conda").nickname)
	end)

	describe("a saved nickname the rules now refuse", function()
		it("is repaired at load when removing its emoji variation selectors is enough, with a new revision", function()
			saved["Hugh Jass"] = { nickname = "Jo\226\157\164\239\184\143", revision = 500 }
			characters = Self.new(saved, clock, settings)
			assert.same({ nickname = "Jo\226\157\164", revision = 1000 }, characters:registration("Hugh Jass"))
		end)

		it("sends the character back to being asked at load otherwise, keeping its professions", function()
			local professions = { [171] = { level = 50, maxLevel = 75 } }
			saved["Hugh Jass"] = { nickname = "\227\133\164", revision = 500, professions = professions }
			characters = Self.new(saved, clock, settings)
			assert.equal("notAsked", characters:state("Hugh Jass"))
			assert.is_nil(characters:message("Hugh Jass", "answer"))
			assert.same({}, characters:prompt("Hugh Jass"))
			assert.equal(professions, saved["Hugh Jass"].professions)
		end)

		it("leaves a saved nickname the rules still take as it was", function()
			saved["Hugh Jass"] = { nickname = "Tony", revision = 500 }
			characters = Self.new(saved, clock, settings)
			assert.same({ nickname = "Tony", revision = 500 }, characters:registration("Hugh Jass"))
		end)
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
		assert.same({ nickname = "Tony", revision = 1000 }, Self.new(saved, clock, settings):registration("Hugh Jass"))
	end)

	it("remembers the GUID of a character played, in its saved table, and none for one never played", function()
		characters:register("Hugh Jass", "Tony")
		characters:see("Hugh Jass", "Player-1-00000001")
		assert.equal("Player-1-00000001", Self.new(saved, clock, settings):guid("Hugh Jass"))
		assert.is_nil(characters:guid("Anna Conda"))
		assert.same({ nickname = "Tony", revision = 1000 }, characters:registration("Hugh Jass"))
	end)

	it("remembers in its saved table that a character started empty, not from the seed", function()
		characters:register("Hugh Jass", "Tony")
		characters:startEmpty("Anna Conda")
		local loaded = Self.new(saved, clock, settings)
		assert.same({ false, true }, { loaded:startedEmpty("Hugh Jass"), loaded:startedEmpty("Anna Conda") })
		assert.equal("notAsked", loaded:state("Anna Conda"))
	end)

	describe("whether a name is one of its characters", function()
		local GUID, OTHER = "Player-1-00000001", "Player-1-00000002"

		it("tells its characters by name while the GUID seen is theirs or either is unknown", function()
			characters:register("Hugh Jass", "Tony")
			characters:keepAnonymous("Anna Conda") -- never played since GUIDs were kept: none
			characters:see("Hugh Jass", GUID)
			assert.same({ true, true, true, true }, {
				characters:owns("Hugh Jass"),
				characters:owns("Hugh Jass", GUID),
				characters:owns("Anna Conda"),
				characters:owns("Anna Conda", OTHER),
			})
			assert.is_false(characters:owns("Cole Slaw"))
		end)

		it("tells another player's character on a name one of its characters had by its other GUID", function()
			characters:register("Hugh Jass", "Tony")
			characters:see("Hugh Jass", GUID)
			assert.is_false(characters:owns("Hugh Jass", OTHER))
		end)

		it("remembers a name of its characters seen with another GUID as taken, until it is played again", function()
			characters:register("Hugh Jass", "Tony")
			characters:see("Hugh Jass", GUID)
			characters:seeName("Hugh Jass", GUID)
			assert.is_true(characters:owns("Hugh Jass"))
			characters:seeName("Hugh Jass", OTHER) -- another player's character took the name
			characters:seeName("Anna Conda", OTHER) -- not one of its characters
			local loaded = Self.new(saved, clock, settings)
			assert.same({ false, false, true, false }, {
				loaded:owns("Hugh Jass"),
				loaded:owns("Hugh Jass", OTHER),
				loaded:owns("Hugh Jass", GUID),
				loaded:owns("Anna Conda"),
			})
			loaded:see("Hugh Jass", "Player-1-00000003") -- a character of the account takes the name again
			assert.is_true(loaded:owns("Hugh Jass"))
		end)

		it("tells its characters by GUID alone, never by name, when asked whether a GUID is theirs", function()
			characters:register("Hugh Jass", "Tony")
			characters:keepAnonymous("Anna Conda")
			characters:see("Hugh Jass", GUID)
			assert.same({ true, false, false, false }, {
				characters:ownsGuid("Hugh Jass", GUID),
				characters:ownsGuid("Hugh Jass", OTHER),
				characters:ownsGuid("Hugh Jass", nil),
				characters:ownsGuid("Anna Conda", OTHER),
			})
		end)

		it("never takes a name of a character never played since GUIDs were kept as taken", function()
			characters:keepAnonymous("Anna Conda")
			characters:seeName("Anna Conda", OTHER)
			assert.is_true(characters:owns("Anna Conda"))
		end)
	end)

	describe("states", function()
		it("has not asked about a character never registered", function()
			assert.equal("notAsked", characters:state("Hugh Jass"))
		end)

		it("calls a character with a nickname registered", function()
			characters:register("Hugh Jass", "Tony")
			assert.equal("registered", characters:state("Hugh Jass"))
		end)

		it("keeps a character anonymous with a later revision", function()
			characters:register("Hugh Jass", "Tony")
			assert.is_true(characters:keepAnonymous("Hugh Jass"))
			assert.equal("anonymous", characters:state("Hugh Jass"))
			assert.same({ anonymous = true, revision = 1001 }, characters:registration("Hugh Jass"))
		end)

		it("keeps a character never registered anonymous, at the server's time", function()
			assert.is_true(characters:keepAnonymous("Hugh Jass"))
			assert.same({ anonymous = true, revision = 1000 }, characters:registration("Hugh Jass"))
		end)

		it("does not keep an anonymous character anonymous again", function()
			characters:keepAnonymous("Hugh Jass")
			now = 2000
			assert.is_false(characters:keepAnonymous("Hugh Jass"))
			assert.equal(1000, characters:registration("Hugh Jass").revision)
		end)

		it("registers an anonymous character when its player changes their mind", function()
			characters:keepAnonymous("Hugh Jass")
			characters:register("Hugh Jass", "Tony")
			assert.equal("registered", characters:state("Hugh Jass"))
			assert.same({ nickname = "Tony", revision = 1001 }, characters:registration("Hugh Jass"))
		end)

		it("does not unregister an anonymous character", function()
			characters:keepAnonymous("Hugh Jass")
			assert.is_false(characters:unregister("Hugh Jass"))
			assert.equal("anonymous", characters:state("Hugh Jass"))
		end)

		it("calls a character that withdrew its registration unregistered", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.equal("unregistered", characters:state("Hugh Jass"))
		end)

		it("registers a character again after it unregistered", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.is_true(characters:register("Hugh Jass", "Antoine"))
			assert.equal("registered", characters:state("Hugh Jass"))
		end)

		it("remembers an anonymous character in its saved table", function()
			characters:keepAnonymous("Hugh Jass")
			assert.equal("anonymous", Self.new(saved, clock, settings):state("Hugh Jass"))
		end)

		it("counts the characters in each state", function()
			characters:register("Hugh Jass", "Tony")
			characters:register("Anna Conda", "Tony")
			characters:keepAnonymous("Barb Dwyer")
			assert.equal(2, characters:count("registered"))
			assert.equal(1, characters:count("anonymous"))
		end)
	end)

	describe("the message a character sends", function()
		it("announces and answers with the nickname of a registered character", function()
			characters:register("Hugh Jass", "Tony")
			local expected = { kind = "announcement", nickname = "Tony", revision = 1000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			expected.kind = "answer"
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("says an anonymous character is anonymous", function()
			characters:keepAnonymous("Hugh Jass")
			local expected = { kind = "anonymous", revision = 1000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("sends the removal of a character that unregistered", function()
			characters:register("Hugh Jass", "Tony")
			now = 2000
			characters:unregister("Hugh Jass")
			local expected = { kind = "removal", revision = 2000 }
			assert.same(expected, characters:message("Hugh Jass", "announce"))
			assert.same(expected, characters:message("Hugh Jass", "answer"))
		end)

		it("sends nothing about a character not asked yet", function()
			assert.is_nil(characters:message("Hugh Jass", "announce"))
			assert.is_nil(characters:message("Hugh Jass", "answer"))
		end)

		it("asks, whatever the character's state", function()
			assert.same({ kind = "ask" }, characters:message("Hugh Jass", "ask"))
			characters:register("Hugh Jass", "Tony")
			assert.same({ kind = "ask" }, characters:message("Hugh Jass", "ask"))
		end)
	end)

	describe("the registration prompt", function()
		it("prompts for a character not asked yet, with nothing to pre-fill", function()
			assert.same({}, characters:prompt("Hugh Jass"))
		end)

		it("does not prompt for a registered character", function()
			characters:register("Hugh Jass", "Tony")
			assert.is_nil(characters:prompt("Hugh Jass"))
		end)

		it("does not prompt for an anonymous character", function()
			characters:keepAnonymous("Hugh Jass")
			assert.is_nil(characters:prompt("Hugh Jass"))
			assert.is_nil(Self.new(saved, clock, settings):prompt("Hugh Jass"))
		end)

		it("does not prompt for a character that unregistered, even at a later login", function()
			characters:register("Hugh Jass", "Tony")
			characters:unregister("Hugh Jass")
			assert.is_nil(characters:prompt("Hugh Jass"))
			assert.is_nil(Self.new(saved, clock, settings):prompt("Hugh Jass"))
		end)

		it("prompts again at the next login when the player asked to be asked later", function()
			characters:prompt("Hugh Jass")
			assert.same({}, Self.new(saved, clock, settings):prompt("Hugh Jass"))
		end)

		it("pre-fills the nickname of the player's latest registered character", function()
			characters:register("Anna Conda", "Tony")
			now = 2000
			characters:register("Barb Dwyer", "Antoine")
			characters:keepAnonymous("Paige Turner")
			assert.same({ nickname = "Antoine" }, characters:prompt("Hugh Jass"))
		end)

		it("pre-fills what peers say about the character when no other character is registered", function()
			local heard = { nickname = "Tony", revision = 900, firstHand = false, heard = 950 }
			assert.same({ nickname = "Tony", fromPeers = true }, characters:prompt("Hugh Jass", heard))
		end)

		it("prefers the player's other characters to what peers say", function()
			characters:register("Anna Conda", "Antoine")
			local heard = { nickname = "Tony", revision = 900, firstHand = false, heard = 950 }
			assert.same({ nickname = "Antoine" }, characters:prompt("Hugh Jass", heard))
		end)

		it("never adopts what peers say without the player's click", function()
			characters:prompt("Hugh Jass", { nickname = "Tony", revision = 900, firstHand = false, heard = 950 })
			assert.is_nil(characters:registration("Hugh Jass"))
			assert.equal("notAsked", characters:state("Hugh Jass"))
		end)
	end)
	describe("professions", function()
		local TAILORING, COOKING = 197, 185

		before_each(function()
			characters:register("Hugh Jass", "Tony")
		end)

		it("shares nothing about a profession before a sync stamps it", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			assert.same({}, characters:professions("Hugh Jass"))
		end)

		it(
			"gives each profession a revision at the server's time when a sync stamps it, sorted by skill line",
			function()
				characters:seeProfessions("Hugh Jass", {
					{ skillLine = TAILORING, level = 50, maxLevel = 75 },
					{ skillLine = COOKING, level = 1, maxLevel = 75 },
				})
				characters:stampProfessions("Hugh Jass")
				assert.same({
					{ skillLine = COOKING, level = 1, maxLevel = 75, revision = 1000 },
					{ skillLine = TAILORING, level = 50, maxLevel = 75, revision = 1000 },
				}, characters:professions("Hugh Jass"))
			end
		)

		it("keeps the revision of a profession that has not changed since its last one", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			now = 2000
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			assert.equal(1000, characters:professions("Hugh Jass")[1].revision)
		end)

		it("shares a skill level change only at the next stamp, with a later revision", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 60, maxLevel = 75 } })
			assert.equal(50, characters:professions("Hugh Jass")[1].level)
			characters:stampProfessions("Hugh Jass")
			assert.same(
				{ { skillLine = TAILORING, level = 60, maxLevel = 75, revision = 1001 } },
				characters:professions("Hugh Jass")
			)
		end)

		it("shares the learned recipes, sorted, once the profession's window was opened", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeRecipes("Hugh Jass", TAILORING, { 30, 10, 20 }, { 30, 10 })
			characters:stampProfessions("Hugh Jass")
			assert.same({ 10, 30 }, characters:professions("Hugh Jass")[1].recipes)
		end)

		it("ignores the recipes of a profession the character does not have", function()
			characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
			characters:stampProfessions("Hugh Jass")
			assert.same({}, characters:professions("Hugh Jass"))
			assert.same({}, characters:recipeIDs("Hugh Jass"))
		end)

		it("gives the saved recipe IDs of each profession, to recheck which are learned", function()
			characters:seeProfessions("Hugh Jass", {
				{ skillLine = TAILORING, level = 50, maxLevel = 75 },
				{ skillLine = COOKING, level = 1, maxLevel = 75 },
			})
			characters:seeRecipes("Hugh Jass", TAILORING, { 30, 10, 20 }, { 10 })
			assert.same({ [TAILORING] = { 10, 20, 30 } }, characters:recipeIDs("Hugh Jass"))
		end)

		it("shares a recipe learned since the last stamp, with a later revision", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeRecipes("Hugh Jass", TAILORING, { 10, 20 }, { 10 })
			characters:stampProfessions("Hugh Jass")
			characters:seeRecipes("Hugh Jass", TAILORING, { 10, 20 }, { 20, 10 })
			characters:stampProfessions("Hugh Jass")
			assert.same(
				{ { skillLine = TAILORING, level = 50, maxLevel = 75, recipes = { 10, 20 }, revision = 1001 } },
				characters:professions("Hugh Jass")
			)
		end)

		it("takes recipes read under the wrong profession away from it", function()
			characters:seeProfessions("Hugh Jass", {
				{ skillLine = TAILORING, level = 50, maxLevel = 75 },
				{ skillLine = COOKING, level = 1, maxLevel = 75 },
			})
			-- A window read while the game still gave the profession before it.
			characters:seeRecipes("Hugh Jass", COOKING, { 10, 20 }, { 10 })
			characters:seeRecipes("Hugh Jass", TAILORING, { 10, 20, 30 }, { 10 })
			assert.same({ [TAILORING] = { 10, 20, 30 } }, characters:recipeIDs("Hugh Jass"))
			assert.is_nil(characters:currentProfessions("Hugh Jass")[1].recipes) -- Cooking
		end)

		it("keeps the recipes when the skill level is read again", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 51, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			assert.same({ 10 }, characters:professions("Hugh Jass")[1].recipes)
		end)

		describe("recipes found learned", function()
			it("adds them to a profession with no saved recipe list when the game puts them in it", function()
				characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
				assert.is_true(characters:learnRecipes("Hugh Jass", TAILORING, { [30] = TAILORING, [20] = COOKING }))
				characters:stampProfessions("Hugh Jass")
				assert.same({ 30 }, characters:professions("Hugh Jass")[1].recipes)
				assert.same({}, characters:recipeIDs("Hugh Jass"))
			end)

			it("merges them with the learned ones, sorted, and says when nothing changed", function()
				characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
				characters:seeRecipes("Hugh Jass", TAILORING, { 10, 30 }, { 30 })
				assert.is_true(characters:learnRecipes("Hugh Jass", TAILORING, { [10] = TAILORING, [5] = TAILORING }))
				assert.is_false(characters:learnRecipes("Hugh Jass", TAILORING, { [10] = TAILORING }))
				assert.same({ 5, 10, 30 }, characters:currentProfessions("Hugh Jass")[1].recipes)
				assert.same({ [TAILORING] = { 10, 30 } }, characters:recipeIDs("Hugh Jass"))
			end)

			it("ignores them for a profession the character does not have, or when none belongs to it", function()
				assert.is_false(characters:learnRecipes("Hugh Jass", TAILORING, { [10] = TAILORING }))
				characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
				assert.is_false(characters:learnRecipes("Hugh Jass", TAILORING, { [10] = COOKING }))
				assert.is_nil(characters:currentProfessions("Hugh Jass")[1].recipes)
			end)
		end)

		describe("the hint to open the profession windows", function()
			local function both()
				characters:seeProfessions("Hugh Jass", {
					{ skillLine = TAILORING, level = 50, maxLevel = 75 },
					{ skillLine = COOKING, level = 1, maxLevel = 75 },
				})
			end

			it("names in the prompt the professions with no saved recipe list", function()
				both()
				characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
				assert.same({ COOKING }, characters:recipeHint("Hugh Jass", true))
			end)

			it("shows once per character", function()
				both()
				characters:hintRecipes("Hugh Jass")
				assert.is_nil(characters:recipeHint("Hugh Jass", true))
				assert.is_nil(characters:recipeHint("Hugh Jass"))
			end)

			it("does not show at login for a character not registered", function()
				characters:seeProfessions("Anna Conda", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
				assert.is_nil(characters:recipeHint("Anna Conda"))
				assert.same({ TAILORING }, characters:recipeHint("Anna Conda", true))
			end)

			it("shows at login for a registered character none of whose professions has a saved list", function()
				both()
				assert.same({ COOKING, TAILORING }, characters:recipeHint("Hugh Jass"))
				characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
				assert.is_nil(characters:recipeHint("Hugh Jass"))
			end)

			it("does not show for a character without professions", function()
				characters:register("Hugh Jass", "Tony")
				assert.is_nil(characters:recipeHint("Hugh Jass"))
				assert.is_nil(characters:recipeHint("Anna Conda", true))
			end)
		end)

		it("turns a dropped profession into a removal at the next stamp", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", {})
			assert.same({}, characters:recipeIDs("Hugh Jass"))
			now = 2000
			characters:stampProfessions("Hugh Jass")
			assert.same({ { skillLine = TAILORING, revision = 2000 } }, characters:professions("Hugh Jass"))
		end)

		it("stamps once a removal of each of the game's skill lines a registered character lacks", function()
			local skillLines = { [TAILORING] = "crafting", [COOKING] = "secondary" }
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass", skillLines)
			now = 2000
			characters:stampProfessions("Hugh Jass", skillLines)
			assert.same({
				{ skillLine = COOKING, revision = 1000 },
				{ skillLine = TAILORING, level = 50, maxLevel = 75, revision = 1000 },
			}, characters:professions("Hugh Jass"))
			characters:stampProfessions("Anna Conda", skillLines)
			assert.same({}, characters:professions("Anna Conda")) -- not registered: shares nothing
		end)

		it("forgets a profession dropped before any sync stamped it", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeProfessions("Hugh Jass", {})
			characters:stampProfessions("Hugh Jass")
			assert.same({}, characters:professions("Hugh Jass"))
		end)

		it("shares a profession learned again after its removal, with a later revision", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", {})
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 1, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			assert.same(
				{ { skillLine = TAILORING, level = 1, maxLevel = 75, revision = 1002 } },
				characters:professions("Hugh Jass")
			)
		end)

		it("withdraws every profession of a character that unregisters, with a new revision at the stamp", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:unregister("Hugh Jass")
			assert.same({ { skillLine = TAILORING, revision = 1000 } }, characters:professions("Hugh Jass"))
			characters:stampProfessions("Hugh Jass")
			assert.same({ { skillLine = TAILORING, revision = 1001 } }, characters:professions("Hugh Jass"))
		end)

		it("withdraws every profession of a character kept anonymous", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:keepAnonymous("Hugh Jass")
			characters:stampProfessions("Hugh Jass")
			assert.same({ { skillLine = TAILORING, revision = 1001 } }, characters:professions("Hugh Jass"))
		end)

		it(
			"withdraws every profession when sharing professions is turned off, and shares them again when on",
			function()
				characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
				characters:stampProfessions("Hugh Jass")
				settings.shareProfessions = false
				characters:stampProfessions("Hugh Jass")
				assert.same({ { skillLine = TAILORING, revision = 1001 } }, characters:professions("Hugh Jass"))
				settings.shareProfessions = true
				characters:stampProfessions("Hugh Jass")
				assert.same(
					{ { skillLine = TAILORING, level = 50, maxLevel = 75, revision = 1002 } },
					characters:professions("Hugh Jass")
				)
			end
		)

		it("never shares the professions of a character not registered", function()
			characters:seeProfessions("Anna Conda", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Anna Conda")
			assert.same({}, characters:professions("Anna Conda"))
		end)

		it("keeps a character whose professions were read but who was not asked yet not asked", function()
			characters:seeProfessions("Anna Conda", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			assert.equal("notAsked", characters:state("Anna Conda"))
			assert.is_nil(characters:registration("Anna Conda"))
			assert.same({ nickname = "Tony" }, characters:prompt("Anna Conda"))
		end)

		it("keeps the professions when the registration changes", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:register("Hugh Jass", "Antoine")
			assert.equal(50, characters:professions("Hugh Jass")[1].level)
		end)

		it("gives copies, which changing leaves its professions as they are", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeRecipes("Hugh Jass", TAILORING, { 10 }, { 10 })
			characters:stampProfessions("Hugh Jass")
			characters:professions("Hugh Jass")[1].recipes[1] = 99
			characters:recipeIDs("Hugh Jass")[TAILORING][1] = 99
			assert.same({ 10 }, characters:professions("Hugh Jass")[1].recipes)
			assert.same({ [TAILORING] = { 10 } }, characters:recipeIDs("Hugh Jass"))
		end)

		it("gives the professions as read now, unstamped, sorted by skill line, whatever is shared", function()
			settings.shareProfessions = false
			characters:seeProfessions("Hugh Jass", {
				{ skillLine = TAILORING, level = 50, maxLevel = 75 },
				{ skillLine = COOKING, level = 1, maxLevel = 75 },
			})
			characters:seeRecipes("Hugh Jass", TAILORING, { 30, 10, 20 }, { 30, 10 })
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", {
				{ skillLine = TAILORING, level = 60, maxLevel = 75 },
				{ skillLine = COOKING, level = 1, maxLevel = 75 },
			})
			assert.same({
				{ skillLine = COOKING, level = 1, maxLevel = 75 },
				{ skillLine = TAILORING, level = 60, maxLevel = 75, recipes = { 10, 30 } },
			}, characters:currentProfessions("Hugh Jass"))
		end)

		it("leaves a dropped profession out of the professions read now", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			characters:seeProfessions("Hugh Jass", {})
			assert.same({}, characters:currentProfessions("Hugh Jass"))
		end)

		it("lists every character with a profession read, registered or not, sorted by name", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:seeProfessions("Dee Zaster", { { skillLine = COOKING, level = 1, maxLevel = 75 } })
			characters:seeProfessions("Cole Slaw", {})
			characters:register("Anna Conda", "Anna")
			assert.same({ "Dee Zaster", "Hugh Jass" }, characters:withProfessions())
		end)

		it("says whether reading the professions or the recipes changed anything", function()
			local tailoring = { { skillLine = TAILORING, level = 50, maxLevel = 75 } }
			assert.is_true(characters:seeProfessions("Hugh Jass", tailoring))
			assert.is_false(characters:seeProfessions("Hugh Jass", tailoring))
			assert.is_true(
				characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 51, maxLevel = 75 } })
			)
			assert.is_true(characters:seeRecipes("Hugh Jass", TAILORING, { 10, 20 }, { 10 }))
			assert.is_false(characters:seeRecipes("Hugh Jass", TAILORING, { 20, 10 }, { 10 }))
			assert.is_true(characters:seeRecipes("Hugh Jass", TAILORING, { 10, 20 }, { 10, 20 }))
			assert.is_false(characters:seeRecipes("Hugh Jass", COOKING, { 1 }, { 1 }))
			assert.is_true(characters:seeProfessions("Hugh Jass", {}))
		end)

		it("keeps professions in its saved table", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			characters:stampProfessions("Hugh Jass")
			assert.equal(50, Self.new(saved, clock, settings):professions("Hugh Jass")[1].level)
		end)

		it("loads a saved character from before professions", function()
			local old = { ["Hugh Jass"] = { nickname = "Tony", revision = 900 } }
			local loaded = Self.new(old, clock, {})
			assert.same({}, loaded:professions("Hugh Jass"))
			loaded:seeProfessions("Hugh Jass", { { skillLine = TAILORING, level = 50, maxLevel = 75 } })
			loaded:stampProfessions("Hugh Jass")
			assert.equal(50, loaded:professions("Hugh Jass")[1].level)
		end)
	end)

	describe("progress", function()
		local ONYXIA, DIRE_MAUL, STRATHOLME = 1, 4, 7
		local done = { state = "done", item = 18249 }

		before_each(function()
			characters:register("Hugh Jass", "Tony")
		end)

		it("shares no milestone before a sync stamps it", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			assert.same({}, characters:progress("Hugh Jass"))
		end)

		it("gives each milestone a revision at the server's time when a sync stamps it, sorted by ID", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done, [ONYXIA] = { state = "progress", quest = 6403 } })
			characters:stampProgress("Hugh Jass")
			assert.same({
				{ milestone = ONYXIA, state = "progress", quest = 6403, revision = 1000 },
				{ milestone = DIRE_MAUL, state = "done", item = 18249, revision = 1000 },
			}, characters:progress("Hugh Jass"))
		end)

		it("gives a milestone a new revision only when its cell changed since its last one", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			now = 2000
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = { state = "done", item = 18249 } })
			characters:stampProgress("Hugh Jass")
			assert.equal(1000, characters:progress("Hugh Jass")[1].revision)
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = { state = "progress" } })
			characters:stampProgress("Hugh Jass")
			assert.same(
				{ { milestone = DIRE_MAUL, state = "progress", revision = 2000 } },
				characters:progress("Hugh Jass")
			)
		end)

		it("turns a milestone the character no longer has into a removal at the next stamp", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			characters:seeProgress("Hugh Jass", {})
			now = 2000
			characters:stampProgress("Hugh Jass")
			assert.same({ { milestone = DIRE_MAUL, revision = 2000 } }, characters:progress("Hugh Jass"))
		end)

		it("stamps once a removal of each tracked milestone a registered character lacks", function()
			local ids = { [DIRE_MAUL] = true, [STRATHOLME] = true }
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass", ids)
			now = 2000
			characters:stampProgress("Hugh Jass", ids)
			assert.same({
				{ milestone = DIRE_MAUL, state = "done", item = 18249, revision = 1000 },
				{ milestone = STRATHOLME, revision = 1000 },
			}, characters:progress("Hugh Jass"))
			characters:stampProgress("Anna Conda", ids)
			assert.same({}, characters:progress("Anna Conda")) -- not registered: shares nothing
		end)

		it("withdraws every milestone of a character that unregisters or is kept anonymous", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			characters:unregister("Hugh Jass")
			assert.same({ { milestone = DIRE_MAUL, revision = 1000 } }, characters:progress("Hugh Jass"))
			characters:stampProgress("Hugh Jass")
			assert.same({ { milestone = DIRE_MAUL, revision = 1001 } }, characters:progress("Hugh Jass"))
			characters:register("Hugh Jass", "Tony")
			characters:stampProgress("Hugh Jass")
			characters:keepAnonymous("Hugh Jass")
			characters:stampProgress("Hugh Jass")
			assert.same({ { milestone = DIRE_MAUL, revision = 1003 } }, characters:progress("Hugh Jass"))
		end)

		it("withdraws every milestone when sharing progress is turned off, and shares them again when on", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			settings.shareProgress = false
			characters:stampProgress("Hugh Jass")
			assert.same({ { milestone = DIRE_MAUL, revision = 1001 } }, characters:progress("Hugh Jass"))
			settings.shareProgress = true
			characters:stampProgress("Hugh Jass")
			assert.same(
				{ { milestone = DIRE_MAUL, state = "done", item = 18249, revision = 1002 } },
				characters:progress("Hugh Jass")
			)
		end)

		it("shares progress whatever the professions' switch says", function()
			settings.shareProfessions = false
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			assert.equal("done", characters:progress("Hugh Jass")[1].state)
		end)

		it("never shares the progress of a character not registered", function()
			characters:seeProgress("Anna Conda", { [DIRE_MAUL] = done })
			characters:stampProgress("Anna Conda")
			assert.same({}, characters:progress("Anna Conda"))
			assert.equal("notAsked", characters:state("Anna Conda"))
		end)

		it("gives the progress as read now, unstamped, sorted by ID, whatever is shared", function()
			settings.shareProgress = false
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			characters:seeProgress("Hugh Jass", { [STRATHOLME] = { state = "done", item = 12382 }, [DIRE_MAUL] = done })
			assert.same({
				{ milestone = DIRE_MAUL, state = "done", item = 18249 },
				{ milestone = STRATHOLME, state = "done", item = 12382 },
			}, characters:currentProgress("Hugh Jass"))
		end)

		it("lists every character with a milestone read, registered or not, sorted by name", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:seeProgress("Dee Zaster", { [STRATHOLME] = { state = "done", item = 12382 } })
			characters:seeProgress("Cole Slaw", {})
			assert.same({ "Dee Zaster", "Hugh Jass" }, characters:withProgress())
		end)

		it("lists every one of this account's characters, with progress or none, sorted by name", function()
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:seeProgress("Cole Slaw", {})
			characters:keepAnonymous("Anna Conda")
			assert.same({ "Anna Conda", "Cole Slaw", "Hugh Jass" }, characters:names())
		end)

		it("says whether reading the progress changed anything", function()
			assert.is_true(characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done }))
			assert.is_false(characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = { state = "done", item = 18249 } }))
			assert.is_true(characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = { state = "progress" } }))
			assert.is_true(characters:seeProgress("Hugh Jass", {}))
			assert.is_false(characters:seeProgress("Hugh Jass", {}))
		end)

		it("keeps progress in its saved table, apart from the professions", function()
			characters:seeProfessions("Hugh Jass", { { skillLine = 197, level = 50, maxLevel = 75 } })
			characters:seeProgress("Hugh Jass", { [DIRE_MAUL] = done })
			characters:stampProgress("Hugh Jass")
			local loaded = Self.new(saved, clock, settings)
			assert.equal("done", loaded:progress("Hugh Jass")[1].state)
			assert.equal(50, loaded:currentProfessions("Hugh Jass")[1].level)
		end)
	end)
end)
