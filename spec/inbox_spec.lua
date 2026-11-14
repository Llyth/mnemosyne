local ns = require("spec.helpers.addon")("Protocol", "Memory", "Self", "Sync", "News", "Outbox", "Inbox")
local Protocol, Inbox = ns.Protocol, ns.Inbox

describe("Inbox", function()
	local now, inbox, memory, outbox, dropped, newer, inScope

	local function clock()
		return now
	end

	before_each(function()
		now, dropped, newer = 1000, {}, 0
		inScope = function(name)
			return name ~= "Mallory Knox"
		end
		local settings = { passOn = true }
		local characters = ns.Self.new({}, clock)
		memory = ns.Memory.new({}, clock)
		outbox = ns.Outbox.new(clock, function()
			return true
		end)
		inbox = Inbox.new({
			clock = clock,
			serverClock = clock,
			memory = memory,
			sync = ns.Sync.new({}, clock, memory, settings, characters),
			news = ns.News.new(clock, function()
				return 0
			end, memory, characters, settings),
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
