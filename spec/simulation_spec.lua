-- The multi-peer simulation (docs/agents/testing.md): several peers, each with
-- its own Memory, Self, Sync and Protocol reader, wired through an in-memory
-- transport that carries wire text, chunks included, the way Client would.
local ns = require("spec.helpers.addon")("Protocol", "Memory", "Self", "Sync")
local Memory, Protocol, Self, Sync = ns.Memory, ns.Protocol, ns.Self, ns.Sync

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

	local function post(from, outgoing)
		for _, out in ipairs(outgoing) do
			for _, text in ipairs(Protocol.split(out.text)) do
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
			if message and (message.kind == "digest" or message.kind == "identities" or message.kind == "done") then
				post(wire.to, peer.sync:receive(wire.from, message))
			elseif message then
				peer.memory:hear(wire.from, { nickname = message.nickname, revision = message.revision })
			end
		end
	end

	local function newPeer(name)
		local memory = Memory.new({}, clock)
		local characters = Self.new({}, clock)
		local peer = {
			name = name,
			memory = memory,
			characters = characters,
			sync = Sync.new({}, clock, memory, { passOn = true }, characters),
			reader = Protocol.newReader(clock),
		}
		peers[name] = peer
		return peer
	end

	-- A character tells others who plays it, as its announcement would.
	local function announce(peer, ...)
		local registration = peer.characters:registration(peer.name)
		local message = { kind = "removal", revision = registration.revision }
		if registration.nickname then
			message = { kind = "announcement", nickname = registration.nickname, revision = registration.revision }
		end
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

	it("takes at most 1,000 new identities a day from one peer", function()
		local mallory = newPeer("Mallory Knox")
		for i = 1, 1500 do
			mallory.memory:hear("Fake Name" .. i, { nickname = "Mallory", revision = 900 })
		end
		sync(mallory, d)
		assert.equal(Memory.MAX_NEW_PER_PEER, d.memory:count())
		now = now + DAY
		sync(mallory, d)
		assert.equal(1500, d.memory:count())
	end)

	it("passes on nothing from a peer that switched it off, but still learns", function()
		announce(a, b)
		local e = newPeer("Ella Vator")
		e.characters:register(e.name, "Ella")
		announce(e, c)
		b.sync = Sync.new({}, clock, b.memory, { passOn = false }, b.characters)
		sync(b, c)
		assert.is_nil(c.memory:recall(a.name))
		assert.equal("Ella", b.memory:recall(e.name).nickname)
	end)
end)
