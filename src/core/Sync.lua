-- Sync: two peers bringing each other's memory up to date (decision 0002).
-- Pure: it takes its saved table, the clock (the server time), the memory and
-- the settings as arguments (decision 0004), and returns what to send; Client
-- sends it by whisper through the paced queue (Outbox).
--
-- Each peer sends its digest, then, once it has the other's, the identities
-- the other lacks or holds at an older revision, then the end of its part. A
-- sync passes on at most what the other keeps in a day from one peer,
-- first-hand changes of the last day first. A
-- sync with a peer happens at most once every 6 hours; at most 2 run at once
-- and at most 10 wait, the most recently heard peers first. A sync whose peer
-- passes on nothing new for 2 minutes, or that lasts 20 minutes, is cut; the
-- next one starts again from the digest. Whispers can arrive out of order, so a
-- peer's end of its part that comes before its digest still lets this side
-- answer that digest if it comes within 2 minutes.
--
-- Professions (decision 0008) ride on the same sync: each side sends the digest
-- of its professions just before its digest, and passes on what the other
-- lacks after the identities, so a sync cut short has passed on the
-- identities. A digest of professions that comes after the peer's digest
-- (whispers come out of order) is answered when it comes, during the sync, and
-- professions that come after the peer's done are still taken for 2 minutes. A
-- peer that sends no digest of professions (an older one) gets only identities.
-- A peer whose digest of professions this side never answered syncs once
-- during the cooldown, on either side: peers that synced before they shared
-- professions would otherwise wait 6 hours to pass them on. After that early
-- sync, or once its digest of professions is answered, the cooldown holds, so
-- an older peer gets one early sync only.
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
-- A first-hand change this recent (its revision, never ahead of the clock) is
-- passed on before the rest, vouched; older first-hand identities take turns
-- with second-hand ones, so the copies a peer already holds do not crowd out
-- what it lacks. An hour short of the window the peer takes vouched changes in,
-- so one sent last in a long sync still reaches it inside it.
Sync.FRESH = Memory.VOUCHED_WINDOW - 60 * 60 -- seconds

-- saved: when each peer last synced (MnemosyneDB.syncs); entries older than
-- the cooldown are let go here.
-- clock: returns the server time, in seconds.
-- memory: the Memory to hash, pass on and learn into.
-- settings: the saved settings; settings.passOn switches passing on what the
-- memory holds.
-- characters: the Self of this account's characters. What peers say about one
-- of them is neither learned nor passed on (decision 0001), once its player has
-- decided (registered, anonymous or unregistered).
-- professions: the Professions to hash, pass on and learn into; none when left out.
-- early: the peers that can no longer sync during the cooldown
-- (MnemosyneDB.earlySyncs), peer -> "heard" (its digest of professions was
-- answered) or "synced" (it had its early sync).
function Sync.new(saved, clock, memory, settings, characters, professions, early)
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
		professions = professions,
		early = early or {},
		professionDigests = {}, -- peer -> { digest, at }, its digest of professions until answered
		endedAt = {}, -- peer -> when a sync this side answered ended at its done: its professions still count
		sessions = {}, -- peer -> { started, active, answered, digestAgain }
		waiting = {}, -- { peer, heard, digest, digestHeard }, the most recently heard first
		doneFirst = {}, -- peer -> when its done came before its digest, to answer the digest still
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

-- Whether the cooldown keeps a sync with the peer from starting: a peer whose
-- professions this side never heard skips it once.
local function refuses(self, peer, now)
	return isCooling(self, peer, now) and (not self.professions or self.early[peer] ~= nil)
end

local function start(self, peer, now, outgoing)
	if isCooling(self, peer, now) then
		self.early[peer] = "synced"
	end
	self.sessions[peer] = { started = now, active = now }
	if self.professions then
		-- This account's professions get their revisions as a sync starts, on either side.
		self.professions:prepare()
		send(outgoing, peer, { kind = "professionDigest", digest = self.professions:digest(peer) })
	end
	send(outgoing, peer, { kind = "digest", digest = self.memory:digest() })
end

