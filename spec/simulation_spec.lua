-- The multi-peer simulation (docs/agents/testing.md): several peers, each with
-- its own Memory, Self, Sync, News and Protocol reader, wired through an
-- in-memory transport that carries wire text, chunks included, the way Client
-- would.
local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Self", "Professions", "Sync", "News")
local Memory, News, Professions, Protocol, Self, Sync =
	ns.Memory, ns.News, ns.Professions, ns.Protocol, ns.Self, ns.Sync

describe("Several peers", function()
	local HOUR, DAY = 60 * 60, 24 * 60 * 60
	local now, peers, inFlight

	local function clock()
		return now
	end

	before_each(function()
		now = 1731500000
		peers = {}
		inFlight = {}
	end)

	local SYNC_KINDS = { digest = true, identities = true, done = true, professionDigest = true, professions = true }

	local function post(from, outgoing)
		for _, out in ipairs(outgoing) do
			for _, text in ipairs(peers[from].writer:split(out.text)) do
				inFlight[#inFlight + 1] = { from = from, to = out.peer, text = text }
			end
		end
	end

	-- Delivers every message in flight, and what the peers send back, until
	-- nothing is left.
	local function run()
		while inFlight[1] do
			local wire = table.remove(inFlight, 1)
			local peer = peers[wire.to]
			local message = peer.reader:read(wire.from, wire.text)
			if message and SYNC_KINDS[message.kind] then
				local outgoing, learned = peer.sync:receive(wire.from, message)
				post(wire.to, outgoing)
				for _, identity in ipairs(learned or {}) do
					peer.news:add(identity)
				end
			elseif message and message.kind == "news" then
				peer.news:receive(wire.from, message.identity)
			elseif message then
				peer.memory:hear(wire.from, { nickname = message.nickname, revision = message.revision })
			end
		end
	end

	local function newPeer(name)
		local memory = Memory.new({}, clock)
		local characters = Self.new({}, clock, {})
		local professions = Professions.new({}, clock, memory, characters, { passOn = true })
		local peer = {
			name = name,
			memory = memory,
			characters = characters,
			professions = professions,
			sync = Sync.new({}, clock, memory, { passOn = true }, professions),
			reader = Protocol.newReader(clock),
			writer = Protocol.newWriter(),
			delay = 0, -- what its randomness draws for each news delay
		}
		peer.news = News.new(clock, function()
			return peer.delay
		end, memory, { passOn = true })
		peers[name] = peer
		return peer
	end

	-- A character tells others who plays it, as its announcement would.
	local function announce(peer, ...)
		local message = peer.characters:message(peer.name, "announce")
		for _, other in ipairs({ ... }) do
			post(peer.name, { { peer = other.name, text = Protocol.write(message) } })
		end
		run()
	end

	local function sync(peer, other)
		post(peer.name, (peer.sync:request(other.name, now)))
		run()
	end

	local a, b, c, d

	before_each(function()
		a = newPeer("Anna Conda")
		b = newPeer("Barb Dwyer")
		c = newPeer("Cole Slaw")
		d = newPeer("Dee Zaster")
		a.characters:register(a.name, "Tony")
	end)

	it("lets D learn A through B and C, second-hand, with its source", function()
		announce(a, b)
		sync(b, c)
		sync(c, d)
		local identity = d.memory:recall(a.name)
		assert.equal("Tony", identity.nickname)
		assert.is_false(identity.firstHand)
		assert.equal(c.name, identity.source)
		assert.equal(b.name, c.memory:recall(a.name).source)
	end)

	it("syncs both ways: each peer learns what the other knew", function()
		announce(a, b)
		local e = newPeer("Ella Vator")
		e.characters:register(e.name, "Ella")
		announce(e, c)
		sync(b, c)
		assert.equal("Ella", b.memory:recall(e.name).nickname)
		assert.equal("Tony", c.memory:recall(a.name).nickname)
	end)

	it("lets a first-hand identity override a forged copy", function()
		local mallory = newPeer("Mallory Knox")
		mallory.memory:hear(a.name, { nickname = "Mallory", revision = now + 1000 })
		sync(mallory, d)
		assert.equal("Mallory", d.memory:recall(a.name).nickname)
		announce(a, d)
		assert.same({ nickname = "Tony", revision = now, firstHand = true, heard = now }, d.memory:recall(a.name))
		local eve = newPeer("Eve Ill")
		eve.memory:hear(a.name, { nickname = "Eve", revision = now + 1000 })
		sync(eve, d)
		assert.equal("Tony", d.memory:recall(a.name).nickname)
	end)

	it("carries an unregistration to everyone who knew the identity", function()
		announce(a, b)
		sync(b, c)
		sync(c, d)
		now = now + 1
		a.characters:unregister(a.name)
		announce(a, b)
		now = now + 6 * HOUR
		sync(b, c)
		sync(c, d)
		for _, peer in ipairs({ b, c, d }) do
			assert.is_nil(peer.memory:recall(a.name), peer.name)
		end
	end)

	it("carries a character kept anonymous to everyone who knew its identity", function()
		announce(a, b)
		sync(b, c)
		now = now + 1
		a.characters:keepAnonymous(a.name)
		announce(a, b)
		now = now + 6 * HOUR
		sync(b, c)
		for _, peer in ipairs({ b, c }) do
			assert.is_nil(peer.memory:recall(a.name), peer.name)
		end
	end)

	it("hides an identity peers dispute, until the character settles it", function()
		local mallory = newPeer("Mallory Knox")
		announce(a, b)
		mallory.memory:hear(a.name, { nickname = "Mallory", revision = a.characters:registration(a.name).revision })
		sync(b, d)
		sync(mallory, d)
		assert.is_nil(d.memory:recall(a.name))
		announce(a, d)
		assert.equal("Tony", d.memory:recall(a.name).nickname)
	end)

	it("hides a reused name's old identity until the character that took the name speaks first-hand", function()
		announce(a, b)
		b.memory:see(a.name, "Player-1-00000001") -- B saw Anna Conda in chat
		sync(b, d)
		-- Anna Conda is deleted; another player takes the name, and D sees the new character in chat.
		d.memory:see(a.name, "Player-1-00000002")
		assert.is_nil(d.memory:recall(a.name))
		assert.is_false(d.memory:knows(a.name))
		now = now + 6 * HOUR
		sync(b, d)
		assert.is_nil(d.memory:recall(a.name))
		local taken = newPeer(a.name)
		now = now + 1
		taken.characters:register(a.name, "Zed")
		announce(taken, d)
		assert.equal("Zed", d.memory:recall(a.name).nickname)
		d.memory:see(a.name, "Player-1-00000002")
		assert.equal("Zed", d.memory:recall(a.name).nickname)
	end)

	-- Lets the time pass, a second at a time: each guildmate posts its news due
	-- to the others, who hear it at once. Returns how many posts went out.
	local function guildWaits(guild, seconds)
		local posts = 0
		for _ = 0, seconds do
			for _, peer in ipairs(guild) do
				-- One post a second at most, as Client takes them.
				local identity = peer.news:due()
				if identity then
					posts = posts + 1
					local text = Protocol.write({ kind = "news", identity = identity })
					for _, other in ipairs(guild) do
						if other ~= peer then
							post(peer.name, { { peer = other.name, text = text } })
						end
					end
				end
			end
			run()
			now = now + 1
		end
		return posts
	end

	it("lets a whole guild hear a change once, from the first guildmate whose delay ends", function()
		local e = newPeer("Ella Vator")
		local guild = { b, c, d, e }
		local stranger = newPeer("Xavier Ray")
		announce(a, stranger)
		b.delay, c.delay = 20, 5
		sync(b, stranger)
		sync(c, stranger)
		assert.equal(1, guildWaits(guild, News.MAX_DELAY))
		for _, peer in ipairs({ d, e }) do
			local identity = peer.memory:recall(a.name)
			assert.equal("Tony", identity.nickname, peer.name)
			assert.equal(c.name, identity.source, peer.name)
		end
		assert.equal(stranger.name, b.memory:recall(a.name).source)
		assert.equal(0, guildWaits(guild, News.MAX_DELAY))
	end)

	it("lets a guild hear an unregistration a sync brought", function()
		local guild = { b, c, d }
		local revision = a.characters:registration(a.name).revision
		for _, peer in ipairs(guild) do
			peer.memory:hear(a.name, { nickname = "Tony", revision = revision, source = "Zed Ex" })
		end
		local stranger = newPeer("Xavier Ray")
		now = now + 1
		a.characters:unregister(a.name)
		announce(a, stranger)
		sync(b, stranger)
		assert.equal(1, guildWaits(guild, News.MAX_DELAY))
		assert.is_nil(c.memory:recall(a.name))
		assert.is_nil(d.memory:recall(a.name))
	end)

	it("takes at most 1,000 new identities a day from one peer", function()
		local mallory = newPeer("Mallory Knox")
		for i = 1, 1500 do
			mallory.memory:hear("Fake Name" .. i, { nickname = "Mallory", revision = 900 })
		end
		sync(mallory, d)
		assert.equal(Memory.MAX_CHANGES_PER_PEER, d.memory:count())
		now = now + DAY
		sync(mallory, d)
		assert.is_true(d.memory:count() > Memory.MAX_CHANGES_PER_PEER)
	end)

	it("lets one peer forge at most 1,000 identities a day, 5,000 more vouched, even held ones", function()
		local mallory = newPeer("Mallory Knox")
		for i = 1, Memory.MAX_VOUCHED_PER_PEER + Memory.MAX_CHANGES_PER_PEER + 500 do
			d.memory:hear("Real Name" .. i, { nickname = "Tony", revision = 900, source = "Peer" .. (i % 2) })
			mallory.memory:hear("Real Name" .. i, { nickname = "Mallory", revision = now - 1 })
		end
		sync(mallory, d)
		local forged = 0
		for _, identity in ipairs(d.memory:search("Mallory")) do
			forged = forged + (identity.source == mallory.name and 1 or 0)
		end
		assert.equal(Memory.MAX_VOUCHED_PER_PEER + Memory.MAX_CHANGES_PER_PEER, forged)
	end)

	it("passes on nothing from a peer that switched it off, but still learns", function()
		announce(a, b)
		local e = newPeer("Ella Vator")
		e.characters:register(e.name, "Ella")
		announce(e, c)
		b.sync = Sync.new({}, clock, b.memory, { passOn = false })
		sync(b, c)
		assert.is_nil(c.memory:recall(a.name))
		assert.equal("Ella", b.memory:recall(e.name).nickname)
	end)

	it("keeps a forgotten character out of one peer's memory, until it speaks first-hand or is unforgotten", function()
		announce(a, b)
		sync(b, d)
		d.memory:forget(a.name)
		now = now + 6 * HOUR
		sync(b, d)
		assert.is_nil(d.memory:recall(a.name))
		assert.equal("Tony", b.memory:recall(a.name).nickname)
		d.memory:unforget(a.name)
		now = now + 6 * HOUR
		sync(b, d)
		assert.equal(b.name, d.memory:recall(a.name).source)
		d.memory:forget(a.name)
		announce(a, d)
		assert.is_true(d.memory:recall(a.name).firstHand)
	end)

	describe("sharing professions", function()
		local ALCHEMY = 171
		local mallory

		-- Every peer given is on every one's guild roster.
		local function guild(...)
			local roster = {}
			for _, peer in ipairs({ ... }) do
				roster[#roster + 1] = peer.name
			end
			for _, peer in ipairs({ ... }) do
				peer.professions:seeLists({}, roster)
			end
		end

		local function shown(peer)
			return peer.professions:list()[1]
		end

		before_each(function()
			mallory = newPeer("Mallory Knox")
			guild(a, b, c, d, mallory)
			a.characters:seeProfessions(a.name, { { skillLine = ALCHEMY, level = 50, maxLevel = 75 } })
			a.characters:seeRecipes(a.name, ALCHEMY, { 2329, 2330 }, { 2329 })
		end)

		it("lets C learn A's profession through B, second-hand, with its source", function()
			sync(a, b)
			assert.is_true(shown(b).firstHand)
			sync(b, c)
			local profession = shown(c)
			assert.equal(a.name, profession.name)
			assert.same({ 2329 }, profession.recipes)
			assert.is_false(profession.firstHand)
			assert.equal(b.name, profession.source)
		end)

		it("lets a first-hand profession override a forged copy", function()
			mallory.professions:hear(
				"Zed Ex",
				{ name = a.name, skillLine = ALCHEMY, revision = now + 1000, level = 1, maxLevel = 75 }
			)
			sync(mallory, d)
			assert.equal(1, shown(d).level)
			sync(a, d)
			assert.equal(50, shown(d).level)
			local eve = newPeer("Eve Ill")
			guild(a, b, c, d, mallory, eve)
			eve.professions:hear(
				"Zed Ex",
				{ name = a.name, skillLine = ALCHEMY, revision = now + 2000, level = 2, maxLevel = 75 }
			)
			sync(eve, d)
			assert.equal(50, shown(d).level)
		end)

		it("lets a character's first-hand share drop a profession forged for it that it never had", function()
			local FISHING = 356
			mallory.professions:hear(
				"Zed Ex",
				{ name = a.name, skillLine = FISHING, revision = now + 1000, level = 300, maxLevel = 300 }
			)
			sync(mallory, d)
			assert.equal(FISHING, shown(d).skillLine)
			sync(a, d)
			local list = d.professions:list()
			assert.equal(1, #list)
			assert.equal(ALCHEMY, list[1].skillLine)
			sync(mallory, d)
			assert.equal(1, #d.professions:list())
		end)

		it("carries a dropped profession's removal to everyone who knew it", function()
			sync(a, b)
			sync(b, c)
			now = now + 6 * HOUR
			a.characters:seeProfessions(a.name, {}) -- dropped
			sync(a, b)
			sync(b, c)
			assert.is_nil(shown(b))
			assert.is_nil(shown(c))
		end)

		it("hides a profession peers dispute, until the character settles it", function()
			sync(a, b)
			local revision = shown(b).revision
			mallory.professions:hear(
				"Zed Ex",
				{ name = a.name, skillLine = ALCHEMY, revision = revision, level = 1, maxLevel = 75 }
			)
			sync(b, d)
			sync(mallory, d)
			assert.is_true(shown(d).disputed)
			sync(a, d)
			assert.equal(50, shown(d).level)
		end)

		it("drops the professions of a character kept anonymous, and passes them on to no one", function()
			sync(a, b)
			now = now + 1
			a.characters:keepAnonymous(a.name)
			announce(a, c)
			sync(b, c)
			assert.is_nil(shown(c))
		end)

		it("lets two peers that synced before sharing professions sync once more early to share them", function()
			for _, peer in ipairs({ a, b }) do
				peer.saved, peer.early = {}, {}
				peer.sync = Sync.new(peer.saved, clock, peer.memory, { passOn = true }) -- before the update
			end
			sync(a, b)
			now = now + HOUR
			for _, peer in ipairs({ a, b }) do
				peer.sync = Sync.new(peer.saved, clock, peer.memory, { passOn = true }, peer.professions, peer.early)
			end
			sync(a, b)
			assert.equal(50, shown(b).level)
			now = now + 1
			a.characters:seeProfessions(a.name, { { skillLine = ALCHEMY, level = 60, maxLevel = 75 } })
			sync(a, b)
			sync(b, a)
			assert.equal(50, shown(b).level)
		end)

		it("takes at most 2,000 second-hand professions a day from one peer", function()
			local names = { a, b, c, d, mallory }
			for i = 1, Professions.MAX_CHANGES_PER_PEER + 100 do
				names[#names + 1] = { name = "Fake Name" .. i, professions = { seeLists = function() end } }
			end
			guild(unpack(names))
			for i = 1, Professions.MAX_CHANGES_PER_PEER + 100 do
				local heard = { name = "Fake Name" .. i, skillLine = ALCHEMY, revision = 900, level = 1, maxLevel = 75 }
				mallory.professions:hear("Zed Ex" .. i % 2, heard)
			end
			assert.equal(Professions.MAX_CHANGES_PER_PEER + 100, #mallory.professions:list())
			sync(mallory, d)
			assert.equal(Professions.MAX_CHANGES_PER_PEER, #d.professions:list())
			now = now + DAY
			sync(mallory, d)
			assert.equal(Professions.MAX_CHANGES_PER_PEER + 100, #d.professions:list())
		end)
	end)
end)
