local ns = require("spec.helpers.addon")("Protocol", "Memory", "Self", "News")
local Memory, News, Self = ns.Memory, ns.News, ns.Self

describe("News", function()
	local now, delay, memory, characters, settings, news

	local function clock()
		return now
	end

	-- The randomness, as math.random: the delay the test chose, within its bounds.
	local function random(low, high)
		assert.equal(0, low)
		assert.equal(News.MAX_DELAY, high)
		return delay
	end

	-- A sync brings an identity: the memory learns it, then News hears of it,
	-- marked when it made the identity disputed, as Sync passes it.
	local function learn(identity, source)
		local changed, how = memory:hear(identity.name, {
			nickname = identity.nickname,
			revision = identity.revision,
			source = source or "Barb Dwyer",
		})
		assert.is_true(changed)
		news:add({
			name = identity.name,
			nickname = identity.nickname,
			revision = identity.revision,
			disputed = how == "disputed" or nil,
		})
	end

	-- Everything due now, one post at a time, as Client takes them.
	local function allDue()
		local due = {}
		for identity in news.due, news do
			due[#due + 1] = identity
		end
		return due
	end

	local tony = { name = "Hugh Jass", nickname = "Tony", revision = 900 }

	before_each(function()
		now = 1000
		delay = 12
		memory = Memory.new({}, clock)
		characters = Self.new({}, clock)
		settings = { passOn = true }
		news = News.new(clock, random, memory, characters, settings)
	end)

	it("posts an identity a sync brought once, after a random delay of 0 to 30 seconds", function()
		learn(tony)
		now = now + 11
		assert.is_nil(news:due())
		now = now + 1
		assert.same(tony, news:due())
		now = now + 60
		assert.is_nil(news:due())
	end)

	it("posts one at a time, the one due the longest first", function()
		learn(tony)
		delay = 3
		local ann = { name = "Anna Conda", nickname = "Ann", revision = 901 }
		learn(ann)
		now = now + 12
		assert.same({ ann, tony }, allDue())
	end)

	it("posts a removal a sync brought", function()
		local removal = { name = "Anna Conda", revision = 901 }
		learn(removal)
		now = now + News.MAX_DELAY
		assert.same(removal, news:due())
	end)

	it("posts the latest revision when a later sync brings a newer one meanwhile", function()
		learn(tony)
		local later = { name = "Hugh Jass", nickname = "Tone", revision = 950 }
		learn(later)
		now = now + News.MAX_DELAY
		assert.same(later, news:due())
	end)

	it("never posts a dispute a sync brought, a removal included", function()
		memory:hear(tony.name, { nickname = "Tony", revision = 900, source = "Cole Slaw" })
		learn({ name = tony.name, revision = 900 }, "Mallory Knox")
		now = now + News.MAX_DELAY
		assert.is_nil(news:due())
	end)

	it("drops a waiting post once a later sync makes its identity disputed", function()
		learn(tony)
		learn({ name = tony.name, nickname = "Mallory", revision = 900 }, "Mallory Knox")
		now = now + News.MAX_DELAY
		assert.is_nil(news:due())
	end)

	it("cancels its post when a guildmate posts the same identity, or a later one, during the delay", function()
		learn(tony)
		learn({ name = "Anna Conda", nickname = "Ann", revision = 901 })
		news:receive("Cole Slaw", tony)
		news:receive("Cole Slaw", { name = "Anna Conda", nickname = "Annie", revision = 960 })
		now = now + News.MAX_DELAY
		assert.is_nil(news:due())
	end)

	it("still posts when a guildmate's news during the delay is older, or dropped", function()
		learn(tony)
		news:receive("Cole Slaw", { name = "Hugh Jass", nickname = "Hugh", revision = 800 })
		news:receive("Mallory Knox", { name = "Hugh Jass", nickname = "Mallory", revision = now + 2 * 24 * 60 * 60 })
		now = now + News.MAX_DELAY
		assert.same(tony, news:due())
	end)

	it("hears guild news second-hand, with the guildmate as source, and never posts it again", function()
		assert.is_true(news:receive("Cole Slaw", tony))
		local identity = memory:recall(tony.name)
		assert.equal("Tony", identity.nickname)
		assert.is_false(identity.firstHand)
		assert.equal("Cole Slaw", identity.source)
		now = now + News.MAX_DELAY
		assert.is_nil(news:due())
	end)

	it("keeps the second-hand rules for guild news: first-hand wins, an older revision is dropped", function()
		memory:hear(tony.name, { nickname = "Tony", revision = 900 })
		assert.is_false(news:receive("Mallory Knox", { name = tony.name, nickname = "Mallory", revision = 950 }))
		assert.is_true(news:receive("Cole Slaw", { name = "Anna Conda", nickname = "Ann", revision = 901 }))
		assert.is_false(news:receive("Cole Slaw", { name = "Anna Conda", nickname = "Ann", revision = 800 }))
		assert.equal("Tony", memory:recall(tony.name).nickname)
	end)

	it("learns the GUID a guildmate posts with news, which only fills a missing one", function()
		news:receive("Cole Slaw", { name = "Anna Conda", nickname = "Ann", revision = 901, guid = "Player-1-00000001" })
		memory:see("Anna Conda", "Player-1-00000002")
		assert.is_nil(memory:recall("Anna Conda"))
		memory:hear(tony.name, { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
		memory:see(tony.name, "Player-1-00000003")
		assert.is_true(news:receive("Mallory Knox", {
			name = tony.name,
			nickname = "Tony",
			revision = 950,
			guid = "Player-1-00000004",
		}))
		memory:see(tony.name, "Player-1-00000003")
		assert.equal(950, memory:recall(tony.name).revision)
	end)

	it("counts guild news toward a guildmate's changes of the day", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			news:receive("Mallory Knox", { name = "Fake Name" .. i, nickname = "Mallory", revision = 900 })
		end
		assert.is_false(news:receive("Mallory Knox", { name = "Fake Namez", nickname = "Mallory", revision = 900 }))
	end)

	it("never learns what guildmates say about the player's own characters", function()
		characters:register("Anna Conda", "Ann")
		assert.is_false(news:receive("Mallory Knox", { name = "Anna Conda", nickname = "Mallory", revision = 2000 }))
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("posts nothing while the player switched off passing on what they know", function()
		settings.passOn = false
		learn(tony)
		now = now + News.MAX_DELAY
		assert.is_nil(news:due())
	end)

	it("keeps at most 30 posts waiting, so a first sync of a whole memory does not flood the guild", function()
		for i = 1, News.MAX_WAITING + 5 do
			learn({ name = "Some Name" .. i, nickname = "Tony", revision = 900 })
		end
		now = now + News.MAX_DELAY
		assert.equal(News.MAX_WAITING, #allDue())
	end)
end)