-- Answers a peer's digest of professions, once a sync: the professions it lacks.
local function answerProfessions(self, peer, digest, outgoing)
	self.sessions[peer].professionsAnswered = true
	self.early[peer] = "heard"
	for _, batch in ipairs(Protocol.batchProfessions(self.professions:answer(peer, digest))) do
		send(outgoing, peer, { kind = "professions", professions = batch })
	end
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
		local fresh, missing = {}, {}
		-- Hashed now, not at start: the memory may have changed while the peer's digest came.
		for _, name in ipairs(self.memory:missing(digest)) do
			-- A first-hand name is the server's, never checked: one too long would break a batch.
			if #name <= Protocol.MAX_NAME_BYTES and not self.characters:registration(name) then
				local identity = self.memory:knows(name) and self.memory:passOn(name)
				-- Not one ahead of the clock: no real change is, and the peer would not take it as vouched.
				if identity and identity.revision <= now and now - identity.revision <= Sync.FRESH then
					-- The peer takes up to 5,000 of these a day from one peer, besides its 1,000.
					identity.vouched = true
					fresh[#fresh + 1] = identity
				else
					missing[#missing + 1] = name
				end
			end
		end
		-- First-hand changes of the last day first, the latest first, so a sync
		-- cut short has passed on what the characters said of themselves lately.
		table.sort(fresh, function(a, b)
			return a.revision > b.revision
		end)
		local chosen = {}
		for i, identity in ipairs(fresh) do
			if i <= Memory.MAX_VOUCHED_PER_PEER then
				chosen[i] = identity
			else
				missing[#missing + 1] = identity.name -- past the 5,000: takes turns with the rest, not vouched
			end
		end
		-- Then the rest, no more than the peer keeps in a day from one peer,
		-- from a point that moves with the clock, so later syncs pass on the rest.
		for i = 1, math.min(#missing, Memory.MAX_CHANGES_PER_PEER) do
			-- Appended: a nil from passOn would leave a hole that ends the batches there.
			chosen[#chosen + 1] = self.memory:passOn(missing[(now + i) % #missing + 1])
		end
		for _, batch in ipairs(Protocol.batch(chosen)) do
			send(outgoing, peer, { kind = "identities", identities = batch })
		end
	end
	local heard = self.professionDigests[peer]
	self.professionDigests[peer] = nil
	if self.professions and heard and now - heard.at < Sync.TIMEOUT then
		answerProfessions(self, peer, heard.digest, outgoing)
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
		if not self.sessions[peer] and not refuses(self, peer, now) then
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
	if self.sessions[peer] or refuses(self, peer, now) then
		return {}, false
	end
	if running(self) >= Sync.MAX_RUNNING then
		return {}, wait(self, peer, heard)
	end
	local outgoing = {}
	start(self, peer, now, outgoing)
	return outgoing, true
end

-- Takes a sync message from a peer, read by Protocol: a digest (of identities
-- or of professions), identities, professions or the end of the peer's part.
-- Returns what to send, and the identities that changed the memory (the news;
-- professions are never news), marked disputed when they made one
-- disputed. Identities and professions count only inside a sync with that
-- peer, after its digest, and are heard second-hand, with the peer as source;
-- only one that changes the memory keeps the sync going. A second digest in a
-- sync this side already answered (a peer that reloaded, or cut its sync
-- before the answer came) gets only this side's
-- digest, so the peer can answer and end its sync: the answer is not sent
-- again, and what the peer lacks comes in a later sync. A done before this side
-- answered ends the sync and starts the cooldown all the same (the peer may be
-- refusing), but the peer's digest, if it comes within 2 minutes (it was
-- overtaken), is still answered once. A peer this side will
-- not answer (sending its digest again during the cooldown, a third time in the
-- same sync, or with the waiting list full) is told this side is done, which
-- ends the peer's sync and starts its cooldown.
function Sync:receive(peer, message)
	local now = self.clock()
	local session = self.sessions[peer]
	local outgoing = {}
	if message.kind == "professionDigest" then
		if not self.professions then
			return outgoing
		elseif session and session.answered then
			-- Overtaken by the peer's digest: answered now, once.
			if not session.professionsAnswered then
				answerProfessions(self, peer, message.digest, outgoing)
			end
		else
			-- Kept until the peer's digest comes: one per peer, let go after 2 minutes (tick).
			self.professionDigests[peer] = { digest = message.digest, at = now }
		end
	elseif message.kind == "professions" then
		local endedAt = self.endedAt[peer]
		local open = (session and session.answered) or (endedAt and now - endedAt < Sync.TIMEOUT)
		if self.professions and open then
			for _, profession in ipairs(message.professions) do
				if self.professions:hear(peer, profession) and session then
					session.active = now
				end
			end
		end
	elseif message.kind == "digest" then
		if not session then
			local doneAt = self.doneFirst[peer]
			self.doneFirst[peer] = nil
			if doneAt and now - doneAt < Sync.TIMEOUT then
				-- Its place was freed at the done: answered at once, not kept running.
				self.sessions[peer] = { started = now, active = now }
				answer(self, peer, message.digest, now, outgoing)
				self.sessions[peer] = nil
			elseif refuses(self, peer, now) then
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
		local learned = {}
		for _, identity in ipairs(message.identities) do
			local changed, how
			if not self.characters:registration(identity.name) then
				changed, how = self.memory:hear(identity.name, {
					nickname = identity.nickname,
					revision = identity.revision,
					source = peer,
					guid = identity.guid,
					vouched = identity.vouched,
				})
			end
			if changed then
				-- Only what is new: a peer re-sending what this side knows would hold a place forever.
				session.active = now
				-- What the memory holds now, not what the peer sent: it keeps the GUID it held.
				learned[#learned + 1] = how == "disputed" and { name = identity.name, disputed = true }
					or self.memory:passOn(identity.name)
			end
		end
		return outgoing, learned
	elseif message.kind == "done" then
		if not session.answered then
			self.doneFirst[peer] = now
		else
			-- Its professions may still come after its done (whispers come out of order).
			self.endedAt[peer] = now
		end
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
	for peer, doneAt in pairs(self.doneFirst) do
		if now - doneAt >= Sync.TIMEOUT then
			self.doneFirst[peer] = nil
		end
	end
	for peer, heard in pairs(self.professionDigests) do
		if now - heard.at >= Sync.TIMEOUT then
			self.professionDigests[peer] = nil
		end
	end
	for peer, endedAt in pairs(self.endedAt) do
		if now - endedAt >= Sync.TIMEOUT then
			self.endedAt[peer] = nil
		end
	end
	return startWaiting(self, now)
end

-- The peers synced in the last 6 hours, as { peer, at }, the most recent first.
function Sync:recent()
	local now, recent = self.clock(), {}
	for peer, at in pairs(self.synced) do
		if isCooling(self, peer, now) then
			recent[#recent + 1] = { peer = peer, at = at }
		end
	end
	table.sort(recent, function(a, b)
		return a.at > b.at
	end)
	return recent
end

-- How many peers wait for their sync to start.
function Sync:waitingCount()
	return #self.waiting
end
