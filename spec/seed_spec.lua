local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Professions", "Seed")
local Seed = ns.Seed

describe("Seed", function()
	local DAY = 24 * 60 * 60
	local SCHEMA = 1
	local now, account

	-- The account's saved table as 1.4.x left it: its memory (a disputed
	-- identity and a peer's daily count among it), its professions, the
	-- characters it forgot and the strangers it asked.
	local function seed()
		return {
			schema = 1,
			memory = {
				identities = {
					["Anna Conda"] = { nickname = "Ann", revision = 900, heard = 900, guid = "Player-1-0000000A" },
					["Barb Dwyer"] = { nickname = "Barb", revision = 900, heard = 900, disputed = true },
					["Cole Slaw"] = { nickname = "Cole", revision = 900, heard = 900, firstHand = true },
				},
				newFrom = { ["Mallory Knox"] = { since = 900, count = 900 } },
			},
			professions = {
				held = {
					["Anna Conda"] = {
						guid = "Player-1-0000000A",
						skills = { [171] = { revision = 900, level = 10, maxLevel = 75, recipes = { 1, 2 } } },
					},
				},
				seen = { ["Anna Conda"] = 900 },
			},
			forgotten = { ["Dee Zaster"] = true },
			asked = { ["Ella Vator"] = 900 },
			characters = {},
			settings = {},
		}
	end

	local function deepCopy(value)
		if type(value) ~= "table" then
			return value
		end
		local copied = {}
		for key, inner in pairs(value) do
			copied[key] = deepCopy(inner)
		end
		return copied
	end

	before_each(function()
		now = 1800000000
		account = seed()
	end)

	it("copies the seed at a character's first login, without its disputes and daily counts", function()
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		assert.same({ "Ann", "Cole" }, {
			character.memory.identities["Anna Conda"].nickname,
			character.memory.identities["Cole Slaw"].nickname,
		})
		assert.is_nil(character.memory.identities["Barb Dwyer"])
		assert.is_nil(next(character.memory.newFrom or {}))
		assert.equal(10, character.professions.held["Anna Conda"].skills[171].level)
		assert.same({ ["Dee Zaster"] = true }, character.forgotten)
		assert.equal(SCHEMA, character.schema)
	end)

	it("stamps when the seed was first seen, once", function()
		Seed.load(account, {}, now, SCHEMA)
		assert.equal(now, account.seededAt)
		Seed.load(account, {}, now + DAY, SCHEMA)
		assert.equal(now, account.seededAt)
	end)

	it("never writes the seed", function()
		local before = deepCopy(account)
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		character.memory.identities["Anna Conda"].stale = true
		character.professions.held["Anna Conda"].skills[171].recipes[1] = 7
		character.forgotten["Anna Conda"] = true
		before.seededAt = now
		assert.same(before, account)
	end)

	it("copies nothing at a second login", function()
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		character.forgotten["Anna Conda"] = true
		character.memory.identities["Cole Slaw"] = nil
		Seed.load(account, character, now + DAY, SCHEMA)
		assert.is_true(character.forgotten["Anna Conda"])
		assert.is_nil(character.memory.identities["Cole Slaw"])
	end)

	it("copies the seed again to a character whose saved table did not come back", function()
		Seed.load(account, {}, now, SCHEMA)
		local character = {}
		Seed.load(account, character, now + DAY, SCHEMA)
		assert.equal("Ann", character.memory.identities["Anna Conda"].nickname)
	end)

	it("copies what an older version wrote into the seed before the 30 days", function()
		Seed.load(account, {}, now, SCHEMA)
		now = now + 10 * DAY
		account.memory.identities["Hugh Jass"] = { nickname = "Tony", revision = now, heard = now } -- 1.4.x again
		now = now + 2 * DAY
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		assert.equal("Tony", character.memory.identities["Hugh Jass"].nickname)
	end)

	it("drops the seed 30 days after it was first seen, and starts a new character empty", function()
		Seed.load(account, {}, now, SCHEMA)
		Seed.load(account, {}, now + 30 * DAY - 1, SCHEMA)
		assert.is_not_nil(account.memory)
		local character = {}
		Seed.load(account, character, now + 30 * DAY, SCHEMA)
		assert.same({ memory = false, professions = false, forgotten = false, asked = false, seededAt = now }, {
			memory = account.memory ~= nil,
			professions = account.professions ~= nil,
			forgotten = account.forgotten ~= nil,
			asked = account.asked ~= nil,
			seededAt = account.seededAt,
		})
		assert.same({ schema = SCHEMA }, character)
	end)

	it("drops at once what an older version wrote after the seed was dropped", function()
		Seed.load(account, {}, now, SCHEMA)
		now = now + 31 * DAY
		Seed.load(account, {}, now, SCHEMA)
		account.memory = { identities = { ["Hugh Jass"] = { nickname = "Tony", revision = now, heard = now } } }
		now = now + DAY
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		assert.is_nil(account.memory)
		assert.is_nil(character.memory)
	end)

	it("keeps the seed while when it was first seen is ahead of the clock", function()
		account.seededAt = now + 365 * DAY
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		assert.is_not_nil(account.memory)
		assert.equal("Ann", character.memory.identities["Anna Conda"].nickname)
	end)

	it("stamps nothing and copies nothing without a seed", function()
		account = {}
		local character = {}
		Seed.load(account, character, now, SCHEMA)
		assert.same({}, account)
		assert.same({ schema = SCHEMA }, character)
	end)

	it("says whether it copied the seed", function()
		local character = {}
		assert.is_true(Seed.load(account, character, now, SCHEMA))
		assert.is_false(Seed.load(account, character, now, SCHEMA))
		assert.is_false(Seed.load({}, {}, now, SCHEMA))
	end)

	describe("tells a character created since the update", function()
		before_each(function()
			account.characters = {
				["Hugh Jass"] = { nickname = "Tony", revision = 900 }, -- saved by 1.4.x: no GUID
				["Anna Conda"] = { revision = 900, anonymous = true, guid = "Player-1-0000000A" },
			}
		end)

		it("from one the account's characters knew before this login", function()
			assert.is_false(Seed.isNew(account, "Hugh Jass", "Player-1-0000000B"))
			assert.is_false(Seed.isNew(account, "Anna Conda", "Player-1-0000000A"))
			assert.is_false(Seed.isNew(account, "Anna Conda", nil)) -- the game gave no GUID
		end)

		it("as one the account's characters did not know", function()
			assert.is_true(Seed.isNew(account, "Cole Slaw", "Player-1-0000000C"))
			assert.is_true(Seed.isNew({}, "Cole Slaw", "Player-1-0000000C"))
		end)

		it("as one under the name of a character known with another GUID, deleted since", function()
			assert.is_true(Seed.isNew(account, "Anna Conda", "Player-1-0000000C"))
		end)
	end)
end)
