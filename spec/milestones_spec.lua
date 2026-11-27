local ns = require("spec.helpers.addon")("Milestones")
local Milestones = ns.Milestones

describe("Milestones", function()
	it("gives each milestone a stable ID of its own, a category and a kind", function()
		local seen = {}
		for _, milestone in ipairs(Milestones.LIST) do
			assert.is_nil(seen[milestone.id], "ID " .. tostring(milestone.id) .. " used twice")
			seen[milestone.id] = true
			assert.equal(milestone, Milestones.BY_ID[milestone.id])
			assert.truthy(
				({ attunements = true, entrances = true, summons = true, leveling = true })[milestone.category]
			)
			assert.truthy(({ attunement = true, entrance = true, summon = true })[milestone.kind])
		end
		assert.equal(20, #Milestones.LIST)
	end)

	-- A list as a set, failing on a value listed twice.
	local function set(list)
		local result = {}
		for _, value in ipairs(list) do
			assert.is_nil(result[value], tostring(value) .. " listed twice")
			result[value] = true
		end
		return result
	end

	it("lists every item and quest a milestone tracks, once each, for Client to read", function()
		local items, quests = set(Milestones.ITEMS), set(Milestones.QUESTS)
		for _, item in ipairs({ 16309, 11000, 12344, 12324, 12323, 12219, 12336, 12335, 12337, 22057, 22049, 275989 }) do
			assert.is_true(items[item], "item " .. item)
		end
		for _, quest in ipairs({ 6403, 6501, 6502, 6585, 6601, 6602, 3802, 4742, 4743, 92458, 96984 }) do
			assert.is_true(quests[quest], "quest " .. quest)
		end
		-- Molten Core is a placeholder: its quests are not read yet.
		assert.is_nil(quests[7848])
		assert.is_nil(quests[7487])
	end)

	describe("the cell a character shows", function()
		local ONYXIA, MOLTEN_CORE, BLACKROCK_DEPTHS, UPPER_BLACKROCK_SPIRE = 1, 2, 3, 6
		local THELDREN, MOR_GRAYHOOF, LORD_VALTHALAK = 8, 9, 13
		local AMULET, SHADOWFORGE_KEY, INVOCATION, MOR_GRAYHOOF_BRAZIER = 16309, 11000, 22057, 22049
		local SEAL, UNADORNED, UNFORGED, FORGED = 12344, 12219, 12323, 12324
		local SPIRESTONE, SMOLDERTHORN, BLOODAXE = 12336, 12335, 12337

		-- Each argument a list, made a set as Client hands them over.
		local function cells(held, completed, inLog)
			local function toSet(list)
				local result = {}
				for _, value in ipairs(list or {}) do
					result[value] = true
				end
				return result
			end
			return Milestones.cells(toSet(held), toSet(completed), toSet(inLog))
		end

		it("shows nothing for a character that holds no tracked item and has no tracked quest", function()
			assert.same({}, cells())
		end)

		it("shows a milestone done, with its item, while the character holds the item", function()
			assert.same({ state = "done", item = SHADOWFORGE_KEY }, cells({ SHADOWFORGE_KEY })[BLACKROCK_DEPTHS])
		end)

		it("shows an entrance in progress, with its quest, while the quest is in the log", function()
			assert.same({ state = "progress", quest = 3802 }, cells(nil, nil, { 3802 })[BLACKROCK_DEPTHS])
		end)

		it("shows nothing for an entrance whose quest is completed but whose key is gone", function()
			assert.is_nil(cells(nil, { 3802 })[BLACKROCK_DEPTHS])
		end)

		it("shows a done milestone done even with its quest in the log", function()
			assert.same(
				{ state = "done", item = SHADOWFORGE_KEY },
				cells({ SHADOWFORGE_KEY }, nil, { 3802 })[BLACKROCK_DEPTHS]
			)
		end)

		it("shows Onyxia in progress while a quest of the chain is in the log", function()
			assert.same({ state = "progress", quest = 6501 }, cells(nil, { 6403 }, { 6501 })[ONYXIA])
		end)

		it("shows Onyxia in progress between two quests of the chain, done and not the final one", function()
			assert.same({ state = "progress" }, cells(nil, { 6585, 6601 })[ONYXIA])
		end)

		it("shows nothing for Onyxia once the final quest is completed but the amulet is gone", function()
			assert.is_nil(cells(nil, { 6403, 6501, 6502 })[ONYXIA])
			assert.is_nil(cells(nil, { 6585, 6601, 6602 })[ONYXIA])
		end)

		it("shows Onyxia done while the character holds the Drakefire Amulet", function()
			assert.same({ state = "done", item = AMULET }, cells({ AMULET }, { 6502 })[ONYXIA])
		end)

		it("never shows Molten Core, a placeholder that tracks nothing", function()
			assert.is_nil(cells(Milestones.ITEMS, Milestones.QUESTS, Milestones.QUESTS)[MOLTEN_CORE])
		end)

		it("counts the Brazier of Invocation for each Brazier of Beckoning's boss, not for Theldren", function()
			local shown = cells({ INVOCATION })
			for id = MOR_GRAYHOOF, LORD_VALTHALAK do
				assert.same({ state = "done", item = INVOCATION }, shown[id])
			end
			assert.is_nil(shown[THELDREN])
		end)

		it("shows a boss's own Brazier of Beckoning before the Brazier of Invocation", function()
			local shown = cells({ INVOCATION, MOR_GRAYHOOF_BRAZIER })
			assert.same({ state = "done", item = MOR_GRAYHOOF_BRAZIER }, shown[MOR_GRAYHOOF])
		end)

		describe("Upper Blackrock Spire", function()
			it("is done while the character holds the Seal of Ascension, whatever else it holds", function()
				assert.same(
					{ state = "done", item = SEAL },
					cells({ SEAL, FORGED, SPIRESTONE }, nil, { 4743 })[UPPER_BLACKROCK_SPIRE]
				)
			end)

			it("is in progress with every gem lit while the Forged or Unforged Seal is held", function()
				assert.same({ state = "progress", item = FORGED, gems = 7 }, cells({ FORGED })[UPPER_BLACKROCK_SPIRE])
				assert.same(
					{ state = "progress", item = UNFORGED, gems = 7 },
					cells({ UNFORGED }, nil, { 4743 })[UPPER_BLACKROCK_SPIRE]
				)
			end)

			it("is in progress with the gems held, a bit each", function()
				assert.same({ state = "progress", gems = 1 }, cells({ SPIRESTONE })[UPPER_BLACKROCK_SPIRE])
				assert.same({ state = "progress", gems = 6 }, cells({ SMOLDERTHORN, BLOODAXE })[UPPER_BLACKROCK_SPIRE])
			end)

			it("is in progress with its quest and the gems held while a seal quest is in the log", function()
				assert.same(
					{ state = "progress", quest = 4742, item = UNADORNED, gems = 2 },
					cells({ UNADORNED, SMOLDERTHORN }, nil, { 4742 })[UPPER_BLACKROCK_SPIRE]
				)
				assert.same(
					{ state = "progress", quest = 4743, gems = 0 },
					cells(nil, nil, { 4743 })[UPPER_BLACKROCK_SPIRE]
				)
			end)

			it("is in progress while the Unadorned Seal is held", function()
				assert.same(
					{ state = "progress", item = UNADORNED, gems = 0 },
					cells({ UNADORNED })[UPPER_BLACKROCK_SPIRE]
				)
			end)

			it("shows nothing once the seal quests are completed but the Seal is gone", function()
				assert.is_nil(cells(nil, { 4742, 4743 })[UPPER_BLACKROCK_SPIRE])
			end)
		end)
	end)

	describe("a cell heard from a peer", function()
		local ONYXIA, MOLTEN_CORE, BLACKROCK_DEPTHS, UPPER_BLACKROCK_SPIRE, MOR_GRAYHOOF = 1, 2, 3, 6, 9
		local normalize = Milestones.normalize

		it("keeps a done cell and an in-progress cell as they came", function()
			assert.same({ state = "done", item = 16309 }, normalize(ONYXIA, { state = "done", item = 16309 }))
			assert.same(
				{ state = "progress", quest = 4742, item = 12219, gems = 5 },
				normalize(UPPER_BLACKROCK_SPIRE, { state = "progress", quest = 4742, item = 12219, gems = 5 })
			)
			assert.same({ state = "progress" }, normalize(ONYXIA, { state = "progress" }))
		end)

		it("ignores a milestone it does not know, as a later version's", function()
			assert.is_nil(normalize(999, { state = "done" }))
			assert.is_nil(normalize("1", { state = "done" }))
			assert.is_nil(normalize(nil, { state = "done" }))
		end)

		it("drops a cell for Molten Core, a placeholder", function()
			assert.is_nil(normalize(MOLTEN_CORE, { state = "done" }))
		end)

		it("drops a malformed cell", function()
			assert.is_nil(normalize(ONYXIA, nil))
			assert.is_nil(normalize(ONYXIA, "done"))
			assert.is_nil(normalize(ONYXIA, {}))
			assert.is_nil(normalize(ONYXIA, { state = "maybe" }))
		end)

		it("drops a summon in progress: a summon is done or nothing", function()
			assert.is_nil(normalize(MOR_GRAYHOOF, { state = "progress" }))
		end)

		-- Kept, a trimmed copy would say other than the same revision a later
		-- version holds, which disputes it there.
		it("drops a cell whose item or quest is not the milestone's, whole", function()
			assert.is_nil(normalize(BLACKROCK_DEPTHS, { state = "done", item = 16309 }))
			assert.is_nil(normalize(BLACKROCK_DEPTHS, { state = "done", item = 11000, quest = 3802 }))
			assert.is_nil(normalize(BLACKROCK_DEPTHS, { state = "done", item = "11000" }))
			assert.is_nil(normalize(BLACKROCK_DEPTHS, { state = "progress", quest = 6502 }))
			assert.is_nil(normalize(BLACKROCK_DEPTHS, { state = "progress", item = 11000 }))
			assert.is_nil(normalize(UPPER_BLACKROCK_SPIRE, { state = "progress", item = 12344 }))
		end)

		it("drops a cell whose gems are out of range, or on a milestone without gems, whole", function()
			for _, gems in ipairs({ -1, 8, 1.5, 0 / 0, math.huge, "7" }) do
				assert.is_nil(normalize(UPPER_BLACKROCK_SPIRE, { state = "progress", gems = gems }))
			end
			assert.is_nil(normalize(ONYXIA, { state = "progress", gems = 7 }))
			assert.is_nil(normalize(UPPER_BLACKROCK_SPIRE, { state = "done", item = 12344, gems = 7 }))
		end)

		it("drops fields a cell does not have", function()
			assert.same({ state = "done" }, normalize(BLACKROCK_DEPTHS, { state = "done", nickname = "Tony", [1] = 2 }))
		end)

		it("is a copy: changing what came in leaves it as it was", function()
			local heard = { state = "done", item = 11000 }
			local kept = normalize(BLACKROCK_DEPTHS, heard)
			heard.item = nil
			assert.same({ state = "done", item = 11000 }, kept)
		end)
	end)

	it("tells two cells equal when they show the same", function()
		local equal = Milestones.equal
		assert.is_true(equal(nil, nil))
		assert.is_true(equal({ state = "done", item = 16309 }, { state = "done", item = 16309 }))
		assert.is_true(equal({ state = "progress", gems = 3 }, { state = "progress", gems = 3 }))
		assert.is_false(equal({ state = "done" }, nil))
		assert.is_false(equal(nil, { state = "done" }))
		assert.is_false(equal({ state = "done" }, { state = "progress" }))
		assert.is_false(equal({ state = "done", item = 22049 }, { state = "done", item = 22057 }))
		assert.is_false(equal({ state = "progress", quest = 4742 }, { state = "progress", quest = 4743 }))
		assert.is_false(equal({ state = "progress", gems = 3 }, { state = "progress", gems = 1 }))
	end)
end)
