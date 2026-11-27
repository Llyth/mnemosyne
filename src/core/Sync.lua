-- Sync: two peers bringing each other's memory up to date (decision 0002).
-- Pure: it takes its saved table, the clock (the server time), the memory and
-- the settings as arguments (decision 0004), and returns what to send; Client
-- sends it by whisper through the paced queue (Outbox).
--
-- Each peer sends its digest, then, once it has the other's, the identities
-- the other lacks or holds at an older revision, then the end of its part. A
-- sync passes on at most what the other keeps in a day from one peer,
-- first-hand changes of the last day first. A sync with a peer happens at most
-- once every 15 minutes with a friend or a guildmate (on this side's lists, as
-- Scope holds them) and once every 6 hours with anyone else; at most 2 run at once
-- (one whose answer is still sent after the peer's done counts)
-- and at most 10 wait, the most recently heard peers first. A sync whose peer
-- passes on nothing new for 2 minutes, or that lasts 20 minutes, is cut; the
-- next one starts again from the digest, and after a cut at 20 minutes, not
-- before 6 hours, even with a friend or guildmate. Whispers can arrive out of order, so a
-- peer's end of its part that comes before its digest still lets this side
-- answer that digest if it comes within 2 minutes.
--
-- Professions (decision 0008) ride on the same sync: each side sends the digest
-- of its professions just before its digest, and passes on what the other
-- lacks after the identities, so a sync cut short has passed on the
-- identities. A digest of professions that comes after the peer's digest
-- (whispers come out of order) is answered when it comes, during the sync, and
-- professions that come after the peer's done, or after the sync was cut (a
-- long run of identities or professions this side holds reaches the 2-minute
-- cut), are still taken for 2 minutes after the peer's last batch, never more
-- than 2 minutes past the sync's 20. A peer that sends no digest of
-- professions (an older one) gets only identities.
-- Progress (decision 0009) rides the same way, after the professions, with a
-- digest of its own sent with theirs, and taken as late: a peer that sends no
-- digest of progress (an older one) gets identities and professions only.
-- A peer whose digest of professions, or of progress, this side never
-- answered syncs once during the cooldown, on either side: peers that synced
-- before they shared them would otherwise wait out the cooldown to pass them
-- on. After that early sync, or once its digest of progress (of professions,
-- on a side without progress) is answered, the cooldown holds, so an older
-- peer gets one early sync only.
-- The cooldowns and early syncs are each character's own: one shared by the
-- account's characters would have one refuse a peer another synced with, which
-- a peer comparing them would read as one account (decision 0001).
local _, ns = ...

local Memory, Protocol = ns.Memory, ns.Protocol

local Sync = {}
Sync.__index = Sync
ns.Sync = Sync

Sync.COOLDOWN_LISTED = 15 * 60 -- seconds between two syncs with the same friend or guildmate
Sync.COOLDOWN = 6 * 60 * 60 -- seconds between two syncs with the same peer outside the lists (a stranger)
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
-- Names an answer looks at before it lets the queue send (lazy): a step
-- costs about a millisecond.
Sync.STEP = 1000

-- What a sync passes on after the identities, in this order: professions
-- (decision 0008), then progress (decision 0009), each with a digest of its
-- own and its own mark among the early syncs (savedEarly).
local CATEGORIES = {
	{ kind = "professions", digest = "professionDigest", mark = "heard", batch = Protocol.batchProfessions },
	{ kind = "progress", digest = "progressDigest", mark = "progress", batch = Protocol.batchProgress },
}
local CATEGORY = {} -- each category by its kind, and by its digest's
for _, category in ipairs(CATEGORIES) do
	CATEGORY[category.kind], CATEGORY[category.digest] = category, category
end
-- The marks of the early syncs, in order: a peer marked below the last
-- category this side shares is owed one early sync.
local RANK = { heard = 1, progress = 2, synced = math.huge }

-- A mark's rank: one a later release wrote (then a downgrade) counts as had.
local function rank(mark)
	return RANK[mark] or (mark and math.huge) or 0
end

