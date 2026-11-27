-- News: an identity a sync brought new or at a later revision, posted once to
-- the guild so the whole guild learns a change in seconds (decision 0002), and
-- the news heard from guildmates. Pure: it takes the clock, the randomness,
-- the memory and the settings as arguments (decision 0004); Client posts what
-- it returns on the guild channel.
--
-- Each identity is posted after a random delay of 0 to 30 seconds, and not at
-- all if a guildmate posted it, or a later revision, meanwhile: the guild
-- hears it once. News heard is second-hand, with the guildmate as source, under
-- Memory's rules, and is never posted again; news of this account's own
-- characters too, as anyone's (decision 0001).
local _, ns = ...

local News = {}
News.__index = News
ns.News = News

News.MAX_DELAY = 30 -- seconds
-- Posts waiting at most: a first sync brings a whole memory, mostly what the
-- guild already holds; what does not fit reaches it through syncs.
News.MAX_WAITING = 30

-- clock: returns the time, in seconds.
-- random: as math.random, random(0, MAX_DELAY) a whole number of seconds.
-- memory: the Memory that learned the news, and learns the guild's.
-- settings: the saved settings; settings.passOn switches posting news.
function News.new(clock, random, memory, settings)
	return setmetatable({
		clock = clock,
		random = random,
		memory = memory,
		settings = settings,
		waiting = {}, -- name -> { identity, at }
	}, News)
end

-- Takes an identity a sync brought, that changed the memory: { name,
-- nickname, revision, guid, disputed }, a removal without a nickname. It waits for
-- its delay; one already waiting for that name takes the newer revision and
-- keeps its time.
function News:add(identity)
	-- A dispute is not news (a sync never passes one on), nor what it disputes.
	if identity.disputed then
		self.waiting[identity.name] = nil
		return
	end
	local waiting = self.waiting[identity.name]
	if waiting then
		waiting.identity = identity
		return
	end
	local count = 0
	for _ in pairs(self.waiting) do
		count = count + 1
	end
	if count < News.MAX_WAITING then
		local at = self.clock() + self.random(0, News.MAX_DELAY)
		self.waiting[identity.name] = { identity = identity, at = at }
	end
end

-- Takes guild news a guildmate posted: { name, nickname, revision, guid }.
-- Returns whether the memory learned it; its GUID only fills a missing one. A post of ours for that name is cancelled
-- when the guildmate posted the same identity, or news the memory took (a
-- later revision, or a dispute): news the memory drops (too far ahead, past
-- the guildmate's changes of the day) cancels nothing.
function News:receive(peer, identity)
	local learned = self.memory:hear(identity.name, {
		nickname = identity.nickname,
		revision = identity.revision,
		source = peer,
		guid = identity.guid,
	})
	local waiting = self.waiting[identity.name]
	if
		waiting
		and (
			learned
			or waiting.identity.revision == identity.revision and waiting.identity.nickname == identity.nickname
		)
	then
		self.waiting[identity.name] = nil
	end
	return learned
end

-- The identity to post now, the one due the longest, or nil; each is posted
-- once, and none while passing on is off. Client takes one at a time, when it
-- would send it at once, so a guildmate's post can cancel the others until then.
function News:due()
	local now = self.clock()
	local name, first
	for other, waiting in pairs(self.waiting) do
		if waiting.at <= now and (not first or waiting.at < first.at) then
			name, first = other, waiting
		end
	end
	if not first then
		return nil
	end
	self.waiting[name] = nil
	return self.settings.passOn and first.identity or nil
end
