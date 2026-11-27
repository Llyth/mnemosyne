local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Scope", "Professions", "Self", "Seed")
local Memory, Professions, Scope, Seed, Self = ns.Memory, ns.Professions, ns.Scope, ns.Seed, ns.Self

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
		local characters

		before_each(function()
			characters = Self.new({
				["Hugh Jass"] = { nickname = "Tony", revision = 900 }, -- saved by 1.4.x: no GUID
				["Anna Conda"] = { revision = 900, anonymous = true, guid = "Player-1-0000000A" },
			}, function()
				return now
			end, {})
		end)

		it("from one the account's characters knew before this login", function()
			assert.is_false(Seed.isNew(characters, "Hugh Jass", "Player-1-0000000B"))
			assert.is_false(Seed.isNew(characters, "Anna Conda", "Player-1-0000000A"))
			assert.is_false(Seed.isNew(characters, "Anna Conda", nil)) -- the game gave no GUID
		end)

		it("as one the account's characters did not know", function()
			assert.is_true(Seed.isNew(characters, "Cole Slaw", "Player-1-0000000C"))
		end)

		it("as one under the name of a character known with another GUID, deleted since", function()
			assert.is_true(Seed.isNew(characters, "Anna Conda", "Player-1-0000000C"))
		end)

		it("as one under a name another player's character was seen to take", function()
			characters:seeName("Anna Conda", "Player-1-0000000C")
			assert.is_true(Seed.isNew(characters, "Anna Conda", nil))
		end)
	end)

	-- A login as Client runs it: the saved tables loaded (Seed.load), the
	-- character's memory and professions, then the login step once its name is
	-- known. character: its saved table (MnemosyneCharacterDB), {} when it did
	-- not come back. Returns its memory, professions and the account's
	-- characters (Self).
	local function login(character, name, guid)
		local copied = Seed.load(account, character, now, SCHEMA)
		character.memory = character.memory or {}
		character.forgotten = character.forgotten or {}
		character.professions = character.professions or {}
		local function clock()
			return now
		end
		local characters = Self.new(account.characters, clock, account.settings)
		local memory = Memory.new(character.memory, clock, character.forgotten, characters)
		local professions = Professions.new(
			character.professions,
			clock,
			memory,
			characters,
			account.settings,
			Scope.new(account.settings),
			nil,
			function()
				return name
			end
		)
		Seed.login(characters, name, guid, copied, memory, professions)
		return memory, professions, characters
	end

	describe("at login", function()
		it("starts a character created since the update empty, then learns its GUID", function()
			local memory, professions, characters = login({}, "Hugh Jass", "Player-1-0000000H")
			assert.same({ {}, {}, {} }, { memory:search(""), memory:forgotten(), professions:list() })
			assert.equal("Player-1-0000000H", characters:guid("Hugh Jass"))
		end)

		it("starts empty a character under the name of one known with another GUID, deleted since", function()
			account.characters["Hugh Jass"] = { nickname = "Tony", revision = 900, guid = "Player-1-0000000A" }
			local memory = login({}, "Hugh Jass", "Player-1-0000000H")
			assert.same({}, memory:search(""))
		end)

		it("keeps the seed for a character the account knew, then learns its GUID", function()
			account.characters["Hugh Jass"] = { nickname = "Tony", revision = 900 } -- saved by 1.4.x: no GUID
			local memory, professions, characters = login({}, "Hugh Jass", "Player-1-0000000H")
			assert.same({ "Ann", 1 }, { memory:recall("Anna Conda").nickname, #professions:list() })
			assert.equal("Player-1-0000000H", characters:guid("Hugh Jass"))
		end)

		it("starts empty again a character created since the update whose saved table did not come back", function()
			login({}, "Hugh Jass", "Player-1-0000000H")
			now = now + DAY
			local memory, professions = login({}, "Hugh Jass", "Player-1-0000000H")
			assert.same({ {}, {} }, { memory:search(""), professions:list() })
		end)

		it("copies the seed again to a character of 1.4.x whose saved table did not come back", function()
			account.characters["Hugh Jass"] = { nickname = "Tony", revision = 900 }
			login({}, "Hugh Jass", "Player-1-0000000H")
			now = now + DAY
			local memory = login({}, "Hugh Jass", "Player-1-0000000H")
			assert.equal("Ann", memory:recall("Anna Conda").nickname)
		end)

		it("leaves a character that kept its saved table as it was", function()
			local character = {}
			login(character, "Hugh Jass", "Player-1-0000000H")
			now = now + DAY
			local memory = login(character, "Hugh Jass", "Player-1-0000000H")
			memory:hear("Cole Slaw", { nickname = "Cole", revision = 900 })
			now = now + DAY
			assert.equal("Cole", login(character, "Hugh Jass", "Player-1-0000000H"):recall("Cole Slaw").nickname)
		end)
	end)
end)
