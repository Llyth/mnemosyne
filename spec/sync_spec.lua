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

	it("never passes on an identity whose name is too long for a peer to take", function()
		memory:hear(string.rep("a", 60) .. " Jass", { nickname = "Tony", revision = 900 })
		local outgoing = sync:receive("Barb Dwyer", { kind = "digest", digest = emptyDigest() })
		assert.equal("1:I:900:Hugh Jass:Tony", outgoing[2].text)
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

	describe("between two peers", function()
		local function newPeer(name)
			local peer = { name = name, memory = Memory.new({}, clock), reader = Protocol.newReader(clock) }
			peer.sync = Sync.new({}, clock, peer.memory, { passOn = true }, Self.new({}, clock))
			return peer
		end

		-- Delivers to a peer what was sent to it, chunks put together; returns its replies.
		local function deliver(from, to, outgoing)
			local replies = {}
			for _, out in ipairs(outgoing) do
				if out.peer == to.name then
					local message
					for _, chunk in ipairs(Protocol.split(out.text)) do
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
				anna.sync = Sync.new({}, clock, anna.memory, { passOn = true }, Self.new({}, clock))
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
			anna.sync = Sync.new({}, clock, anna.memory, { passOn = true }, Self.new({}, clock))
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
end)
