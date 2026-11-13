-- Sync: two peers bringing each other's memory up to date (decision 0002).
-- Pure: it takes its saved table, the clock (the server time), the memory and
-- the settings as arguments (decision 0004), and returns what to send; Client
-- sends it by whisper through its paced queue.
--
-- Each peer sends its digest, then, once it has the other's, the identities
-- the other lacks or holds at an older revision, then the end of its part. A
-- sync with a peer happens at most once every 6 hours; at most 2 run at once
-- and at most 10 wait, the most recently heard peers first. A sync whose peer
-- goes quiet for 2 minutes is cut; the next one starts again from the digest.
local _, ns = ...

local Protocol = ns.Protocol

local Sync = {}
Sync.__index = Sync
ns.Sync = Sync

Sync.COOLDOWN = 6 * 60 * 60 -- seconds between two syncs with the same peer
Sync.MAX_RUNNING = 2
Sync.MAX_WAITING = 10
Sync.TIMEOUT = 120 -- seconds without a message from the peer before a sync is cut

-- saved: when each peer last synced (MnemosyneDB.syncs); entries older than
-- the cooldown are let go here.
-- clock: returns the server time, in seconds.
-- memory: the Memory to hash, pass on and learn into.
-- settings: the saved settings; settings.passOn switches passing on what the
-- memory holds.
-- characters: the Self of this account's characters. What peers say about one
-- of them is neither learned nor passed on (decision 0001), once its player has
-- decided (registered, anonymous or unregistered).
function Sync.new(saved, clock, memory, settings, characters)
	local now = clock()
	for peer, syncedAt in pairs(saved) do
		if now - syncedAt >= Sync.COOLDOWN then
			saved[peer] = nil
		end
	end
	return setmetatable({
		synced = saved,
		clock = clock,
		memory = memory,
		settings = settings,
		characters = characters,
		sessions = {}, -- peer -> { active, answered }
		waiting = {}, -- { peer, heard, digest }, the most recently heard first
	}, Sync)
end

local function send(outgoing, peer, message)
	outgoing[#outgoing + 1] = { peer = peer, text = Protocol.write(message), kind = message.kind }
end

local function running(self)
	local count = 0
	for _ in pairs(self.sessions) do
		count = count + 1
	end
	return count
end

local function isCooling(self, peer, now)
	local syncedAt = self.synced[peer]
	return syncedAt ~= nil and now - syncedAt < Sync.COOLDOWN
end

local function start(self, peer, now, outgoing, digest)
	self.sessions[peer] = { active = now }
	send(outgoing, peer, { kind = "digest", digest = digest or self.memory:digest() })
end

-- Answers a peer's digest: what the peer lacks, then the end of this side's
-- part. Passing on counts toward the cooldown, so a sync cut after it does not
-- pass on the memory again before 6 hours. mine: this side's digest, if made.
local function answer(self, peer, digest, mine, now, outgoing)
	local session = self.sessions[peer]
	session.answered = true
	session.active = now
	self.synced[peer] = now
	if self.settings.passOn then
		local missing = {}
		for _, identity in ipairs(self.memory:missing(digest, mine)) do
			-- A first-hand name is the server's, never checked: one too long would break a batch.
			if #identity.name <= Protocol.MAX_NAME_BYTES and not self.characters:registration(identity.name) then
				missing[#missing + 1] = identity
			end
		end
		for first = 1, #missing, Protocol.MAX_IDENTITIES do
			local batch = { unpack(missing, first, first + Protocol.MAX_IDENTITIES - 1) }
			send(outgoing, peer, { kind = "identities", identities = batch })
		end
	end
	send(outgoing, peer, { kind = "done" })
end

-- Puts a peer in the waiting list, or moves it up, with the digest it sent if
-- any, to answer when its sync starts. Returns whether it is in the list, which
-- keeps the 10 most recently heard.
local function wait(self, peer, heard, digest)
	local waiting = self.waiting
	for i, entry in ipairs(waiting) do
		if entry.peer == peer then
			digest = digest or entry.digest
			table.remove(waiting, i)
			break
		end
	end
	local at = #waiting + 1
	for i, entry in ipairs(waiting) do
		if entry.heard < heard then
			at = i
			break
		end
	end
	if at > Sync.MAX_WAITING then
		return false
	end
	table.insert(waiting, at, { peer = peer, heard = heard, digest = digest })
	waiting[Sync.MAX_WAITING + 1] = nil
	return true
end

-- Starts waiting syncs while there is room.
local function startWaiting(self, now)
	local outgoing = {}
	while self.waiting[1] and running(self) < Sync.MAX_RUNNING do
		local entry = table.remove(self.waiting, 1)
		local peer = entry.peer
		if not self.sessions[peer] and not isCooling(self, peer, now) then
			local mine = self.memory:digest()
			start(self, peer, now, outgoing, mine)
			if entry.digest then
				answer(self, peer, entry.digest, mine, now, outgoing)
			end
		end
	end
	return outgoing
end

-- Asks for a sync with a peer, heard at the time heard (it orders the waiting
-- list). Returns what to send, and whether the sync started or waits.
function Sync:request(peer, heard)
	local now = self.clock()
	if self.sessions[peer] or isCooling(self, peer, now) then
		return {}, false
	end
	if running(self) >= Sync.MAX_RUNNING then
		return {}, wait(self, peer, heard)
	end
	local outgoing = {}
	start(self, peer, now, outgoing)
	return outgoing, true
end

-- Takes a sync message from a peer, read by Protocol: a digest, identities or
-- the end of the peer's part. Returns what to send. Identities count only
-- inside a sync with that peer, after its digest, and are heard second-hand,
-- with the peer as source. A peer asking again during the cooldown is told
-- this side is done, so it waits too.
function Sync:receive(peer, message)
	local now = self.clock()
	local session = self.sessions[peer]
	local outgoing = {}
	if message.kind == "digest" then
		if not session then
			if isCooling(self, peer, now) then
				send(outgoing, peer, { kind = "done" })
			elseif running(self) >= Sync.MAX_RUNNING then
				wait(self, peer, now, message.digest)
			else
				local mine = self.memory:digest()
				start(self, peer, now, outgoing, mine)
				answer(self, peer, message.digest, mine, now, outgoing)
			end
		elseif not session.answered then
			answer(self, peer, message.digest, nil, now, outgoing)
		end
	elseif not session or not session.answered then
		return outgoing
	elseif message.kind == "identities" then
		session.active = now
		for _, identity in ipairs(message.identities) do
			if not self.characters:registration(identity.name) then
				self.memory:hear(identity.name, {
					nickname = identity.nickname,
					revision = identity.revision,
					source = peer,
				})
			end
		end
	elseif message.kind == "done" then
		self.sessions[peer] = nil
		self.synced[peer] = now
		return startWaiting(self, now)
	end
	return outgoing
end

-- Cuts the syncs whose peer went quiet, and starts waiting ones. Returns what
-- to send. Client calls it every few seconds.
function Sync:tick()
	local now = self.clock()
	for peer, session in pairs(self.sessions) do
		if now - session.active >= Sync.TIMEOUT then
			self.sessions[peer] = nil
		end
	end
	return startWaiting(self, now)
end
