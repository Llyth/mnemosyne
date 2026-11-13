-- Sync: two peers bringing each other's memory up to date (decision 0002).
-- Pure: it takes its saved table, the clock (the server time), the memory and
-- the settings as arguments (decision 0004), and returns what to send; Client
-- sends it by whisper through its paced queue.
--
-- Each peer sends its digest, then, once it has the other's, the identities
-- the other lacks or holds at an older revision, then the end of its part. A
-- sync passes on at most what the other keeps in a day from one peer. A
-- sync with a peer happens at most once every 6 hours; at most 2 run at once
-- and at most 10 wait, the most recently heard peers first. A sync whose peer
-- passes on nothing new for 2 minutes, or that lasts 20 minutes, is cut; the
-- next one starts again from the digest.
local _, ns = ...

local Memory, Protocol = ns.Memory, ns.Protocol

local Sync = {}
Sync.__index = Sync
ns.Sync = Sync

Sync.COOLDOWN = 6 * 60 * 60 -- seconds between two syncs with the same peer
Sync.MAX_RUNNING = 2
Sync.MAX_WAITING = 10
Sync.TIMEOUT = 120 -- seconds without anything new from the peer before a sync is cut
-- In an instance whispers go one a second, so two honest syncs can take 8 to 17
-- minutes; the cut is for a peer that drips one new change every 2 minutes or less.
Sync.MAX_DURATION = 20 * 60 -- seconds before a sync is cut, however much the peer passes on

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
		sessions = {}, -- peer -> { started, active, answered, digestAgain }
		waiting = {}, -- { peer, heard, digest, digestHeard }, the most recently heard first
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

local function start(self, peer, now, outgoing)
	self.sessions[peer] = { started = now, active = now }
	send(outgoing, peer, { kind = "digest", digest = self.memory:digest() })
end

-- Answers a peer's digest: what the peer lacks, then the end of this side's
-- part. Passing on counts toward the cooldown, so a sync cut after it does not
-- pass on the memory again before 6 hours.
local function answer(self, peer, digest, now, outgoing)
	local session = self.sessions[peer]
	session.answered = true
	session.active = now
	self.synced[peer] = now
	if self.settings.passOn then
		local missing = {}
		-- Hashed now, not at start: the memory may have changed while the peer's digest came.
		for _, identity in ipairs(self.memory:missing(digest)) do
			-- A first-hand name is the server's, never checked: one too long would break a batch.
			if #identity.name <= Protocol.MAX_NAME_BYTES and not self.characters:registration(identity.name) then
				missing[#missing + 1] = identity
			end
		end
		-- No more than the peer keeps in a day from one peer, from a point that
		-- moves with the clock, so that later syncs pass on the rest.
		local chosen = {}
		for i = 1, math.min(#missing, Memory.MAX_NEW_PER_PEER) do
			chosen[i] = missing[(now + i) % #missing + 1]
		end
		for first = 1, #chosen, Protocol.MAX_IDENTITIES do
			local batch = { unpack(chosen, first, first + Protocol.MAX_IDENTITIES - 1) }
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
	local digestHeard = digest and heard
	for i, entry in ipairs(waiting) do
		if entry.peer == peer then
			if not digest then
				digest, digestHeard = entry.digest, entry.digestHeard
			end
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
	table.insert(waiting, at, { peer = peer, heard = heard, digest = digest, digestHeard = digestHeard })
	waiting[Sync.MAX_WAITING + 1] = nil
	return true
end

-- Starts waiting syncs while there is room. A digest the peer sent is answered
-- only while the peer's own sync still runs; after that, the digest this side
-- sends starts the peer's sync again, and the peer's reply is answered.
local function startWaiting(self, now)
	local outgoing = {}
	while self.waiting[1] and running(self) < Sync.MAX_RUNNING do
		local entry = table.remove(self.waiting, 1)
		local peer = entry.peer
		if not self.sessions[peer] and not isCooling(self, peer, now) then
			start(self, peer, now, outgoing)
			if entry.digest and now - entry.digestHeard < Sync.TIMEOUT then
				answer(self, peer, entry.digest, now, outgoing)
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
-- with the peer as source; only one that changes the memory keeps the sync
-- going. A second digest in a sync this side already answered (a peer that
-- reloaded, or cut its sync before the answer came) gets only this side's
-- digest, so the peer can answer and end its sync: the answer is not sent
-- again, and what the peer lacks comes in a later sync. A peer this side will
-- not answer (sending its digest again during the cooldown, a third time in the
-- same sync, or with the waiting list full) is told this side is done, which
-- ends the peer's sync and starts its cooldown.
function Sync:receive(peer, message)
	local now = self.clock()
	local session = self.sessions[peer]
	local outgoing = {}
	if message.kind == "digest" then
		if not session then
			if isCooling(self, peer, now) then
				send(outgoing, peer, { kind = "done" })
			elseif running(self) >= Sync.MAX_RUNNING then
				if not wait(self, peer, now, message.digest) then
					send(outgoing, peer, { kind = "done" })
				end
			else
				start(self, peer, now, outgoing)
				answer(self, peer, message.digest, now, outgoing)
			end
		elseif session.digestAgain then
			send(outgoing, peer, { kind = "done" })
		elseif session.answered then
			-- Not the answer again: the peer has most often dropped it, and it fills the paced queue.
			session.digestAgain = true
			send(outgoing, peer, { kind = "digest", digest = self.memory:digest() })
		else
			answer(self, peer, message.digest, now, outgoing)
		end
	elseif not session then
		return outgoing
	elseif message.kind == "identities" and session.answered then
		for _, identity in ipairs(message.identities) do
			if
				not self.characters:registration(identity.name)
				and self.memory:hear(identity.name, {
					nickname = identity.nickname,
					revision = identity.revision,
					source = peer,
				})
			then
				-- Only what is new: a peer re-sending what this side knows would hold a place forever.
				session.active = now
			end
		end
	elseif message.kind == "done" then
		self.sessions[peer] = nil
		self.synced[peer] = now
		return startWaiting(self, now)
	end
	return outgoing
end

-- Cuts the syncs whose peer went quiet or that last too long, and starts
-- waiting ones. Returns what to send. Client calls it every few seconds.
function Sync:tick()
	local now = self.clock()
	for peer, session in pairs(self.sessions) do
		if now - session.active >= Sync.TIMEOUT or now - session.started >= Sync.MAX_DURATION then
			self.sessions[peer] = nil
		end
	end
	return startWaiting(self, now)
end
