local ns = require("spec.helpers.addon")(
	"Protocol",
	"Digest",
	"Memory",
	"Self",
	"Scope",
	"Copies",
	"Professions",
	"Milestones",
	"Progress",
	"Sync"
)
local Memory, Professions, Progress, Protocol, Scope, Self, Sync =
	ns.Memory, ns.Professions, ns.Progress, ns.Protocol, ns.Scope, ns.Self, ns.Sync

describe("Sync", function()
	local HOUR = 60 * 60
	local LISTED = 15 * 60 -- the cooldown with a friend or a guildmate
	local now, saved, memory, settings, characters, sync, played

	-- The character logged on, which syncs.
	local function playing()
		return played
	end

	local function clock()
		return now
	end

	before_each(function()
		now = 100000
		saved = {}
		memory = Memory.new({}, clock)
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		settings = { passOn = true }
		characters = Self.new({}, clock)
		played = "Bea Bop"
		sync = Sync.new(saved, clock, memory, settings, nil, nil, nil, playing)
	end)

	-- Reads what Sync sends the way the peer gets it, chunks put together.
	local function decode(text)
		local reader = Protocol.newReader(clock)
		local message
		for _, chunk in ipairs(Protocol.newWriter():split(text)) do
			message = reader:read("Anna Conda", chunk)
		end
		return assert(message, text)
	end

	-- The kinds of the messages sent, in order, each with the peer it goes to.
	local function sent(outgoing)
		local list = {}
		for _, out in ipairs(outgoing) do
			list[#list + 1] = out.peer .. " " .. decode(out.text).kind
		end
		return list
	end

	local function emptyDigest()
		return Memory.new({}, clock):digest()
	end

	-- Runs a whole sync with a peer whose memory is empty.
	local function syncWith(peer)
		sync:request(peer, now)
		sync:receive(peer, { kind = "digest", digest = emptyDigest() })
		return sync:receive(peer, { kind = "done" })
	end

	it("starts a sync by sending its digest to the peer", function()
		local outgoing, accepted = sync:request("Barb Dwyer", now)
		assert.is_true(accepted)
		assert.same({ "Barb Dwyer digest" }, sent(outgoing))
		assert.equal(memory:digest(), decode(outgoing[1].text).digest)
	end)

	it("answers a peer's digest with its own, what the peer lacks, and the end of its part", function()
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.same({ "Barb Dwyer digest", "Barb Dwyer identities", "Barb Dwyer done" }, sent(outgoing))
		assert.same({ { name = "Hugh Jass", nickname = "Tony", revision = 900 } }, decode(outgoing[2].text).identities)
	end)

	it("sends its digest only once when it started the sync", function()
		sync:request("Barb Dwyer", now)
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.same({ "Barb Dwyer identities", "Barb Dwyer done" }, sent(outgoing))
	end)

	it("passes on nothing to a peer whose digest matches its own", function()
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = memory:digest() })
		assert.same({ "Barb Dwyer digest", "Barb Dwyer done" }, sent(outgoing))
	end)

	it("passes on nothing when the player switched off passing on what they know", function()
		settings.passOn = false
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.same({ "Barb Dwyer digest", "Barb Dwyer done" }, sent(outgoing))
	end)

	it("tells a peer it synced with recently that its part is done, so the peer does not ask again", function()
		syncWith("Barb Dwyer")
		assert.same(
			{ "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
	end)

	it("ends its sync with a peer that says it is done, and waits 6 hours before the next", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "done" })
		now = now + Sync.TIMEOUT
		sync:tick()
		assert.same({}, sync:request("Barb Dwyer", now))
	end)

	it("frees the place of a sync whose peer says it is done before answering", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		sync:request("Cole Slaw", now)
		assert.same({ "Cole Slaw digest" }, sent(sync:receive("Anna Conda", { kind = "done" })))
	end)

	it("passes on its memory when the peer's done arrives before its digest", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "done" })
		assert.same(
			{ "Barb Dwyer identities", "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
		assert.same(
			{ "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
	end)

	it("does not answer a digest that comes 2 minutes after the peer's done", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "done" })
		now = now + Sync.TIMEOUT
		assert.same(
			{ "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
	end)

	it("never passes on an identity whose name is too long for a peer to take", function()
		memory:hear(string.rep("a", 60) .. " Jass", { nickname = "Tony", revision = 900 })
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.equal("2:I:900:Hugh Jass:Tony", outgoing[2].text)
	end)

	it(
		"sends only its digest to a peer that sends its digest again in the same sync, then says its part is done",
		function()
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same(
				{ "Barb Dwyer digest" },
				sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
			)
			assert.same(
				{ "Barb Dwyer done" },
				sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
			)
		end
	)

	describe("answering lazily", function()
		local function lazySync()
			return Sync.new({}, clock, memory, settings, nil, nil, nil, playing, nil, true)
		end

		-- Asks each lazy answer for its messages until it is over, as the queue
		-- does; counts the times one was not ready yet.
		local function produced(outgoing)
			local messages, waits = {}, 0
			for _, out in ipairs(outgoing) do
				if out.produce then
					local message = out.produce()
					while message ~= nil do
						if message then
							messages[#messages + 1] = message
						else
							waits = waits + 1
						end
						message = out.produce()
					end
				else
					messages[#messages + 1] = out
				end
			end
			return messages, waits
		end

		local function texts(messages)
			local list = {}
			for i, message in ipairs(messages) do
				list[i] = message.peer .. " " .. message.text
			end
			return list
		end

		it("sends the same messages as a whole answer, made as the queue asks for them", function()
			for i = 1, 3 * Sync.STEP do
				memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = now - i })
			end
			local digest = { kind = "digest", digest = emptyDigest() }
			local whole = sync:receive("Barb Dwyer", digest)
			local outgoing = lazySync():receive("Barb Dwyer", digest)
			assert.same({ "Barb Dwyer digest" }, sent({ outgoing[1] }))
			assert.is_function(outgoing[2].produce)
			local messages, waits = produced(outgoing)
			assert.same(texts(whole), texts(messages))
			assert.is_true(waits >= 3)
		end)

		it("makes nothing more of its answer once the sync is cut", function()
			for i = 1, 100 do
				memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
			end
			sync = lazySync()
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.is_table(outgoing[2].produce())
			now = now + Sync.TIMEOUT
			sync:tick()
			assert.is_nil(outgoing[2].produce())
		end)

		it("still makes its answer after the peer's done", function()
			sync = lazySync()
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			sync:receive("Barb Dwyer", { kind = "done" })
			assert.same({ "Barb Dwyer digest", "Barb Dwyer identities", "Barb Dwyer done" }, sent(produced(outgoing)))
		end)

		it("keeps a sync's place while its answer is still made after the peer's done", function()
			sync = lazySync()
			local digest = { kind = "digest", digest = emptyDigest() }
			local answer = sync:receive("Anna Conda", digest)
			sync:receive("Anna Conda", { kind = "done" })
			sync:receive("Barb Dwyer", digest)
			sync:receive("Barb Dwyer", { kind = "done" })
			assert.same({}, sync:receive("Cole Slaw", digest))
			assert.same({}, sync:tick())
			produced(answer)
			assert.same({ "Cole Slaw digest" }, sent({ sync:tick()[1] }))
		end)

		it("starts no other sync with a peer while its answer still goes out", function()
			for i = 1, 3000 do
				memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
			end
			local scope = Scope.new({})
			scope:see({}, { "Mallory Knox" })
			sync = Sync.new({}, clock, memory, settings, nil, nil, nil, playing, scope, true)
			local digest = { kind = "digest", digest = emptyDigest() }
			local answer = sync:receive("Mallory Knox", digest)[2].produce
			sync:receive("Mallory Knox", { kind = "done" })
			for _ = 1, LISTED / 60 do
				now = now + 60
				local message = answer()
				while message == false do
					message = answer()
				end
				assert.is_table(message)
				sync:tick()
			end
			assert.same({}, sync:receive("Mallory Knox", digest))
			assert.same({ {}, false }, { sync:request("Mallory Knox", now) })
		end)

		it("frees the place of an answer the queue stopped asking for, 2 minutes after", function()
			sync = lazySync()
			local digest = { kind = "digest", digest = emptyDigest() }
			sync:receive("Anna Conda", digest)
			sync:receive("Anna Conda", { kind = "done" })
			sync:receive("Barb Dwyer", digest)
			sync:receive("Barb Dwyer", { kind = "done" })
			sync:receive("Cole Slaw", digest)
			now = now + Sync.TIMEOUT - 1
			assert.same({}, sync:tick())
			now = now + 1
			assert.same({ "Cole Slaw digest" }, sent({ sync:tick()[1] }))
		end)
	end)

	it("sends many identities in batches that each fit a chunked message", function()
		for i = 1, 100 do
			memory:hear("Anna Conda" .. i, { nickname = string.rep("é", 32), revision = 99999999999999 })
		end
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		local count = 0
		for _, out in ipairs(outgoing) do
			assert.is_true(#out.text <= Protocol.MAX_CHUNKED_BYTES)
			local message = decode(out.text)
			count = count + (message.identities and #message.identities or 0)
		end
		assert.equal(101, count)
	end)

	it("sends identities with GUIDs in batches of at most 16 lines, a GUID taking a line", function()
		for i = 1, 20 do
			memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
			memory:see("Anna Conda" .. i, "Player-1-" .. i)
		end
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		local count, guids = 0, 0
		for _, out in ipairs(outgoing) do
			local _, lines = out.text:gsub("\n", "")
			assert.is_true(lines + 1 <= Protocol.MAX_LINES)
			for _, identity in ipairs(decode(out.text).identities or {}) do
				count = count + 1
				guids = guids + (identity.guid and 1 or 0)
			end
		end
		assert.equal(21, count)
		assert.equal(20, guids)
	end)

	it("passes on at most what a peer keeps in a day from one peer, the rest in later syncs", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
		end
		local passedOn, count = {}, 0
		for _ = 1, 2 do
			for _, out in ipairs(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })) do
				for _, identity in ipairs(decode(out.text).identities or {}) do
					count = count + 1
					passedOn[identity.name] = true
				end
			end
			sync:receive("Barb Dwyer", { kind = "done" })
			now = now + Sync.COOLDOWN
		end
		assert.equal(2 * Memory.MAX_CHANGES_PER_PEER, count)
		assert.is_true(passedOn["Hugh Jass"])
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			assert.is_true(passedOn["Anna Conda" .. i])
		end
	end)

	-- The names passed on in one answer to a peer whose memory is empty, in order.
	local function answered(peer)
		local order = {}
		for _, out in ipairs(sync:receive(peer, { kind = "digest", digest = emptyDigest() })) do
			for _, identity in ipairs(decode(out.text).identities or {}) do
				order[#order + 1] = identity.name
			end
		end
		return order
	end

	it("passes on first-hand changes of the last day first, the latest first, past the limit", function()
		for i = 1, 1500 do
			memory:hear("Barb Dwyer" .. i, { nickname = "Barb", revision = 900, source = "Peer" .. i % 2 })
		end
		memory:hear("Anna Conda", { nickname = "Ann", revision = now - 100 })
		memory:hear("Ella Vator", { nickname = "Ella", revision = now - 10 })
		local order = answered("Cole Slaw")
		assert.equal(2 + Memory.MAX_CHANGES_PER_PEER, #order)
		assert.same({ "Ella Vator", "Anna Conda" }, { order[1], order[2] })
	end)

	it("does not put first a first-hand revision far ahead of the clock, which the peer refuses", function()
		for i = 1, 1500 do
			memory:hear("Barb Dwyer" .. i, { nickname = "Barb", revision = 900, source = "Peer" .. i % 2 })
		end
		memory:hear("Anna Conda", { nickname = "Ann", revision = now + 10 * Sync.FRESH })
		memory:hear("Ella Vator", { nickname = "Ella", revision = now - 10 })
		assert.equal("Ella Vator", answered("Cole Slaw")[1])
	end)

	it("vouches for the first-hand changes of the last day it passes on, not for the rest", function()
		memory:hear("Anna Conda", { nickname = "Ann", revision = now - 10 })
		memory:hear("Barb Dwyer", { nickname = "Barb", revision = 900, source = "Cole Slaw" })
		local vouched = {}
		for _, out in ipairs(sync:receive("Ella Vator", { kind = "digest", digest = emptyDigest() })) do
			for _, identity in ipairs(decode(out.text).identities or {}) do
				vouched[identity.name] = identity.vouched or false
			end
		end
		assert.same({ ["Anna Conda"] = true, ["Hugh Jass"] = false, ["Barb Dwyer"] = false }, vouched)
	end)

	it("passes on up to 5,000 first-hand changes of the last day, besides its 1,000 others", function()
		for i = 1, Memory.MAX_VOUCHED_PER_PEER + 10 do
			memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = now - i })
		end
		for i = 1, 1500 do
			memory:hear("Barb Dwyer" .. i, { nickname = "Barb", revision = 900, source = "Peer" .. i % 2 })
		end
		local seen, vouched = {}, 0
		for _, out in ipairs(sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() })) do
			for _, identity in ipairs(decode(out.text).identities or {}) do
				assert.is_nil(seen[identity.name], identity.name)
				seen[identity.name] = true
				vouched = vouched + (identity.vouched and 1 or 0)
			end
		end
		assert.equal(Memory.MAX_VOUCHED_PER_PEER, vouched)
		assert.equal("Anna Conda1", answered("Ella Vator")[1])
	end)

	it("does not vouch for a first-hand revision ahead of the clock", function()
		memory:hear("Anna Conda", { nickname = "Ann", revision = now + 60 })
		for _, out in ipairs(sync:receive("Ella Vator", { kind = "digest", digest = emptyDigest() })) do
			for _, identity in ipairs(decode(out.text).identities or {}) do
				assert.is_nil(identity.vouched, identity.name)
			end
		end
	end)

	it("does not vouch for a change that may reach the peer past its day", function()
		memory:hear("Anna Conda", { nickname = "Ann", revision = now - 24 * HOUR + 10 * 60 })
		for _, out in ipairs(sync:receive("Ella Vator", { kind = "digest", digest = emptyDigest() })) do
			for _, identity in ipairs(decode(out.text).identities or {}) do
				assert.is_nil(identity.vouched, identity.name)
			end
		end
	end)

	it("learns, as vouched, what a peer vouches for", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		for i = 1, Memory.MAX_CHANGES_PER_PEER + 1 do
			sync:receive("Barb Dwyer", {
				kind = "identities",
				identities = { { name = "Anna Conda" .. i, nickname = "Ann", revision = now - 10, vouched = true } },
			})
		end
		assert.equal("Ann", memory:recall("Anna Conda" .. (Memory.MAX_CHANGES_PER_PEER + 1)).nickname)
		assert.equal("Barb Dwyer", memory:recall("Anna Conda1").source)
	end)

	it("lets older first-hand identities take turns with second-hand ones", function()
		for i = 1, 1500 do
			memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
			memory:hear("Barb Dwyer" .. i, { nickname = "Barb", revision = 900, source = "Peer" .. i % 2 })
		end
		local firstHand, secondHand = 0, 0
		for _, name in ipairs(answered("Cole Slaw")) do
			if name:find("^Anna") then
				firstHand = firstHand + 1
			else
				secondHand = secondHand + 1
			end
		end
		assert.is_true(firstHand > 0 and secondHand > 0, firstHand .. " " .. secondHand)
	end)

	it("learns second-hand what a peer it syncs with passes on, with the peer as source", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Ann", revision = 901 } },
		})
		local identity = memory:recall("Anna Conda")
		assert.equal("Ann", identity.nickname)
		assert.is_false(identity.firstHand)
		assert.equal("Barb Dwyer", identity.source)
	end)

	it("learns the GUID a peer passes on with an identity", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Ann", revision = 901, guid = "Player-1-00000001" } },
		})
		memory:see("Anna Conda", "Player-1-00000002")
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("returns the identities a peer passed on that changed the memory, for news", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		local ann = { name = "Anna Conda", nickname = "Ann", revision = 901 }
		local outgoing, learned = sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { ann, { name = "Hugh Jass", nickname = "Tony", revision = 900 } },
		})
		assert.same({}, outgoing)
		assert.same({ ann }, learned)
	end)

	it("marks a change that made an identity disputed, for news", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		local _, learned = sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Ann", revision = 901 } },
		})
		assert.is_nil(learned[1].disputed)
		sync:request("Mallory Knox", now)
		sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })
		_, learned = sync:receive("Mallory Knox", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Mallory", revision = 901 } },
		})
		assert.is_true(learned[1].disputed)
	end)

	it("posts the GUID its memory holds, not the one a peer passed on", function()
		memory:hear(
			"Anna Conda",
			{ nickname = "Ann", revision = 900, source = "Barb Dwyer", guid = "Player-1-00000001" }
		)
		sync:request("Mallory Knox", now)
		sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })
		local _, learned = sync:receive("Mallory Knox", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Ann", revision = 901, guid = "Player-1-00000666" } },
		})
		assert.equal("Player-1-00000001", learned[1].guid)
	end)

	it("drops identities a peer sends before its digest", function()
		sync:request("Mallory Knox", now)
		sync:receive("Mallory Knox", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Mallory", revision = 901 } },
		})
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	-- A memory without the player's own characters would leave, in each bucket
	-- of its digest, exactly their hashes missing from a peer's: subtracting
	-- them would link an anonymous character to the player's others.
	it("learns what peers say about the player's own characters, as anyone's, so its digest matches theirs", function()
		characters:register("Anna Conda", "Ann")
		characters:keepAnonymous("Cole Slaw")
		local peer = Memory.new({}, clock)
		peer:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		peer:hear("Anna Conda", { nickname = "Ann", revision = characters:registration("Anna Conda").revision })
		peer:hear("Cole Slaw", { revision = characters:registration("Cole Slaw").revision })
		sync:receive("Barb Dwyer", { kind = "digest", digest = peer:digest() })
		sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = {
				{ name = "Anna Conda", nickname = "Ann", revision = characters:registration("Anna Conda").revision },
				{ name = "Cole Slaw", revision = characters:registration("Cole Slaw").revision },
			},
		})
		assert.equal(peer:digest(), memory:digest())
	end)

	it("passes on what peers said about the player's own characters, as anyone's", function()
		characters:register("Anna Conda", "Ann")
		memory:hear("Anna Conda", { nickname = "Ann", revision = 800, source = "Dee Lighted" })
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		local names = {}
		for _, identity in ipairs(decode(outgoing[2].text).identities) do
			names[#names + 1] = identity.name
		end
		table.sort(names)
		assert.same({ "Anna Conda", "Hugh Jass" }, names)
	end)

	it("drops identities from a peer it is not syncing with", function()
		sync:receive("Mallory Knox", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Mallory", revision = 901 } },
		})
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("syncs with a peer at most once every 6 hours", function()
		syncWith("Barb Dwyer")
		now = now + 6 * HOUR - 1
		local outgoing, accepted = sync:request("Barb Dwyer", now)
		assert.same({}, outgoing)
		assert.is_false(accepted)
		now = now + 1
		assert.same({ "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
	end)

	it("syncs with a guildmate again after 15 minutes, without professions too", function()
		local scope = Scope.new({})
		scope:see({}, { "Barb Dwyer" })
		sync = Sync.new(saved, clock, memory, settings, nil, nil, nil, playing, scope)
		syncWith("Barb Dwyer")
		now = now + LISTED - 1
		assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
		now = now + 1
		assert.same({ "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
	end)

	it("remembers when it synced with a peer across a reload", function()
		syncWith("Barb Dwyer")
		sync = Sync.new(saved, clock, memory, settings, nil, nil, nil, playing)
		assert.same({}, sync:request("Barb Dwyer", now))
	end)

	it("lets go at load when it synced with a peer more than 6 hours ago", function()
		syncWith("Barb Dwyer")
		now = now + 1
		syncWith("Cole Slaw")
		now = now + 6 * HOUR - 1
		Sync.new(saved, clock, memory, settings)
		assert.same({ ["Cole Slaw"] = now - 6 * HOUR + 1 }, saved[played])
	end)

	it("lets go at load a character's syncs once none of the last 6 hours is left", function()
		syncWith("Barb Dwyer")
		now = now + 6 * HOUR
		Sync.new(saved, clock, memory, settings)
		assert.same({}, saved)
	end)

	-- A cooldown shared by the account's characters would have one refuse a
	-- peer that another synced with: a peer comparing them would link them.
	it("keeps each character's cooldown its own: another of the account's syncs at once", function()
		syncWith("Barb Dwyer")
		now = now + 10 * 60
		played = "Cole Slaw"
		assert.same({}, sync:recent())
		assert.same(
			{ "Barb Dwyer digest", "Barb Dwyer identities", "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
		assert.same({ { peer = "Barb Dwyer", at = now } }, sync:recent())
		played = "Bea Bop"
		assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
	end)

	it("lets go at load the syncs saved before each character kept its own, at most one more sync each", function()
		saved["Barb Dwyer"] = now - 60
		local early = { ["Barb Dwyer"] = "synced" }
		sync = Sync.new(saved, clock, memory, settings, nil, nil, early, playing)
		assert.same({ {}, {} }, { saved, early })
		local _, accepted = sync:request("Barb Dwyer", now)
		assert.is_true(accepted)
	end)

	it("runs at most 2 syncs at once, and starts a waiting one when one ends", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		local outgoing, accepted = sync:request("Cole Slaw", now)
		assert.same({}, outgoing)
		assert.is_true(accepted)
		sync:receive("Anna Conda", { kind = "digest", digest = emptyDigest() })
		assert.same({ "Cole Slaw digest" }, sent(sync:receive("Anna Conda", { kind = "done" })))
	end)

	it("keeps at most 10 syncs waiting, the most recently heard peers first", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		for i = 1, 11 do
			sync:request("Peer" .. i, now - 100 + i)
		end
		local started = {}
		for _ = 1, 6 do
			now = now + 120
			for _, line in ipairs(sent(sync:tick())) do
				started[#started + 1] = line
			end
		end
		local expected = {}
		for i = 11, 2, -1 do
			expected[#expected + 1] = "Peer" .. i .. " digest"
		end
		assert.same(expected, started)
	end)

	it("tells a peer whose digest comes while the waiting list is full that its part is done", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		for i = 1, 10 do
			sync:request("Peer" .. i, now)
		end
		assert.same({ "Cole Slaw done" }, sent(sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() })))
	end)

	it("cuts a sync whose peer stops answering, frees its place, and lets it start again from the digest", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		sync:request("Cole Slaw", now)
		now = now + 119
		assert.same({}, sync:tick())
		now = now + 1
		assert.same({ "Cole Slaw digest" }, sent(sync:tick()))
		assert.same({ "Anna Conda digest" }, sent(sync:request("Anna Conda", now)))
	end)

	it("lets a sync asked for in combat or lockdown wait, and starts it once that ends", function()
		local outgoing, accepted = sync:request("Anna Conda", now, true)
		assert.same({}, outgoing)
		assert.is_true(accepted)
		assert.same({}, sync:tick(true))
		assert.same({ "Anna Conda digest" }, sent(sync:tick()))
	end)

	it("still cuts a sync in combat or lockdown, starting none in its place", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		sync:request("Cole Slaw", now)
		now = now + Sync.TIMEOUT
		assert.same({}, sync:tick(true))
		assert.same({ "Cole Slaw digest" }, sent(sync:tick()))
	end)

	it("keeps a sync going while the peer keeps sending", function()
		sync:request("Barb Dwyer", now)
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		now = now + 100
		sync:receive("Barb Dwyer", { kind = "identities", identities = { { name = "Anna Conda", revision = 901 } } })
		now = now + 100
		sync:tick()
		sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { { name = "Cole Slaw", nickname = "Cole", revision = 901 } },
		})
		assert.equal("Cole", memory:recall("Cole Slaw").nickname)
	end)

	it("counts a sync cut after it passed on its memory toward the 6 hours", function()
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		now = now + 120
		sync:tick()
		assert.same({}, sync:request("Barb Dwyer", now))
	end)

	it("keeps a waiting peer's digest when the peer is asked for again", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() })
		sync:request("Cole Slaw", now + 1)
		sync:receive("Anna Conda", { kind = "digest", digest = emptyDigest() })
		assert.same(
			{ "Cole Slaw digest", "Cole Slaw identities", "Cole Slaw done" },
			sent(sync:receive("Anna Conda", { kind = "done" }))
		)
	end)

	it("cuts a sync whose peer sends only what it already knows", function()
		local known = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } }
		sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })
		sync:receive("Ivy League", { kind = "digest", digest = emptyDigest() })
		for _ = 1, 2 do
			now = now + 100
			sync:receive("Mallory Knox", { kind = "identities", identities = known })
			sync:receive("Ivy League", { kind = "identities", identities = known })
			sync:tick()
		end
		assert.same({ "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
	end)

	it("cuts a sync after 20 minutes, however much the peer passes on", function()
		sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })
		sync:receive("Ivy League", { kind = "digest", digest = emptyDigest() })
		for revision = 1, Sync.MAX_DURATION / 100 do
			now = now + 100
			sync:receive(
				"Mallory Knox",
				{ kind = "identities", identities = { { name = "Anna Conda", revision = revision } } }
			)
			sync:receive(
				"Ivy League",
				{ kind = "identities", identities = { { name = "Cole Slaw", revision = revision } } }
			)
			sync:tick()
		end
		assert.same({ "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
	end)

	it("makes a guildmate whose sync was cut at 20 minutes wait 6 hours, as anyone else", function()
		local scope = Scope.new({})
		scope:see({}, { "Mallory Knox" })
		sync = Sync.new(saved, clock, memory, settings, nil, nil, nil, playing, scope)
		sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })
		for revision = 1, Sync.MAX_DURATION / 100 do
			now = now + 100
			sync:receive(
				"Mallory Knox",
				{ kind = "identities", identities = { { name = "Anna Conda", revision = revision } } }
			)
			sync:tick()
		end
		now = now + LISTED
		assert.same({ {}, false }, { sync:request("Mallory Knox", now) })
		now = now + Sync.COOLDOWN - LISTED
		assert.same({ "Mallory Knox digest" }, sent(sync:request("Mallory Knox", now)))
	end)

	it("makes a guildmate whose answer still went out at 20 minutes wait 6 hours", function()
		for i = 1, 3000 do
			memory:hear("Anna Conda" .. i, { nickname = "Ann", revision = 900 })
		end
		local scope = Scope.new({})
		scope:see({}, { "Mallory Knox" })
		sync = Sync.new(saved, clock, memory, settings, nil, nil, nil, playing, scope, true)
		local answer = sync:receive("Mallory Knox", { kind = "digest", digest = emptyDigest() })[2].produce
		sync:receive("Mallory Knox", { kind = "done" })
		for _ = 1, Sync.MAX_DURATION / 60 do
			now = now + 60
			local message = answer()
			while message == false do
				message = answer()
			end
			sync:tick()
		end
		assert.is_nil(answer())
		now = now + LISTED
		assert.same({ {}, false }, { sync:request("Mallory Knox", now) })
		now = now + Sync.COOLDOWN - LISTED
		assert.same({ "Mallory Knox digest" }, sent(sync:request("Mallory Knox", now)))
	end)

	describe("between two peers", function()
		local function newPeer(name)
			local peer = {
				name = name,
				memory = Memory.new({}, clock),
				reader = Protocol.newReader(clock),
				writer = Protocol.newWriter(),
			}
			peer.sync = Sync.new({}, clock, peer.memory, { passOn = true })
			return peer
		end

		-- Delivers to a peer what was sent to it, chunks put together; returns its replies.
		local function deliver(from, to, outgoing)
			local replies = {}
			for _, out in ipairs(outgoing) do
				if out.peer == to.name then
					local message
					for _, chunk in ipairs(from.writer:split(out.text)) do
						message = to.reader:read(from.name, chunk)
					end
					for _, reply in ipairs(to.sync:receive(from.name, message)) do
						replies[#replies + 1] = reply
					end
				end
			end
			return replies
		end

		-- Delivers back and forth until both peers are quiet.
		local function converse(from, to, outgoing)
			while #outgoing > 0 do
				outgoing = deliver(from, to, outgoing)
				from, to = to, from
			end
		end

		it("passes on what changed in its memory between starting the sync and answering", function()
			local anna, barb = newPeer("Anna Conda"), newPeer("Barb Dwyer")
			anna.memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			barb.memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Cole Slaw" })
			local outgoing = anna.sync:request(barb.name, now)
			anna.memory:hear("Hugh Jass", { nickname = "Tom", revision = 950 })
			converse(anna, barb, outgoing)
			assert.equal("Tom", barb.memory:recall("Hugh Jass").nickname)
		end)

		it(
			"does not send again an answer that was lost to a peer that sends its digest again; the rest comes in a later sync",
			function()
				local anna, barb = newPeer("Anna Conda"), newPeer("Barb Dwyer")
				barb.memory:hear("Bo Nanza", { nickname = "Bo", revision = 900 })
				deliver(anna, barb, (anna.sync:request(barb.name, now)))
				anna.sync = Sync.new({}, clock, anna.memory, { passOn = true })
				converse(anna, barb, (anna.sync:request(barb.name, now)))
				assert.is_nil(anna.memory:recall("Bo Nanza"))
				now = now + Sync.COOLDOWN
				anna.sync:tick()
				converse(anna, barb, (anna.sync:request(barb.name, now)))
				assert.equal("Bo", anna.memory:recall("Bo Nanza").nickname)
			end
		)

		it("sends its answer once to a peer that reloads between its digest and the answer", function()
			local anna, barb = newPeer("Anna Conda"), newPeer("Barb Dwyer")
			barb.memory:hear("Bo Nanza", { nickname = "Bo", revision = 900 })
			local answers = 0
			local receive = barb.sync.receive
			function barb.sync.receive(...)
				local outgoing = receive(...)
				for _, out in ipairs(outgoing) do
					answers = answers + (out.kind == "identities" and 1 or 0)
				end
				return outgoing
			end
			local answer = deliver(anna, barb, (anna.sync:request(barb.name, now)))
			anna.sync = Sync.new({}, clock, anna.memory, { passOn = true })
			converse(barb, anna, answer)
			assert.equal("Bo", anna.memory:recall("Bo Nanza").nickname)
			assert.equal(1, answers)
		end)

		it("does not answer a waiting peer's digest once the peer has cut its sync, so both still sync", function()
			local anna, barb = newPeer("Anna Conda"), newPeer("Barb Dwyer")
			anna.memory:hear("Al Beback", { nickname = "Al", revision = 900 })
			barb.memory:hear("Bo Nanza", { nickname = "Bo", revision = 900 })
			barb.sync:request("Cole Slaw", now)
			barb.sync:request("Dee Lighted", now)
			converse(anna, barb, (anna.sync:request(barb.name, now)))
			now = now + Sync.TIMEOUT
			anna.sync:tick()
			anna.sync:request("Ivy League", now)
			anna.sync:request("Mallory Knox", now)
			converse(barb, anna, barb.sync:receive("Cole Slaw", { kind = "done" }))
			now = now + Sync.TIMEOUT
			barb.sync:tick()
			converse(anna, barb, anna.sync:receive("Ivy League", { kind = "done" }))
			assert.equal("Bo", anna.memory:recall("Bo Nanza").nickname)
			assert.equal("Al", barb.memory:recall("Al Beback").nickname)
		end)
	end)

	it("makes a peer whose digest comes while it is busy wait its turn, then answers that digest", function()
		sync:request("Anna Conda", now)
		sync:request("Barb Dwyer", now)
		assert.same({}, sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() }))
		sync:receive("Anna Conda", { kind = "digest", digest = emptyDigest() })
		assert.same(
			{ "Cole Slaw digest", "Cole Slaw identities", "Cole Slaw done" },
			sent(sync:receive("Anna Conda", { kind = "done" }))
		)
	end)

	it("syncs again at once with a peer after the cooldowns are reset", function()
		syncWith("Barb Dwyer")
		now = now + 5 * 60
		assert.same(
			{ "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
		played = "Cole Slaw"
		syncWith("Anna Conda")
		sync:resetCooldowns()
		assert.same({}, saved)
		assert.same({}, sync:recent())
		played = "Bea Bop"
		local _, accepted = sync:request("Barb Dwyer", now)
		assert.is_true(accepted)
		assert.same(
			{ "Barb Dwyer identities", "Barb Dwyer done" },
			sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
		)
	end)

	it("leaves the early syncs alone when the cooldowns are reset", function()
		local early = { ["Bea Bop"] = { ["Barb Dwyer"] = "synced" } }
		sync = Sync.new(saved, clock, memory, settings, nil, nil, early, playing)
		sync:resetCooldowns()
		assert.same({ ["Bea Bop"] = { ["Barb Dwyer"] = "synced" } }, early)
	end)

	describe("its recent syncs", function()
		it("lists the peers synced in the last 6 hours, the most recent first", function()
			saved[played] = { ["Anna Conda"] = now - 2 * HOUR, ["Cole Slaw"] = now - HOUR }
			saved[played]["Barb Dwyer"] = now - Sync.COOLDOWN
			saved["Cole Slaw"] = { ["Hugh Jass"] = now } -- another character's
			assert.same({
				{ peer = "Cole Slaw", at = now - HOUR },
				{ peer = "Anna Conda", at = now - 2 * HOUR },
			}, sync:recent())
		end)

		it("counts the peers waiting for their sync", function()
			assert.equal(0, sync:waitingCount())
			sync:request("Anna Conda", now)
			sync:request("Barb Dwyer", now)
			sync:request("Cole Slaw", now)
			assert.equal(1, sync:waitingCount())
		end)
	end)

	describe("with professions", function()
		local scope, professions, early
		local NONE = string.rep("0", Protocol.DIGEST_LENGTH)
		local tailoring = { name = "Hugh Jass", skillLine = 197, revision = 900, level = 5, maxLevel = 75 }

		before_each(function()
			characters = Self.new({}, clock, {})
			characters:register("Dee Zaster", "Dee")
			characters:seeProfessions("Dee Zaster", { { skillLine = 171, level = 5, maxLevel = 75 } })
			scope = Scope.new(settings)
			professions = Professions.new({}, clock, memory, characters, settings, scope)
			scope:see({}, { "Barb Dwyer", "Hugh Jass" })
			professions:seeLists()
			early = {}
			sync = Sync.new(saved, clock, memory, settings, professions, nil, early, playing, scope)
		end)

		it("sends the digest of its professions just before its digest, its own stamped first", function()
			assert.equal(NONE, professions:digest("Barb Dwyer"))
			assert.same({ "Barb Dwyer professionDigest", "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
			assert.not_equal(NONE, professions:digest("Barb Dwyer"))
		end)

		it("passes on the professions the peer lacks after the identities, then the end of its part", function()
			professions:hear("Cole Slaw", tailoring)
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same({
				"Barb Dwyer professionDigest",
				"Barb Dwyer digest",
				"Barb Dwyer identities",
				"Barb Dwyer professions",
				"Barb Dwyer done",
			}, sent(outgoing))
			local names = {} -- Dee Zaster's include the removals of the skill lines it lacks
			for _, passed in ipairs(decode(outgoing[4].text).professions) do
				names[passed.name] = true
			end
			assert.same({ ["Dee Zaster"] = true, ["Hugh Jass"] = true }, names)
		end)

		it("passes on only identities to a peer that sent no digest of professions", function()
			professions:hear("Cole Slaw", tailoring)
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same(
				{ "Barb Dwyer professionDigest", "Barb Dwyer digest", "Barb Dwyer identities", "Barb Dwyer done" },
				sent(outgoing)
			)
		end)

		it("passes on professions when the peer's digest of professions comes after its digest", function()
			professions:hear("Cole Slaw", tailoring)
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			local outgoing = sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			assert.same({ "Barb Dwyer professions" }, sent(outgoing))
			assert.same({}, sent(sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })))
		end)

		it("takes professions that come after the peer's done, within 2 minutes", function()
			local message = { kind = "professions", professions = { tailoring } }
			sync:request("Barb Dwyer", now)
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			sync:receive("Barb Dwyer", { kind = "done" })
			sync:receive("Barb Dwyer", message)
			assert.equal("Hugh Jass", professions:list()[2].name)
			now = now + Sync.TIMEOUT
			sync:tick()
			sync:receive("Barb Dwyer", {
				kind = "professions",
				professions = { { name = "Hugh Jass", skillLine = 171, revision = 900, level = 1, maxLevel = 75 } },
			})
			assert.is_nil(professions:list()[3])
		end)

		it("takes professions that come after the peer's digest when its done came before it", function()
			sync:request("Barb Dwyer", now)
			sync:receive("Barb Dwyer", { kind = "done" })
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			now = now + 5
			sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
			assert.equal(2, #professions:list())
		end)

		it("takes professions that come after a long run of identities it already holds", function()
			local held = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } }
			local started = now
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			while now - started < 2 * Sync.TIMEOUT + 5 do
				now = now + 5
				sync:receive("Barb Dwyer", { kind = "identities", identities = held })
				sync:tick()
			end
			sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
			assert.equal(2, #professions:list())
		end)

		it("takes professions that come after a long run of professions it already holds", function()
			local started = now
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			while now - started < 2 * Sync.TIMEOUT + 5 do
				now = now + 5
				sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
				sync:tick()
			end
			local alchemy = { name = "Hugh Jass", skillLine = 171, revision = 900, level = 5, maxLevel = 75 }
			sync:receive("Barb Dwyer", { kind = "professions", professions = { alchemy } })
			assert.equal(3, #professions:list())
		end)

		it("takes no professions after cutting a sync it never answered", function()
			sync:request("Barb Dwyer", now)
			now = now + Sync.TIMEOUT
			sync:tick()
			sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
			assert.equal(1, #professions:list())
		end)

		it("stops taking professions 2 minutes past the 20-minute cut, however long the peer goes on", function()
			local held = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } }
			local started = now
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			while now - started < Sync.MAX_DURATION + Sync.TIMEOUT do
				now = now + 5
				sync:receive("Barb Dwyer", { kind = "identities", identities = held })
				sync:tick()
			end
			sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
			assert.equal(1, #professions:list())
		end)

		it("stops taking professions 2 minutes past the 20-minute cut, however long the peer sends them", function()
			local started = now
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			while now - started < Sync.MAX_DURATION + Sync.TIMEOUT do
				now = now + 5
				sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
				sync:tick()
			end
			local alchemy = { name = "Hugh Jass", skillLine = 171, revision = 900, level = 5, maxLevel = 75 }
			sync:receive("Barb Dwyer", { kind = "professions", professions = { alchemy } })
			assert.equal(2, #professions:list())
		end)

		it("stops taking professions 2 minutes past the 20-minute cut after a done near its end", function()
			local held = { { name = "Hugh Jass", nickname = "Tony", revision = 900 } }
			local started = now
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			-- A new identity each minute keeps the sync going for 19 minutes.
			for i = 1, 19 do
				now = now + 60
				sync:receive("Barb Dwyer", {
					kind = "identities",
					identities = { { name = "Name Number" .. i, nickname = "Name", revision = 900 } },
				})
				sync:tick()
			end
			sync:receive("Barb Dwyer", { kind = "done" })
			while now - started < Sync.MAX_DURATION + Sync.TIMEOUT do
				now = now + 5
				sync:receive("Barb Dwyer", { kind = "identities", identities = held })
				sync:tick()
			end
			sync:receive("Barb Dwyer", { kind = "professions", professions = { tailoring } })
			assert.equal(1, #professions:list())
		end)

		it("forgets a digest of professions whose digest did not follow within 2 minutes", function()
			professions:hear("Cole Slaw", tailoring)
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			now = now + Sync.TIMEOUT
			sync:tick()
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.is_false(sent(outgoing)[4] == "Barb Dwyer professions")
		end)

		it("learns professions second-hand only inside a sync with the peer", function()
			local message = { kind = "professions", professions = { tailoring } }
			sync:receive("Barb Dwyer", message)
			assert.is_nil(professions:list()[2])
			sync:request("Barb Dwyer", now)
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			sync:receive("Barb Dwyer", message)
			assert.equal("Hugh Jass", professions:list()[2].name)
			assert.equal("Barb Dwyer", professions:list()[2].source)
		end)

		-- A whole sync, the digests of professions answered, so the cooldown holds.
		local function syncFully(peer)
			sync:request(peer, now)
			sync:receive(peer, { kind = "professionDigest", digest = NONE })
			sync:receive(peer, { kind = "digest", digest = emptyDigest() })
			sync:receive(peer, { kind = "done" })
		end

		it("syncs with a guildmate again after 15 minutes, not before", function()
			syncFully("Barb Dwyer")
			now = now + LISTED - 1
			assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
			now = now + 1
			assert.same({ "Barb Dwyer professionDigest", "Barb Dwyer digest" }, sent(sync:request("Barb Dwyer", now)))
		end)

		it("syncs with a friend outside the guild again after 15 minutes, not before", function()
			scope:see({ "Cole Slaw" }, { "Barb Dwyer", "Hugh Jass" })
			professions:seeLists()
			syncFully("Cole Slaw")
			now = now + LISTED - 1
			assert.same({ {}, false }, { sync:request("Cole Slaw", now) })
			now = now + 1
			assert.same({ "Cole Slaw professionDigest", "Cole Slaw digest" }, sent(sync:request("Cole Slaw", now)))
		end)

		it("syncs with a stranger at most once every 6 hours, whoever the lists hold", function()
			settings.everyone = true
			scope:see({ "Cole Slaw" }, { "Barb Dwyer", "Hugh Jass" })
			syncFully("Mip Wiq")
			now = now + 6 * HOUR - 1
			assert.same({ {}, false }, { sync:request("Mip Wiq", now) })
			now = now + 1
			assert.same({ "Mip Wiq professionDigest", "Mip Wiq digest" }, sent(sync:request("Mip Wiq", now)))
		end)

		it("answers a guildmate's digest again after 15 minutes, not before", function()
			syncFully("Barb Dwyer")
			now = now + LISTED - 1
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			assert.same(
				{ "Barb Dwyer done" },
				sent(sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
			)
			now = now + 1
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.equal("Barb Dwyer digest", sent(outgoing)[2])
		end)

		it("answers a friend's digest again after 15 minutes, not before", function()
			scope:see({ "Cole Slaw" }, { "Barb Dwyer", "Hugh Jass" })
			professions:seeLists()
			syncFully("Cole Slaw")
			now = now + LISTED - 1
			sync:receive("Cole Slaw", { kind = "professionDigest", digest = NONE })
			assert.same(
				{ "Cole Slaw done" },
				sent(sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() }))
			)
			now = now + 1
			sync:receive("Cole Slaw", { kind = "professionDigest", digest = NONE })
			local outgoing = sync:receive("Cole Slaw", { kind = "digest", digest = emptyDigest() })
			assert.equal("Cole Slaw digest", sent(outgoing)[2])
		end)

		it("lists a guildmate synced in the last 6 hours among its recent syncs", function()
			saved[played] = { ["Barb Dwyer"] = now - 2 * HOUR }
			assert.same({ { peer = "Barb Dwyer", at = now - 2 * HOUR } }, sync:recent())
		end)

		describe("with a peer it synced with lately", function()
			before_each(function()
				saved[played] = { ["Barb Dwyer"] = now - LISTED / 3 } -- synced before either side shared professions
			end)

			it("syncs once more early with a peer whose professions it never heard", function()
				local outgoing, accepted = sync:request("Barb Dwyer", now)
				assert.is_true(accepted)
				assert.same({ "Barb Dwyer professionDigest", "Barb Dwyer digest" }, sent(outgoing))
				sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				sync:receive("Barb Dwyer", { kind = "done" })
				now = now + LISTED / 3
				assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
			end)

			it("answers early, once, the digest of a peer whose professions it never heard", function()
				sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
				local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				assert.same({
					"Barb Dwyer professionDigest",
					"Barb Dwyer digest",
					"Barb Dwyer identities",
					"Barb Dwyer professions",
					"Barb Dwyer done",
				}, sent(outgoing))
				sync:receive("Barb Dwyer", { kind = "done" })
				now = now + LISTED / 3
				sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
				outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				assert.same({ "Barb Dwyer done" }, sent(outgoing))
			end)

			it("lets each character have its own early sync with the peer", function()
				sync:request("Barb Dwyer", now)
				sync:receive("Barb Dwyer", { kind = "done" })
				played = "Cole Slaw"
				saved[played] = { ["Barb Dwyer"] = now - LISTED / 3 }
				local _, accepted = sync:request("Barb Dwyer", now)
				assert.is_true(accepted)
			end)

			it("keeps the cooldown with a peer whose professions it heard", function()
				saved[played] = nil
				sync:request("Barb Dwyer", now)
				sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
				sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				sync:receive("Barb Dwyer", { kind = "done" })
				now = now + LISTED / 3
				assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
				local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				assert.same({ "Barb Dwyer done" }, sent(outgoing))
			end)

			it(
				"syncs early only once with an older peer, which never sends its professions, even after a reload",
				function()
					local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
					assert.equal("Barb Dwyer done", sent(outgoing)[#outgoing])
					assert.is_true(#outgoing > 1)
					sync:receive("Barb Dwyer", { kind = "done" })
					now = now + LISTED / 3
					sync = Sync.new(saved, clock, memory, settings, professions, nil, early, playing, scope)
					assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
					outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
					assert.same({ "Barb Dwyer done" }, sent(outgoing))
				end
			)
		end)
	end)

	describe("with progress", function()
		local scope, professions, progress, early
		local NONE = string.rep("0", Protocol.DIGEST_LENGTH)
		local direMaul = { name = "Hugh Jass", milestone = 4, revision = 900, state = "done", item = 18249 }

		before_each(function()
			characters = Self.new({}, clock, {})
			characters:register("Dee Zaster", "Dee")
			characters:seeProfessions("Dee Zaster", { { skillLine = 171, level = 5, maxLevel = 75 } })
			characters:seeProgress("Dee Zaster", { [4] = { state = "done", item = 18249 } })
			scope = Scope.new(settings)
			professions = Professions.new({}, clock, memory, characters, settings, scope)
			progress = Progress.new({}, clock, memory, characters, settings, scope)
			scope:see({}, { "Barb Dwyer", "Hugh Jass" })
			professions:seeLists()
			progress:seeLists()
			early = {}
			sync = Sync.new(saved, clock, memory, settings, professions, progress, early, playing, scope)
		end)

		local function hasMilestone(name)
			for _, milestone in ipairs(progress:list()) do
				if milestone.name == name then
					return true
				end
			end
			return false
		end

		it("sends the digest of its progress after that of its professions, just before its digest", function()
			assert.same(
				{ "Barb Dwyer professionDigest", "Barb Dwyer progressDigest", "Barb Dwyer digest" },
				sent(sync:request("Barb Dwyer", now))
			)
		end)

		it("passes on the progress the peer lacks after the professions, then the end of its part", function()
			progress:hear("Cole Slaw", direMaul)
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE })
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same({
				"Barb Dwyer professionDigest",
				"Barb Dwyer progressDigest",
				"Barb Dwyer digest",
				"Barb Dwyer identities",
				"Barb Dwyer professions",
				"Barb Dwyer progress",
				"Barb Dwyer done",
			}, sent(outgoing))
			local names = {}
			for _, passed in ipairs(decode(outgoing[6].text).progress) do
				names[passed.name] = true
			end
			assert.same({ ["Dee Zaster"] = true, ["Hugh Jass"] = true }, names)
		end)

		it("passes on identities and professions only to an older peer, which sends no digest of progress", function()
			progress:hear("Cole Slaw", direMaul)
			sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same({
				"Barb Dwyer professionDigest",
				"Barb Dwyer progressDigest",
				"Barb Dwyer digest",
				"Barb Dwyer identities",
				"Barb Dwyer professions",
				"Barb Dwyer done",
			}, sent(outgoing))
			assert.same({}, sent(sync:receive("Barb Dwyer", { kind = "done" })))
		end)

		it("passes on progress when the peer's digest of progress comes after its digest, once", function()
			progress:hear("Cole Slaw", direMaul)
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			local outgoing = sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE })
			assert.same({ "Barb Dwyer progress" }, sent(outgoing))
			assert.same({}, sent(sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE })))
		end)

		it("learns progress second-hand only inside a sync with the peer, and within 2 minutes of its done", function()
			local message = { kind = "progress", progress = { direMaul } }
			sync:receive("Barb Dwyer", message)
			assert.is_false(hasMilestone("Hugh Jass"))
			sync:request("Barb Dwyer", now)
			sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			sync:receive("Barb Dwyer", { kind = "done" })
			sync:receive("Barb Dwyer", message)
			assert.is_true(hasMilestone("Hugh Jass"))
			assert.equal("Barb Dwyer", progress:list()[2].source)
			now = now + Sync.TIMEOUT
			sync:tick()
			sync:receive("Barb Dwyer", {
				kind = "progress",
				progress = { { name = "Hugh Jass", milestone = 7, revision = 900, state = "done" } },
			})
			assert.equal(2, #progress:list())
		end)

		it("forgets a digest of progress whose digest did not follow within 2 minutes", function()
			progress:hear("Cole Slaw", direMaul)
			sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE })
			now = now + Sync.TIMEOUT
			sync:tick()
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.is_false(sent(outgoing)[5] == "Barb Dwyer progress")
		end)

		it("ignores progress and its digest without Progress, as an older version would", function()
			sync = Sync.new(saved, clock, memory, settings, professions, nil, early, playing, scope)
			assert.same({}, sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE }))
			local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
			assert.same({
				"Barb Dwyer professionDigest",
				"Barb Dwyer digest",
				"Barb Dwyer identities",
				"Barb Dwyer done",
			}, sent(outgoing))
			sync:receive("Barb Dwyer", { kind = "progress", progress = { direMaul } })
			assert.is_false(hasMilestone("Hugh Jass"))
		end)

		describe("with a peer it synced with lately", function()
			before_each(function()
				saved[played] = { ["Barb Dwyer"] = now - LISTED / 3 }
			end)

			it("syncs once more early with a peer whose professions it heard, but never its progress", function()
				early[played] = { ["Barb Dwyer"] = "heard" } -- saved before this side shared progress
				local outgoing, accepted = sync:request("Barb Dwyer", now)
				assert.is_true(accepted)
				assert.same(
					{ "Barb Dwyer professionDigest", "Barb Dwyer progressDigest", "Barb Dwyer digest" },
					sent(outgoing)
				)
				sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
				sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				sync:receive("Barb Dwyer", { kind = "done" })
				now = now + LISTED / 4
				assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
			end)

			it("keeps the cooldown with a peer a later version marked, as one whose progress it heard", function()
				early[played] = { ["Barb Dwyer"] = "achievements" } -- a later release's mark, then a downgrade
				assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
			end)

			it("keeps the cooldown with a peer whose progress it heard", function()
				saved[played] = nil
				sync:request("Barb Dwyer", now)
				sync:receive("Barb Dwyer", { kind = "progressDigest", digest = NONE })
				sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
				sync:receive("Barb Dwyer", { kind = "done" })
				assert.equal("progress", early[played]["Barb Dwyer"])
				now = now + LISTED / 3
				assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
			end)

			it(
				"syncs early only once with an older peer, which sends its professions but never its progress",
				function()
					saved[played] = nil
					sync:request("Barb Dwyer", now)
					sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
					sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
					sync:receive("Barb Dwyer", { kind = "done" })
					now = now + LISTED / 4
					assert.is_true(select(2, sync:request("Barb Dwyer", now)))
					sync:receive("Barb Dwyer", { kind = "professionDigest", digest = NONE })
					sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
					sync:receive("Barb Dwyer", { kind = "done" })
					now = now + LISTED / 4
					assert.same({ {}, false }, { sync:request("Barb Dwyer", now) })
				end
			)
		end)
	end)
end)
