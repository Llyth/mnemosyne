local ns = require("spec.helpers.addon")("Protocol", "Memory", "Self", "Sync", "News", "Outbox", "Inbox")
local Protocol, Inbox = ns.Protocol, ns.Inbox

describe("Inbox", function()
	local now, inbox, memory, guildNews, outbox, dropped, newer, inScope, versions, ownVersion

	local function clock()
		return now
	end

	before_each(function()
		now, dropped, newer, versions, ownVersion = 1000, {}, 0, {}, "1.4.0"
		inScope = function(name)
			return name ~= "Mallory Knox"
		end
		local settings = { passOn = true }
		local characters = ns.Self.new({}, clock)
		memory = ns.Memory.new({}, clock)
		outbox = ns.Outbox.new(clock, function()
			return true
		end)
		guildNews = ns.News.new(clock, function()
			return 0
		end, memory, characters, settings)
		inbox = Inbox.new({
			clock = clock,
			serverClock = clock,
			memory = memory,
			sync = ns.Sync.new({}, clock, memory, settings, characters),
			news = guildNews,
			reader = Protocol.newReader(clock),
			outbox = outbox,
			wake = function() end,
			canSend = function()
				return true
			end,
			inScope = function(name)
				return inScope(name)
			end,
			playerName = function()
				return "Hugh Jass"
			end,
			log = {
				isOn = function()
					return false
				end,
				received = function() end,
				dropped = function(sender, reason)
					dropped[#dropped + 1] = (sender or "?") .. " " .. reason
				end,
			},
			onNewer = function()
				newer = newer + 1
			end,
			versions = versions,
			version = function()
				return ownVersion
			end,
		})
	end)

	-- Whom the outbox sends to, each once, in the order first sent to.
	local function targets()
		local sent, seen = {}, {}
		local port = {
			paused = function()
				return false
			end,
			compose = function(job)
				return { text = job.text or job.key, target = job.target }
			end,
			send = function(out)
				local target = out.target or "?"
				if not seen[target] then
					seen[target] = true
					sent[#sent + 1] = target
				end
				return "sent"
			end,
		}
		repeat
			now = now + 10
		until not outbox:flush(port)
		return sent
	end

	local announce = Protocol.write({ kind = "announcement", nickname = "Tony", revision = 900 })
	local ask = Protocol.write({ kind = "ask" })

	it("learns a peer's announcement first-hand, under the name the server gives", function()
		inbox:receive("Anna Conda", "GUILD", announce)
		assert.equal("Tony", memory:recall("Anna Conda").nickname)
		assert.is_true(memory:recall("Anna Conda").firstHand)
	end)

	it("drops a message from the player or from no one", function()
		inbox:receive("Hugh Jass", "GUILD", announce)
		inbox:receive("", "GUILD", announce)
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.same({}, dropped)
	end)

	it("drops a message from outside the scope, except on the guild's channel", function()
		inbox:receive("Mallory Knox", "WHISPER", announce)
		assert.is_nil(memory:recall("Mallory Knox"))
		assert.same({ "Mallory Knox scope" }, dropped)
		inbox:receive("Mallory Knox", "GUILD", announce)
		assert.equal("Tony", memory:recall("Mallory Knox").nickname)
	end)

	describe("versions", function()
		local version = Protocol.write({ kind = "version", version = "1.4.0" })

		it("keeps the version a peer runs, under the name the server gives", function()
			inbox:receive("Anna Conda", "GUILD", version)
			assert.equal("1.4.0", versions["Anna Conda"])
			assert.is_nil(memory:recall("Anna Conda"))
		end)

		it("whispers its own back, once a session, to a version heard on the guild's or the group's channel", function()
			inbox:receive("Anna Conda", "GUILD", version)
			inbox:receive("Anna Conda", "GUILD", version)
			inbox:receive("Barb Dwyer", "PARTY", version)
			assert.same({ "Anna Conda", "Barb Dwyer" }, targets())
		end)

		it("never whispers back a version that came by whisper, so two peers never loop", function()
			inbox:receive("Anna Conda", "WHISPER", version)
			assert.equal("1.4.0", versions["Anna Conda"])
			assert.same({}, targets())
		end)

		it("never whispers back when it has no version, in a copy the packager did not build", function()
			ownVersion = nil
			inbox:receive("Anna Conda", "GUILD", version)
			assert.equal("1.4.0", versions["Anna Conda"])
			assert.same({}, targets())
		end)

		it("drops a version from outside the scope", function()
			inbox:receive("Mallory Knox", "WHISPER", version)
			assert.is_nil(versions["Mallory Knox"])
			assert.same({ "Mallory Knox scope" }, dropped)
		end)
	end)

	it("says once a session that a newer Mnemosyne exists", function()
		local later = (Protocol.VERSION + 1) .. ":Q"
		inbox:receive("Anna Conda", "GUILD", later)
		inbox:receive("Barb Dwyer", "GUILD", later)
		assert.equal(1, newer)
		assert.same({ "Anna Conda newer", "Barb Dwyer newer" }, dropped)
	end)

	it("answers an ask once a minute per sender", function()
		inbox:receive("Anna Conda", "GUILD", ask)
		inbox:receive("Anna Conda", "GUILD", ask)
		assert.same({ "Anna Conda cooldown" }, dropped)
		assert.same({ "Anna Conda" }, targets())
		now = now + Inbox.ANSWER_COOLDOWN
		inbox:receive("Anna Conda", "GUILD", ask)
		assert.same({ "Anna Conda" }, targets())
	end)

	it("takes sync messages by whisper only, and news on the guild's channel only", function()
		inbox:receive("Anna Conda", "GUILD", Protocol.write({ kind = "done" }))
		local news = Protocol.write({ kind = "news", identity = { name = "Barb Dwyer", revision = 900 } })
		inbox:receive("Anna Conda", "WHISPER", news)
		assert.same({ "Anna Conda channel", "Anna Conda channel" }, dropped)
	end)

	it("posts to the guild the identities a sync by whisper brought", function()
		local digest = Protocol.write({ kind = "digest", digest = ns.Memory.new({}, clock):digest() })
		for _, chunk in ipairs(Protocol.newWriter():split(digest)) do
			inbox:receive("Anna Conda", "WHISPER", chunk)
		end
		local identities = Protocol.write({
			kind = "identities",
			identities = { { name = "Barb Dwyer", nickname = "Barb", revision = 900 } },
		})
		inbox:receive("Anna Conda", "WHISPER", identities)
		assert.same({ name = "Barb Dwyer", nickname = "Barb", revision = 900 }, guildNews:due())
	end)

	it("learns guild news second-hand, with the guildmate as source, and drops news it holds already", function()
		local posted =
			Protocol.write({ kind = "news", identity = { name = "Barb Dwyer", nickname = "Barb", revision = 900 } })
		inbox:receive("Anna Conda", "GUILD", posted)
		assert.equal("Barb", memory:recall("Barb Dwyer").nickname)
		assert.equal("Anna Conda", memory:recall("Barb Dwyer").source)
		assert.same({}, dropped)
		inbox:receive("Cole Slaw", "GUILD", posted)
		assert.same({ "Cole Slaw older" }, dropped)
	end)

	it("takes professions and their digest by whisper only, as other sync messages", function()
		local digest = Protocol.write({ kind = "professionDigest", digest = string.rep("0", Protocol.DIGEST_LENGTH) })
		local professions = Protocol.write({
			kind = "professions",
			professions = { { name = "Barb Dwyer", skillLine = 171, revision = 900 } },
		})
		for _, chunk in ipairs(Protocol.newWriter():split(digest)) do
			inbox:receive("Anna Conda", "GUILD", chunk)
		end
		inbox:receive("Anna Conda", "GUILD", professions)
		assert.same({ "Anna Conda channel", "Anna Conda channel" }, dropped)
		inbox:receive("Anna Conda", "WHISPER", professions)
		assert.same({ "Anna Conda channel", "Anna Conda channel" }, dropped)
	end)

	it("syncs with a group member who is a peer", function()
		inbox:loggedIn()
		now = now + Inbox.LOGIN_WINDOW
		inbox:receive("Anna Conda", "PARTY", announce)
		assert.same({ "Anna Conda" }, targets())
	end)

	it("syncs after login with the first 3 peers answering within a minute", function()
		inbox:loggedIn()
		local answer = Protocol.write({ kind = "answer", nickname = "Tony", revision = 900 })
		local running = ns.Sync.MAX_RUNNING
		ns.Sync.MAX_RUNNING = 10
		for _, peer in ipairs({ "Anna Conda", "Barb Dwyer", "Carrie Oakey", "Dee Zaster" }) do
			inbox:receive(peer, "WHISPER", answer)
		end
		ns.Sync.MAX_RUNNING = running
		assert.same({ "Anna Conda", "Barb Dwyer", "Carrie Oakey" }, targets())
	end)

	it("starts syncs with the peers heard, the most recently heard first", function()
		inbox:receive("Anna Conda", "GUILD", announce)
		now = now + 1
		inbox:receive("Barb Dwyer", "GUILD", announce)
		assert.equal(2, inbox:peerCount())
		assert.equal(2, inbox:syncAll())
		assert.same({ "Barb Dwyer", "Anna Conda" }, targets())
		inbox:forget("Anna Conda")
		assert.equal(1, inbox:peerCount())
	end)
end)
