local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Copies", "Professions", "Catalog")
local Catalog = ns.Catalog

local TAILORING, ALCHEMY, COOKING, FIRST_AID, MINING, HERBALISM = 197, 171, 185, 129, 186, 182

-- What the game would name them, looked up when shown.
local PROFESSION_NAMES = {
	[TAILORING] = "Tailoring",
	[ALCHEMY] = "Alchemy",
	[COOKING] = "Cooking",
	[FIRST_AID] = "First Aid",
	[MINING] = "Mining",
	[HERBALISM] = "Herbalism",
}
local RECIPE_NAMES = { [10] = "Linen Cloak", [11] = "Brown Linen Vest", [12] = "Élan Robe", [20] = "Spiced Bread" }
local NICKNAMES = { ["Hugh Jass"] = "Tony", ["Anna Conda"] = "~Zoé" }

local lookups = {
	profession = function(skillLine)
		return PROFESSION_NAMES[skillLine]
	end,
	recipe = function(id)
		return RECIPE_NAMES[id]
	end,
	nickname = function(name)
		return NICKNAMES[name]
	end,
}

-- Professions:list() entries, sorted by name then skill line.
local function entries()
	return {
		{
			name = "Anna Conda",
			skillLine = TAILORING,
			level = 150,
			maxLevel = 300,
			recipes = { 10, 12 },
			firstHand = false,
			source = "Hugh Jass",
		},
		{ name = "Hugh Jass", skillLine = COOKING, level = 40, maxLevel = 75, recipes = { 20 }, firstHand = true },
		{
			name = "Hugh Jass",
			skillLine = TAILORING,
			level = 75,
			maxLevel = 150,
			recipes = { 10, 11 },
			firstHand = true,
		},
		{ name = "Mip Wiq", skillLine = ALCHEMY, level = 1, maxLevel = 75 },
		{ name = "Mip Wiq", skillLine = TAILORING, disputed = true },
		{ name = "Sal Monella", skillLine = TAILORING, level = 300, maxLevel = 300, recipes = { 11 }, own = true },
	}
end

local function names(rows)
	local found = {}
	for i, row in ipairs(rows) do
		found[i] = row.name
	end
	return found
end

