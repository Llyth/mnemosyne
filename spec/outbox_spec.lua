local ns = require("spec.helpers.addon")("Protocol", "Outbox")
local Outbox = ns.Outbox

describe("Outbox", function()
	local now, outbox, port, sent, results, paused

	before_each(function()
		now, sent, results, paused = 0, {}, {}, false
		outbox = Outbox.new(function()
			return now
		end, function()
			return true
		end)
		port = {
			paused = function()
				return paused
			end,
			-- A sync chunk goes as it is, by whisper; any other job as its key,
			-- costing a token unless whispered.
			compose = function(job)
				if job.text then
					return { text = job.text, target = job.target }
				elseif job.news then
					return { text = "news", costs = true }
				end
				return { text = job.key, target = job.target, costs = job.channel ~= "WHISPER" }
			end,
			send = function(out)
				sent[#sent + 1] = out.text
				return results[out.target or ""] or "sent"
			end,
		}
	end)

	local function sync(peer, text)
		return { peer = peer, text = text, kind = "identities" }
	end

	it("queues a job once while it waits", function()
		assert.is_true(outbox:add("announce", "GUILD"))
		assert.is_false(outbox:add("announce", "GUILD"))
		outbox:flush(port)
		assert.same({ "announce:GUILD:" }, sent)
		assert.is_true(outbox:add("announce", "GUILD"))
	end)

	it("queues nothing on an account that cannot send", function()
		outbox = Outbox.new(function()
			return now
		end, function()
			return false
		end)
		assert.is_false(outbox:add("ask", "GUILD"))
		outbox:addSyncs({ sync("Anna Conda", "x") })
		assert.is_false(outbox:flush(port))
		assert.same({}, sent)
	end)

	it("drops an answer once 20 jobs wait", function()
		for i = 1, Outbox.MAX_ANSWERS do
			assert.is_true(outbox:add("answer", "WHISPER", "Peer " .. i))
		end
		assert.is_false(outbox:add("answer", "WHISPER", "Peer 21"))
		assert.is_true(outbox:add("announce", "GUILD"))
	end)

	it("sends nothing in combat or lockdown, and keeps the jobs", function()
		outbox:add("announce", "GUILD")
		paused = true
		assert.is_true(outbox:flush(port))
		assert.same({}, sent)
		paused = false
		assert.is_false(outbox:flush(port))
		assert.same({ "announce:GUILD:" }, sent)
	end)

	it("spends the burst of 10 on messages that cost, then 1 a second", function()
		for i = 1, 12 do
			outbox:add("ask", "GUILD", "Peer " .. i)
		end
		outbox:flush(port)
		assert.equal(Outbox.BURST, #sent)
		now = 1
		outbox:flush(port)
		assert.equal(Outbox.BURST + 1, #sent)
	end)

	it("lets whispers through without spending the burst", function()
		for i = 1, 12 do
			outbox:add("answer", "WHISPER", "Peer " .. i)
		end
		outbox:flush(port)
		assert.equal(12, #sent)
	end)

	it("paces all messages to about 1,000 bytes a second", function()
		local chunk = string.rep("x", 250)
		outbox:addSyncs({ sync("Anna Conda", chunk), sync("Anna Conda", chunk), sync("Anna Conda", chunk) })
		outbox:addSyncs({ sync("Anna Conda", chunk), sync("Anna Conda", chunk), sync("Anna Conda", chunk) })
		outbox:flush(port)
		assert.equal(4, #sent)
		now = 0.5
		outbox:flush(port)
		assert.equal(6, #sent)
	end)

	it("sends every other job before the syncs", function()
		outbox:addSyncs({ sync("Anna Conda", "sync") })
		outbox:add("announce", "GUILD")
		outbox:flush(port)
		assert.same({ "announce:GUILD:", "sync" }, sent)
	end)

	it("sends the syncs in turns, the peer served longest ago first", function()
		outbox:addSyncs({ sync("Anna Conda", "a1"), sync("Anna Conda", "a2") })
		outbox:addSyncs({ sync("Barb Dwyer", "b1"), sync("Barb Dwyer", "b2") })
		outbox:flush(port)
		assert.same({ "a1", "b1", "a2", "b2" }, sent)
	end)

	it("cuts a sync from the first message that does not fit", function()
		local max = Outbox.MAX_SYNC_CHUNKS
		Outbox.MAX_SYNC_CHUNKS = 2
		outbox:addSyncs({ sync("Anna Conda", "a1"), sync("Anna Conda", "a2") })
		outbox:addSyncs({ sync("Barb Dwyer", "b1"), sync("Carrie Oakey", "c1") })
		Outbox.MAX_SYNC_CHUNKS = max
		outbox:flush(port)
		assert.same({ "a1", "a2" }, sent)
	end)

	it("splits a long sync message into chunks", function()
		outbox:addSyncs({ sync("Anna Conda", string.rep("x", 600)) })
		outbox:flush(port)
		now = 1
		outbox:flush(port)
		assert.equal(3, #sent)
		assert.truthy(sent[1]:find("^%d+:C:"))
	end)

	it("keeps a throttled message at the head and stops until later", function()
		outbox:add("answer", "WHISPER", "Anna Conda")
		outbox:add("answer", "WHISPER", "Barb Dwyer")
		results["Anna Conda"] = "retry"
		assert.is_true(outbox:flush(port))
		assert.same({ "answer:WHISPER:Anna Conda" }, sent)
		results["Anna Conda"] = nil
		outbox:flush(port)
		assert.same({ "answer:WHISPER:Anna Conda", "answer:WHISPER:Anna Conda", "answer:WHISPER:Barb Dwyer" }, sent)
	end)

	it("drops the rest of a sync once the peer cannot get it", function()
		outbox:addSyncs({ sync("Anna Conda", "a1"), sync("Anna Conda", "a2") })
		outbox:addSyncs({ sync("Barb Dwyer", "b1"), sync("Barb Dwyer", "b2") })
		results["Anna Conda"] = "failed"
		assert.is_false(outbox:flush(port))
		assert.same({ "a1", "b1", "b2" }, sent)
	end)

	describe("with a lazy answer", function()
		-- A lazy answer (Sync's produce): its messages in turn, false where it is
		-- not ready yet; it counts how often it was asked.
		local asked
		local function lazy(peer, ...)
			local steps, at = { ... }, 0
			asked = 0
			return {
				peer = peer,
				produce = function()
					asked = asked + 1
					at = at + 1
					local step = steps[at]
					if step == false then
						return false
					end
					return step and sync(peer, step)
				end,
			}
		end

		it("asks it for its next message only once the peer's queued ones are sent", function()
			outbox:addSyncs({ sync("Anna Conda", "digest"), lazy("Anna Conda", "a1", "a2", "done") })
			assert.equal(0, asked)
			outbox:flush(port)
			assert.same({ "digest", "a1", "a2", "done" }, sent)
			assert.equal(4, asked)
			assert.is_false(outbox:flush(port))
		end)

		it("goes on with it at the next look while it is not ready, sending the others meanwhile", function()
			outbox:addSyncs({ lazy("Anna Conda", false, "a1") })
			outbox:addSyncs({ sync("Barb Dwyer", "b1") })
			assert.is_true(outbox:flush(port))
			assert.same({ "b1" }, sent)
			assert.is_false(outbox:flush(port))
			assert.same({ "b1", "a1" }, sent)
		end)

		it("keeps a message queued after it behind it", function()
			outbox:addSyncs({ lazy("Anna Conda", "a1"), sync("Anna Conda", "a2") })
			outbox:flush(port)
			assert.same({ "a1", "a2" }, sent)
		end)

		it("asks it nothing in combat or lockdown", function()
			outbox:addSyncs({ lazy("Anna Conda", "a1") })
			paused = true
			assert.is_true(outbox:flush(port))
			assert.equal(0, asked)
		end)

		it("drops it once the peer cannot get its messages", function()
			outbox:addSyncs({ lazy("Anna Conda", "a1", "a2") })
			results["Anna Conda"] = "failed"
			assert.is_false(outbox:flush(port))
			assert.same({ "a1" }, sent)
			assert.equal(1, asked)
		end)

		it("cuts one that comes while 3 peers' answers are being made", function()
			for _, peer in ipairs({ "Anna Conda", "Barb Dwyer", "Cole Slaw", "Dee Zaster" }) do
				outbox:addSyncs({ lazy(peer, peer) })
			end
			outbox:flush(port)
			assert.same({ "Anna Conda", "Barb Dwyer", "Cole Slaw" }, sent)
		end)

		it("cuts it from the first message that does not fit", function()
			local max = Outbox.MAX_SYNC_CHUNKS
			Outbox.MAX_SYNC_CHUNKS = 1
			outbox:addSyncs({ sync("Barb Dwyer", "b1"), lazy("Anna Conda", "a1", "a2") })
			outbox:flush(port)
			Outbox.MAX_SYNC_CHUNKS = max
			assert.same({ "b1" }, sent)
			assert.is_false(outbox:flush(port))
			assert.equal(1, asked)
		end)
	end)

	it("drops a job with nothing to send, and lets it be queued again", function()
		port.compose = function() end
		outbox:add("announce", "GROUP")
		assert.is_false(outbox:flush(port))
		assert.same({}, sent)
		assert.is_true(outbox:add("announce", "GROUP"))
	end)

	it("queues news only behind no other job", function()
		outbox:add("announce", "GUILD")
		assert.is_true(outbox:hasJobs())
		outbox:flush(port)
		assert.is_false(outbox:hasJobs())
		outbox:addNews({ name = "Anna Conda" })
		outbox:flush(port)
		assert.same({ "announce:GUILD:", "news" }, sent)
	end)
end)
