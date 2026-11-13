local ns = require("spec.helpers.addon")("Protocol", "Memory", "Self", "Sync")
local Memory, Protocol, Self, Sync = ns.Memory, ns.Protocol, ns.Self, ns.Sync

describe("Sync", function()
	local HOUR = 60 * 60
	local now, saved, memory, settings, characters, sync

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
		sync = Sync.new(saved, clock, memory, settings, characters)
	end)

	-- Reads what Sync sends the way the peer gets it, chunks put together.
	local function decode(text)
		local reader = Protocol.newReader(clock)
		local message
		for _, chunk in ipairs(Protocol.split(text)) do
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
		assert.same({}, sync:request("Barb Dwyer", now))
	end)

	it("never passes on an identity whose name is too long for a peer to take", function()
		memory:hear(string.rep("a", 60) .. " Jass", { nickname = "Tony", revision = 900 })
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.equal("1:I:900:Hugh Jass:Tony", outgoing[2].text)
	end)

	it("ignores a second digest in the same sync", function()
		sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.same({}, sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() }))
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

	it("drops identities a peer sends before its digest", function()
		sync:request("Mallory Knox", now)
		sync:receive("Mallory Knox", {
			kind = "identities",
			identities = { { name = "Anna Conda", nickname = "Mallory", revision = 901 } },
		})
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("never passes on nor learns what peers say about the player's own characters", function()
		characters:register("Anna Conda", "Ann")
		characters:keepAnonymous("Cole Slaw")
		memory:hear("Anna Conda", { nickname = "Ann", revision = 800, source = "Dee Lighted" })
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.same({ { name = "Hugh Jass", nickname = "Tony", revision = 900 } }, decode(outgoing[2].text).identities)
		sync:receive("Barb Dwyer", {
			kind = "identities",
			identities = { { name = "Cole Slaw", nickname = "Cole", revision = 901 } },
		})
		assert.is_nil(memory:recall("Cole Slaw"))
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

	it("remembers when it synced with a peer across a reload", function()
		syncWith("Barb Dwyer")
		sync = Sync.new(saved, clock, memory, settings, characters)
		assert.same({}, sync:request("Barb Dwyer", now))
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
end)
