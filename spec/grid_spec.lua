local ns = require("spec.helpers.addon")("Memory", "Milestones", "Grid")
local Grid = ns.Grid

local ONYXIA, MOLTEN_CORE, BRD, UBRS, STRATHOLME, MARAUDON = 1, 2, 3, 6, 7, 16

-- Each character's nickname as it shows, and bare (for sorting).
local NICKNAMES = { ["Hugh Jass"] = { "Tony", "Tony" }, ["Anna Conda"] = { "~Zoé", "Zoé" } }
local function nickname(name)
	local found = NICKNAMES[name]
	if found then
		return found[1], found[2]
	end
end

-- Progress:list() entries, sorted by name then milestone.
local function entries()
	return {
		{ name = "Anna Conda", milestone = BRD, state = "done", item = 11000, firstHand = false, source = "Hugh Jass" },
		{
			name = "Anna Conda",
			milestone = UBRS,
			state = "progress",
			gems = 5,
			firstHand = false,
			source = "Hugh Jass",
		},
		{ name = "Bob Ross", milestone = UBRS, state = "progress", gems = 3, firstHand = true },
		{ name = "Hugh Jass", milestone = ONYXIA, state = "progress", quest = 6403, firstHand = true },
		{ name = "Hugh Jass", milestone = UBRS, state = "done", item = 12344, firstHand = true },
		{ name = "Mip Wiq", milestone = BRD, disputed = true },
		{ name = "Mip Wiq", milestone = MARAUDON, state = "done", item = 17191, firstHand = true },
		{ name = "Sal Monella", milestone = UBRS, state = "progress", item = 12323, gems = 7, own = true },
		{ name = "Zed Zed", milestone = STRATHOLME, state = "done", item = 12382, firstHand = true },
	}
end

local function names(rows)
	local found = {}
	for i, row in ipairs(rows) do
		found[i] = row.name
	end
	return found
end

describe("Grid", function()
	describe("columns", function()
		it("lists a category's milestones in the order shown, placeholders included", function()
			local ids = {}
			for i, milestone in ipairs(Grid.columns("attunements")) do
				ids[i] = milestone.id
			end
			assert.same({ ONYXIA, MOLTEN_CORE }, ids)
		end)
	end)

	describe("rows", function()
		it("lists the characters with progress in a category, by nickname then name", function()
			local grid = Grid.new(entries(), true, nickname)
			-- Zoé and Tony by nickname, the others by name.
			assert.same(
				{ "Bob Ross", "Sal Monella", "Hugh Jass", "Zed Zed", "Anna Conda" },
				names(grid:rows("entrances", ""))
			)
		end)

		it("gives each row its nickname as it shows, whether it is yours, and its cells by milestone", function()
			local row = Grid.new(entries(), true, nickname):rows("entrances", "")[5]
			assert.equal("Anna Conda", row.name)
			assert.equal("~Zoé", row.nickname)
			assert.is_nil(row.own)
			assert.equal("done", row.cells[BRD].state)
			assert.equal(5, row.cells[UBRS].gems)
			assert.is_true(Grid.new(entries(), true, nickname):rows("entrances", "")[2].own)
		end)

		it("leaves out a character with only a disputed cell there, unless everyone shows", function()
			local grid = Grid.new(entries(), true, nickname)
			assert.same({ "Mip Wiq" }, names(grid:rows("leveling", "")))
			local everyone = names(grid:rows("entrances", "", true))
			assert.same({ "Bob Ross", "Mip Wiq", "Sal Monella", "Hugh Jass", "Zed Zed", "Anna Conda" }, everyone)
			assert.is_true(grid:rows("entrances", "", true)[2].cells[BRD].disputed)
		end)

		it("shows everyone heard of in any category when asked", function()
			local rows = Grid.new(entries(), true, nickname):rows("summons", "", true)
			assert.equal(6, #rows)
			assert.same({}, rows[1].cells)
		end)

		it("leaves out second-hand cells while second-hand is off, but never your own", function()
			local grid = Grid.new(entries(), false, nickname)
			assert.same({ "Bob Ross", "Sal Monella", "Hugh Jass", "Zed Zed" }, names(grid:rows("entrances", "")))
		end)

		it("leaves out a disputed cell while second-hand is off, as any second-hand one", function()
			local rows = Grid.new(entries(), false, nickname):rows("entrances", "", true)
			for _, row in ipairs(rows) do
				assert.is_nil(row.cells[BRD] and row.cells[BRD].disputed)
			end
		end)

		it("shows your own characters with no progress, every cell empty, only when everyone shows", function()
			local grid = Grid.new(entries(), true, nickname, { "Ella Vator", "Hugh Jass" })
			assert.is_nil(names(grid:rows("summons", ""))[1])
			local rows = grid:rows("summons", "", true)
			local ella
			for _, row in ipairs(rows) do
				ella = row.name == "Ella Vator" and row or ella
			end
			assert.is_true(ella.own)
			assert.same({}, ella.cells)
		end)

		it("finds characters by name or nickname, ignoring case and accents", function()
			local grid = Grid.new(entries(), true, nickname)
			assert.same({ "Anna Conda" }, names(grid:rows("entrances", "zoe")))
			assert.same({ "Hugh Jass" }, names(grid:rows("entrances", "HUGH")))
		end)

		it("puts done first, then in progress, then the others, when sorted by a milestone", function()
			local grid = Grid.new(entries(), true, nickname)
			assert.same(
				{ "Anna Conda", "Bob Ross", "Sal Monella", "Hugh Jass", "Zed Zed" },
				names(grid:rows("entrances", "", false, BRD))
			)
		end)

		it("sorts Upper Blackrock Spire by the gems lacking, then which", function()
			local grid = Grid.new(entries(), true, nickname)
			-- Tony done; Sal Monella's seal lacks none; Bob Ross lacks Bloodaxe (4),
			-- Zoé Smolderthorn (2): one each, Smolderthorn first; Zed Zed lacks all.
			assert.same(
				{ "Hugh Jass", "Sal Monella", "Anna Conda", "Bob Ross", "Zed Zed" },
				names(grid:rows("entrances", "", false, UBRS))
			)
		end)
	end)

	describe("gems", function()
		it("tells which gems a cell holds", function()
			assert.same({ true, false, true }, Grid.gems({ state = "progress", gems = 5 }))
			assert.same({ true, true, true }, Grid.gems({ state = "progress", item = 12323, gems = 7 }))
			assert.same({ false, false, false }, Grid.gems({ state = "progress", quest = 4742 }))
			assert.same({ false, false, false }, Grid.gems(nil))
		end)

		it("lists the rows lacking a gem, leaving out those with the Seal", function()
			local rows = Grid.new(entries(), true, nickname):rows("entrances", "")
			assert.same({ "Bob Ross", "Zed Zed" }, names(Grid.lacking(rows, UBRS, 3)))
			assert.same({ "Zed Zed", "Anna Conda" }, names(Grid.lacking(rows, UBRS, 2)))
		end)
	end)
end)