-- saved: when each peer last synced, by character of this account
-- (MnemosyneDB.characterSyncs, character -> peer -> time); entries older than the
-- longer cooldown are let go here, and those saved before each character kept
-- its own (a time by peer), which then cool nothing: at most one more sync.
-- clock: returns the server time, in seconds.
-- memory: the character played's Memory to hash, pass on and learn into. What peers say about
-- this account's own characters is learned and passed on as anyone's
-- (decision 0001): a memory that lacked them would name them, bucket by bucket,
-- to a peer comparing digests.
-- settings: the saved settings; settings.passOn switches passing on what the
-- memory holds.
-- professions: the Professions to hash, pass on and learn into; none when left out.
-- progress: the Progress to hash, pass on and learn into; none when left out.
-- early: the peers that can no longer sync during the cooldown, by character
-- of this account (MnemosyneDB.characterEarlySyncs), character -> peer -> "heard" (its
-- digest of professions was answered), "progress" (its digest of progress
-- was) or "synced" (it had its early sync); those saved before each character
-- kept its own (a mark by peer) are let go.
-- playerName: returns the full name of the character played, the one that
-- syncs; nil before login, when nothing syncs.
-- scope: the Scope, which tells friends and guildmates, who sync more often; with none,
-- every peer waits the longer cooldown.
-- lazy: an answer comes as { peer, produce }, which Outbox calls as the
-- queue sends (produce returns the next message, false while it is not
-- ready, nil once done); left out, as its messages, whole.
function Sync.new(saved, clock, memory, settings, professions, progress, early, playerName, scope, lazy)
	local now = clock()
	early = early or {}
	for character, synced in pairs(saved) do
		if type(synced) == "table" then
			for peer, syncedAt in pairs(synced) do
				if now - syncedAt >= Sync.COOLDOWN then
					synced[peer] = nil
				end
			end
		end
		if type(synced) ~= "table" or next(synced) == nil then
			saved[character] = nil
		end
	end
	for character, marks in pairs(early) do
		if type(marks) ~= "table" then
			early[character] = nil
		end
	end
	local held, shared = { professions = professions, progress = progress }, {} -- the categories this side has, in order
	for _, category in ipairs(CATEGORIES) do
		shared[#shared + 1] = held[category.kind] and category or nil
	end
	return setmetatable({
		saved = saved,
		clock = clock,
		memory = memory,
		settings = settings,
		professions = professions,
		progress = progress,
		shared = shared,
		scope = scope,
		savedEarly = early,
		playerName = playerName or function() end,
		lazy = lazy or false,
		-- kind -> peer -> { digest, at }, its digest of professions or progress until answered
		digests = { professions = {}, progress = {} },
		-- peer -> { at, started } of a sync this side answered, ended or cut: its professions and progress still count
		endedAt = {},
		sessions = {}, -- peer -> { started, active, answered, digestAgain, copiesAnswered, producing, pulled }
		answering = {}, -- peer -> the session ended whose answer is still made, holding its place
		overran = {}, -- character -> peer -> true once a sync with it was cut at 20 minutes, for the session
		waiting = {}, -- { peer, heard, digest, digestHeard }, the most recently heard first
		doneFirst = {}, -- peer -> when its done came before its digest, to answer the digest still
	}, Sync)
end

local function send(outgoing, peer, message)
	outgoing[#outgoing + 1] = { peer = peer, text = Protocol.write(message), kind = message.kind }
end

-- Queues a part of an answer that body(emit, step) produces: emit(message)
-- gives one message, step() lets the queue send before it goes on. It
-- produces nothing more once the sync is cut (tick). The session counts its
-- parts still made (producing) and when the queue last asked (pulled): an
-- answer still made after the peer's done keeps its place (finish).
local function produce(self, outgoing, peer, session, body)
	session.producing = (session.producing or 0) + 1
	session.pulled = self.clock()
	local over = false
	local function stop()
		if not over then
			over = true
			session.producing = session.producing - 1
			if session.producing == 0 and self.answering[peer] == session then
				self.answering[peer] = nil
			end
		end
	end
	local co = coroutine.create(function()
		body(function(message)
			coroutine.yield({ peer = peer, text = Protocol.write(message), kind = message.kind })
		end, function()
			coroutine.yield(false)
		end)
	end)
	outgoing[#outgoing + 1] = {
		peer = peer,
		produce = function()
			if session.cut or coroutine.status(co) == "dead" then
				stop()
				return nil
			end
			session.pulled = self.clock()
			local ok, out = coroutine.resume(co)
			if not ok then
				stop()
				error(out, 0)
			elseif out == nil then
				stop()
			end
			return out
		end,
	}
end

-- What to send, each answer whole unless the sync is lazy.
local function whole(self, outgoing)
	if self.lazy then
		return outgoing
	end
	local messages = {}
	for _, out in ipairs(outgoing) do
		if out.produce then
			local message = out.produce()
			while message ~= nil do
				messages[#messages + 1] = message or nil
				message = out.produce()
			end
		else
			messages[#messages + 1] = out
		end
	end
	return messages
end

-- What the character played made, by peer: its syncs (saved) or its early
-- syncs (savedEarly), made on first use.
local function played(self, byCharacter)
	local name = self.playerName() or "" -- nil before login, when nothing syncs
	byCharacter[name] = byCharacter[name] or {}
	return byCharacter[name]
end

local function running(self)
	local count = 0
	for _ in pairs(self.sessions) do
		count = count + 1
	end
	for _ in pairs(self.answering) do
		count = count + 1
	end
	return count
end

local function isCooling(self, peer, now)
	local syncedAt = played(self, self.saved)[peer]
	-- One whose sync ran into the 20-minute cut waits as anyone else: 15 minutes would let it hold a place for good.
	local listed = self.scope and self.scope:isListed(peer) and not played(self, self.overran)[peer]
	return syncedAt ~= nil and now - syncedAt < (listed and Sync.COOLDOWN_LISTED or Sync.COOLDOWN)
end

-- Whether the cooldown keeps a sync with the peer from starting: a peer whose
-- professions, or progress, this side never heard skips it once.
local function refuses(self, peer, now)
	if self.answering[peer] then
		return true -- one sync at a time with a peer, its answer included
	end
	local last = self.shared[#self.shared]
	local owed = last and rank(played(self, self.savedEarly)[peer]) < RANK[last.mark]
	return isCooling(self, peer, now) and not owed
end

local function newSession(now)
	return { started = now, active = now, copiesAnswered = {} }
end

local function start(self, peer, now, outgoing)
	if isCooling(self, peer, now) then
		played(self, self.savedEarly)[peer] = "synced"
	end
	self.sessions[peer] = newSession(now)
	for _, category in ipairs(self.shared) do
		-- This account's professions and progress get their revisions as a sync starts, on either side.
		local copies = self[category.kind]
		copies:prepare()
		send(outgoing, peer, { kind = category.digest, digest = copies:digest(peer) })
	end
	send(outgoing, peer, { kind = "digest", digest = self.memory:digest() })
end

-- Marks a peer's digest of a category answered in this sync: the early sync
-- owed for it is had, never one it had already or one for a later category.
local function answered(self, peer, category)
	self.sessions[peer].copiesAnswered[category.kind] = true
	local early = played(self, self.savedEarly)
	if rank(early[peer]) < RANK[category.mark] then
		early[peer] = category.mark
	end
end

-- Passes on the professions or progress a peer lacks, from its digest of them.
local function passOnCopies(self, category, peer, digest, emit, step)
	for _, batch in ipairs(category.batch(self[category.kind]:answer(peer, digest, step))) do
		emit({ kind = category.kind, [category.kind] = batch })
	end
end

-- Answers a peer's digest of professions or progress, once a sync: what it lacks.
local function answerCopies(self, category, peer, digest, outgoing)
	answered(self, peer, category)
	produce(self, outgoing, peer, self.sessions[peer], function(emit, step)
		passOnCopies(self, category, peer, digest, emit, step)
	end)
end

-- Passes on the identities a peer lacks, from its digest, a step at a time.
local function passOnIdentities(self, digest, now, emit, step)
	local fresh, missing, looked = {}, {}, 0
	local function stepEvery(count)
		if count - looked >= Sync.STEP then
			looked = count
			step()
		end
	end
	-- Hashed now, not at start: the memory may have changed while the peer's digest came.
	local names = self.memory:missing(digest, stepEvery)
	looked = 0
	for i, name in ipairs(names) do
		-- A first-hand name is the server's, never checked: one too long would break a batch.
		if #name <= Protocol.MAX_NAME_BYTES then
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
		stepEvery(i)
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
		emit({ kind = "identities", identities = batch })
	end
end

-- Answers a peer's digest: what the peer lacks, then the end of this side's
-- part. Passing on counts toward the cooldown, so a sync cut after it does not
-- pass on the memory again before 6 hours. The answer is made as the queue
-- sends it (produce), from the memory as it is then, but stops once the sync
-- is cut.
local function answer(self, peer, digest, now, outgoing)
	local session = self.sessions[peer]
	session.answered = true
	session.active = now
	played(self, self.saved)[peer] = now
	local passOn = self.settings.passOn
	local heard = {} -- category -> the peer's digest of it, when it came within 2 minutes
	for _, category in ipairs(self.shared) do
		local held = self.digests[category.kind][peer]
		self.digests[category.kind][peer] = nil
		if held and now - held.at < Sync.TIMEOUT then
			heard[category] = held.digest
			answered(self, peer, category)
		end
	end
	produce(self, outgoing, peer, session, function(emit, step)
		if passOn then
			passOnIdentities(self, digest, now, emit, step)
		end
		for _, category in ipairs(self.shared) do
			if heard[category] then
				passOnCopies(self, category, peer, heard[category], emit, step)
			end
		end
		emit({ kind = "done" })
	end)
end

-- Ends the sync with a peer, however it ends (its done, a late digest
-- answered, the cut): its place is free, unless this side's answer is still
-- made (a peer's done comes when its own part ends: a peer sending its done at
-- once would otherwise free places while its answers still go out, and the
-- queue cuts honest ones past 3), and, once this side answered it, its
-- professions and progress, which come after its identities and may come after its done
-- (whispers come out of order), still count for 2 minutes.
local function finish(self, peer, now, cut)
	local session = self.sessions[peer]
	session.cut = cut
	self.sessions[peer] = nil
	if not cut and (session.producing or 0) > 0 then
		self.answering[peer] = session
	end
	if session.answered then
		self.endedAt[peer] = { at = now, started = session.started }
	end
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
-- list). Returns what to send, and whether the sync started or waits. While
-- paused (combat or lockdown, when nothing would go out), it waits.
function Sync:request(peer, heard, paused)
	local now = self.clock()
	if self.sessions[peer] or refuses(self, peer, now) then
		return {}, false
	end
	if paused or running(self) >= Sync.MAX_RUNNING then
		return {}, wait(self, peer, heard)
	end
	local outgoing = {}
	start(self, peer, now, outgoing)
	return whole(self, outgoing), true
end

-- Takes a sync message from a peer, read by Protocol: a digest (of identities
-- of professions or of progress), identities, professions, progress or the end
-- of the peer's part.
-- Returns what to send, and the identities that changed the memory (the news;
-- professions and progress are never news), marked disputed when they made one
-- disputed. Identities, professions and progress count only inside a sync with that
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
	local category = CATEGORY[message.kind]
	if category and message.kind == category.digest then
		if not self[category.kind] then
			return outgoing
		elseif session and session.answered then
			-- Overtaken by the peer's digest: answered now, once.
			if not session.copiesAnswered[category.kind] then
				answerCopies(self, category, peer, message.digest, outgoing)
			end
		else
			-- Kept until the peer's digest comes: one per peer, let go after 2 minutes (tick).
			self.digests[category.kind][peer] = { digest = message.digest, at = now }
		end
	elseif category then
		local ended = self.endedAt[peer]
		local open = (session and session.answered) or (ended and now - ended.at < Sync.TIMEOUT)
		local copies = self[category.kind]
		if copies and open then
			for _, passed in ipairs(message[category.kind]) do
				if copies:hear(peer, passed) and session then
					session.active = now
				end
			end
			if not session then
				-- Still passing on its part, as for identities below.
				ended.at = math.min(now, ended.started + Sync.MAX_DURATION)
			end
		end
	elseif message.kind == "digest" then
		if not session and self.answering[peer] then
			-- Its answer still goes out: a done would end the peer's sync and waste the rest.
			return outgoing
		elseif not session then
			local doneAt = self.doneFirst[peer]
			self.doneFirst[peer] = nil
			if doneAt and now - doneAt < Sync.TIMEOUT then
				-- Its place was freed at the done: answered at once, not kept running (the
				-- answer still made holds a place, finish).
				self.sessions[peer] = newSession(now)
				answer(self, peer, message.digest, now, outgoing)
				finish(self, peer, now)
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
		local ended = self.endedAt[peer]
		if message.kind == "identities" and ended and now - ended.at < Sync.TIMEOUT then
			-- Still passing on its part, so its professions and progress may come after: 2 minutes
			-- more, but no later than the 20 minutes a sync may last.
			ended.at = math.min(now, ended.started + Sync.MAX_DURATION)
		end
		return outgoing
	elseif message.kind == "identities" and session.answered then
		local learned = {}
		for _, identity in ipairs(message.identities) do
			local changed, how = self.memory:hear(identity.name, {
				nickname = identity.nickname,
				revision = identity.revision,
				source = peer,
				guid = identity.guid,
				vouched = identity.vouched,
			})
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
		end
		finish(self, peer, now)
		played(self, self.saved)[peer] = now
		return whole(self, startWaiting(self, now))
	end
	return whole(self, outgoing)
end

-- A sync cut at 20 minutes while the peer still passed on something new: its
-- cooldown starts now, the longer one even with a friend or guildmate.
local function overrun(self, peer, now)
	played(self, self.overran)[peer] = true
	played(self, self.saved)[peer] = now
end

-- Cuts the syncs whose peer went quiet or that last too long, and starts
-- waiting ones, but not while paused (combat or lockdown: what they send
-- would wait, and starting one costs). Returns what to send. Client calls it
-- every few seconds.
function Sync:tick(paused)
	local now = self.clock()
	for peer, session in pairs(self.sessions) do
		if now - session.active >= Sync.TIMEOUT then
			finish(self, peer, now, true)
		elseif now - session.started >= Sync.MAX_DURATION then
			overrun(self, peer, now)
			finish(self, peer, now, true)
		end
	end
	-- An answer the queue stopped asking for (the peer went offline, the queue was full) is over;
	-- one still going out at 20 minutes is cut as an overrun, or a peer
	-- sending an empty digest at each cooldown would keep a place for good.
	for peer, session in pairs(self.answering) do
		if now - session.pulled >= Sync.TIMEOUT then
			session.cut = true
			self.answering[peer] = nil
		elseif now - session.started >= Sync.MAX_DURATION then
			overrun(self, peer, now)
			session.cut = true
			self.answering[peer] = nil
		end
	end
	for peer, doneAt in pairs(self.doneFirst) do
		if now - doneAt >= Sync.TIMEOUT then
			self.doneFirst[peer] = nil
		end
	end
	for _, digests in pairs(self.digests) do
		for peer, heard in pairs(digests) do
			if now - heard.at >= Sync.TIMEOUT then
				digests[peer] = nil
			end
		end
	end
	for peer, ended in pairs(self.endedAt) do
		if now - ended.at >= Sync.TIMEOUT then
			self.endedAt[peer] = nil
		end
	end
	if paused then
		return {}
	end
	return whole(self, startWaiting(self, now))
end

-- The peers the character played synced with in the last 6 hours, friends
-- and guildmates included, as { peer, at }, the most recent first.
function Sync:recent()
	local now, recent = self.clock(), {}
	for peer, at in pairs(played(self, self.saved)) do
		if now - at < Sync.COOLDOWN then
			recent[#recent + 1] = { peer = peer, at = at }
		end
	end
	table.sort(recent, function(a, b)
		return a.at > b.at
	end)
	return recent
end

-- Forgets when each peer last synced, with every character of this account,
-- so a sync with any peer can start again at once from this side. A peer still
-- in its own cooldown keeps refusing; the early syncs (decision 0008) stay as
-- they are.
function Sync:resetCooldowns()
	-- Emptied in place: it is the saved table (MnemosyneDB.characterSyncs).
	for character in pairs(self.saved) do
		self.saved[character] = nil
	end
end

-- How many peers wait for their sync to start.
function Sync:waitingCount()
	return #self.waiting
end
