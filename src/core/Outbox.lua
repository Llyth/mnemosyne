-- Outbox: the paced queue of addon messages (decision 0002). Pure: it takes
-- the clock and whether the account can send as arguments, and reaches the
-- game only through the port flush is given (decision 0004); Client sends.
--
-- Jobs (announcements, asks, answers, news) go first, in order; then the sync
-- messages, the peer served longest ago first, so each keeps hearing from its
-- sync. All messages together keep to about 1 KB a second; those that cost
-- the client's per-prefix allowance (all but whispers outside instances) also
-- keep to a burst of 10, then 1 a second.
local _, ns = ...

local Protocol = ns.Protocol

local Outbox = {}
Outbox.__index = Outbox
ns.Outbox = Outbox

Outbox.BURST, Outbox.REFILL = 10, 1 -- the client's allowance per prefix: 10 messages, then 1 per second
Outbox.BYTES_PER_SECOND = 1000 -- the pace, all messages together (decision 0002)
Outbox.MAX_ANSWERS = 20 -- once this many jobs wait, an ask is dropped, not answered
-- Chunks the sync queue holds at most, about 15,000 identities, two or three
-- answers at their largest (5,000 vouched and 1,000 others): what comes beyond is
-- dropped, so peers asking for syncs one after another cannot grow it.
Outbox.MAX_SYNC_CHUNKS = 4000

-- clock: returns the time, in seconds.
-- canSend: returns whether this account can send addon messages at all.
function Outbox.new(clock, canSend)
	return setmetatable({
		clock = clock,
		canSend = canSend,
		jobs = {}, -- in order
		waiting = {}, -- the keys of the jobs in it
		syncs = {}, -- sync messages, sent once no job waits: { text, target, kind }
		syncSends = 0, -- sync messages sent
		servedAt = {}, -- peer -> syncSends when it was last sent one
		tokens = Outbox.BURST,
		bytes = Outbox.BYTES_PER_SECOND,
		refilledAt = clock(),
		writer = Protocol.newWriter(), -- splits long messages into chunks
	}, Outbox)
end

-- Queues a job once: a job already waiting (one announcement per channel, one
-- answer per sender) is not queued twice. Returns true when it queued the job.
function Outbox:add(kind, channel, target)
	if not self.canSend() then
		return false
	end
	local key = kind .. ":" .. channel .. ":" .. (target or "")
	if self.waiting[key] or (kind == "answer" and #self.jobs >= Outbox.MAX_ANSWERS) then
		return false
	end
	self.waiting[key] = true
	self.jobs[#self.jobs + 1] = { key = key, kind = kind, channel = channel, target = target }
	return true
end

-- Whether a job waits (syncs aside).
function Outbox:hasJobs()
	return self.jobs[1] ~= nil
end

-- Queues news to post: an identity.
function Outbox:addNews(identity)
	self.jobs[#self.jobs + 1] = { news = identity }
end

-- Queues what Sync returned ({ peer, text, kind } each), each message as its
-- chunks, after everything else. A sync that does not fit is cut from the
-- first message that does not fit: the peer stops hearing it and lets it go.
function Outbox:addSyncs(outgoing)
	if not self.canSend() then
		return
	end
	local syncs, cut = self.syncs, {}
	for _, out in ipairs(outgoing) do
		local chunks = self.writer:split(out.text)
		if cut[out.peer] or #syncs + #chunks > Outbox.MAX_SYNC_CHUNKS then
			cut[out.peer] = true
		else
			for i, text in ipairs(chunks) do
				-- The kind, for the debug log: the message's on its first chunk.
				syncs[#syncs + 1] = { text = text, target = out.peer, kind = i == 1 and out.kind or "chunk" }
			end
		end
	end
end

-- The index of the sync message to send next: the first one to the peer
-- served longest ago.
local function nextSync(self)
	local at, oldest
	for i, job in ipairs(self.syncs) do
		local served = self.servedAt[job.target] or 0
		if not oldest or served < oldest then
			at, oldest = i, served
		end
	end
	return at
end

-- Drops every sync message to a peer.
local function dropSync(self, peer)
	local kept = {}
	for _, job in ipairs(self.syncs) do
		if job.target ~= peer then
			kept[#kept + 1] = job
		end
	end
	self.syncs = kept
end

-- Sends what the allowance permits, oldest job first and syncs last, unless
-- port.paused(). port.compose(job) builds a job's message,
-- { text, target, costs }, costs when it spends the per-prefix allowance, or
-- nothing to drop the job; port.send(message) sends it and returns "sent",
-- "retry" (throttled: try it again later) or "failed". Returns whether
-- anything is left to send.
function Outbox:flush(port)
	local now = self.clock()
	local elapsed = now - self.refilledAt
	self.tokens = math.min(Outbox.BURST, self.tokens + elapsed * Outbox.REFILL)
	self.bytes = math.min(Outbox.BYTES_PER_SECOND, self.bytes + elapsed * Outbox.BYTES_PER_SECOND)
	self.refilledAt = now
	while (self.jobs[1] or self.syncs[1]) and not port.paused() do
		local isSync = not self.jobs[1]
		local list = isSync and self.syncs or self.jobs
		local at = isSync and nextSync(self) or 1
		local job = list[at]
		local message = port.compose(job)
		if message then
			if (message.costs and self.tokens < 1) or self.bytes < #message.text then
				return true
			end
			local result = port.send(message)
			if result == "retry" then
				self.tokens = 0
				return true
			end
			if message.costs then
				self.tokens = self.tokens - 1
			end
			self.bytes = self.bytes - #message.text
			if isSync then
				self.syncSends = self.syncSends + 1
				self.servedAt[job.target] = self.syncSends
				if result ~= "sent" then
					-- The peer cannot get it (offline): the rest of its sync, this one
					-- included, would go nowhere.
					dropSync(self, job.target)
					at = nil
				end
			end
		end
		if at then
			table.remove(list, at)
		end
		if job.key then
			self.waiting[job.key] = nil
		end
	end
	return self.jobs[1] ~= nil or self.syncs[1] ~= nil
end