describe("Catalog", function()
	describe("professions", function()
		it("lists the primary professions by name, then the secondary ones", function()
			local catalog = Catalog.new(entries(), true, lookups)
			assert.same({ "Alchemy", "Tailoring", "Cooking" }, names(catalog:professions()))
			assert.same({ false, false, true }, {
				catalog:professions()[1].secondary,
				catalog:professions()[2].secondary,
				catalog:professions()[3].secondary,
			})
		end)

		it("counts each profession's distinct recipes and its characters, leaving out disputed ones", function()
			local tailoring = Catalog.new(entries(), true, lookups):professions()[2]
			assert.same({
				skillLine = TAILORING,
				name = "Tailoring",
				secondary = false,
				gathering = false,
				recipes = 3,
				characters = 3,
			}, tailoring)
		end)

		it("counts a profession whose window was never opened, with no recipe", function()
			local alchemy = Catalog.new(entries(), true, lookups):professions()[1]
			assert.equal(0, alchemy.recipes)
			assert.equal(1, alchemy.characters)
		end)

		it("leaves out second-hand professions while second-hand is off, but never your own", function()
			local tailoring = Catalog.new(entries(), false, lookups):professions()[2]
			assert.equal(2, tailoring.characters)
			assert.equal(2, tailoring.recipes)
		end)

		it("names a profession the game cannot name by its skill line", function()
			local catalog = Catalog.new({ { name = "Hugh Jass", skillLine = 999, level = 1, maxLevel = 75 } }, true, {
				profession = function() end,
			})
			assert.equal("999", catalog:professions()[1].name)
		end)

		it("lists every known profession, with no character and no recipe when nobody has it", function()
			local catalog = Catalog.new(entries(), true, lookups, { [TAILORING] = true, [FIRST_AID] = true })
			local professions = catalog:professions()
			assert.same({ "Alchemy", "Tailoring", "Cooking", "First Aid" }, names(professions))
			assert.same({
				skillLine = FIRST_AID,
				name = "First Aid",
				secondary = true,
				gathering = false,
				recipes = 0,
				characters = 0,
			}, professions[4])
			assert.equal(3, professions[2].characters)
		end)

		it("gives a known profession nobody has empty recipe and character lists", function()
			local catalog = Catalog.new({}, true, lookups, { [FIRST_AID] = true })
			assert.same({ "First Aid" }, names(catalog:professions()))
			assert.same({}, catalog:recipes(FIRST_AID, ""))
			assert.same({}, catalog:characters(FIRST_AID, "", {}))
		end)

		it("lists the gathering professions after the crafting ones, before the secondary ones", function()
			local catalog = Catalog.new(
				{ { name = "Hugh Jass", skillLine = MINING, level = 1, maxLevel = 75 } },
				true,
				lookups,
				{ [HERBALISM] = true, [TAILORING] = true, [ALCHEMY] = true, [COOKING] = true }
			)
			local professions = catalog:professions()
			assert.same({ "Alchemy", "Tailoring", "Herbalism", "Mining", "Cooking" }, names(professions))
			assert.same({ false, false, true, true, false }, {
				professions[1].gathering,
				professions[2].gathering,
				professions[3].gathering,
				professions[4].gathering,
				professions[5].gathering,
			})
		end)

		it("splits primary and secondary professions by skill line", function()
			assert.is_true(Catalog.isSecondary(COOKING))
			assert.is_true(Catalog.isSecondary(FIRST_AID))
			assert.is_true(Catalog.isSecondary(356)) -- Fishing
			assert.is_false(Catalog.isSecondary(TAILORING))
		end)
	end)

	describe("recipes", function()
		it("lists a profession's recipes by name, each with how many characters know it", function()
			local recipes = Catalog.new(entries(), true, lookups):recipes(TAILORING, "")
			assert.same({
				{ recipe = 11, name = "Brown Linen Vest", characters = 2 },
				{ recipe = 12, name = "Élan Robe", characters = 1 },
				{ recipe = 10, name = "Linen Cloak", characters = 2 },
			}, recipes)
		end)

		it("finds recipes by name, ignoring case and accents", function()
			local recipes = Catalog.new(entries(), true, lookups):recipes(TAILORING, "ELAN")
			assert.same({ "Élan Robe" }, names(recipes))
		end)

		it("leaves out what only second-hand professions know while second-hand is off", function()
			assert.same(
				{ "Brown Linen Vest", "Linen Cloak" },
				names(Catalog.new(entries(), false, lookups):recipes(TAILORING, ""))
			)
		end)

		it("names a recipe the game cannot name by its ID", function()
			local catalog = Catalog.new(
				{ { name = "Hugh Jass", skillLine = TAILORING, level = 1, maxLevel = 75, recipes = { 7 } } },
				true,
				lookups
			)
			assert.equal("7", catalog:recipes(TAILORING, "")[1].name)
		end)
	end)

	describe("knowers", function()
		it("lists who knows a recipe, online first, then by skill level", function()
			local knowers = Catalog.new(entries(), true, lookups):knowers(TAILORING, 10, { ["Anna Conda"] = true })
			assert.same({ "Anna Conda", "Hugh Jass" }, names(knowers))
			assert.same({
				name = "Anna Conda",
				nickname = "~Zoé",
				level = 150,
				maxLevel = 300,
				source = "Hugh Jass",
				online = true,
			}, knowers[1])
			assert.is_false(knowers[2].online)
		end)

		it("marks your own characters as yours", function()
			local knowers = Catalog.new(entries(), true, lookups):knowers(TAILORING, 11, {})
			assert.same({ "Sal Monella", "Hugh Jass" }, names(knowers))
			assert.is_true(knowers[1].own)
		end)

		it("lists a character whose identity does not show by its name alone", function()
			local knowers = Catalog.new(entries(), true, lookups):knowers(TAILORING, 11, {})
			assert.is_nil(knowers[1].nickname)
		end)
	end)

	describe("characters", function()
		it("lists a profession's characters by skill level, leaving out disputed ones", function()
			local characters = Catalog.new(entries(), true, lookups):characters(TAILORING, "", {})
			assert.same({ "Sal Monella", "Anna Conda", "Hugh Jass" }, names(characters))
		end)

		it("finds characters by name or nickname, ignoring case and accents", function()
			local catalog = Catalog.new(entries(), true, lookups)
			assert.same({ "Anna Conda" }, names(catalog:characters(TAILORING, "zoe", {})))
			assert.same({ "Sal Monella" }, names(catalog:characters(TAILORING, "monel", {})))
		end)

		it("leaves out second-hand professions while second-hand is off", function()
			local characters = Catalog.new(entries(), false, lookups):characters(TAILORING, "", {})
			assert.same({ "Sal Monella", "Hugh Jass" }, names(characters))
		end)
	end)
end)
