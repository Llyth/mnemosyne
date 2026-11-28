-- Inbox: where every addon message from a peer comes in, and what it leads to
-- (decision 0004). Pure: it takes the clocks, the pure modules it feeds and
-- what it needs from the game as functions; Client hands it each message the
-- server delivered, once it has checked the message holds no secret value.
--
-- Everything a peer sends is untrusted: it is read only through Protocol, and
-- an identity is stored under the sender the server gives, never a name in
-- the message. Only the guild's channel proves its sender is in scope
-- (decision 0007); sync messages count only by whisper, news only on the
-- guild's channel.
local _, ns = ...

local Protocol = ns.Protocol

local Inbox = {}
Inbox.__index = Inbox
ns.Inbox = Inbox

Inbox.ANSWER_COOLDOWN = 60 -- seconds before answering the same sender again
Inbox.LOGIN_WINDOW, Inbox.LOGIN_SYNCS = 60, 3 -- after login, sync with the first 3 peers answering within a minute

-- The channels of the group: a message there from a peer is a group member's.
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }
-- The kinds of a sync's messages, taken by whisper only.
local SYNC_KINDS = {
	digest = true,
	identities = true,
	done = true,
	professionDigest = true,
	professions = true,
	progressDigest = true,
	progress = true,
}

-- deps, a table of:
-- clock: returns the time, in seconds; serverClock: the server time.
-- memory, sync, news, reader (Protocol.newReader), outbox: the modules fed.
-- wake(): starts sending what the outbox holds.
-- canSend(): whether this account can send addon messages at all.
-- inScope(name): whether Mnemosyne talks with a character (Scope).
-- playerName(): the character played, nil before login.
-- log: Debug (isOn, received, dropped).
-- onNewer(version): tells the player a newer Mnemosyne exists: a newer release,
-- when it gives the version a peer runs, or else a newer protocol.
-- versions: the saved versions of Mnemosyne peers run, by name.
-- version(): this account's version of Mnemosyne (Protocol.releaseVersion),
-- nil in a copy the packager did not build.
-- paused(): whether nothing would go out now (combat or lockdown): a sync
-- asked for waits (Sync:request); never paused when left out.
function Inbox.new(deps)
	return setmetatable({
		clock = deps.clock,
		serverClock = deps.serverClock,
		memory = deps.memory,
		sync = deps.sync,
		news = deps.news,
		reader = deps.reader,
		outbox = deps.outbox,
		wake = deps.wake,
		canSend = deps.canSend,
		inScope = deps.inScope,
		playerName = deps.playerName,
		log = deps.log,
		onNewer = deps.onNewer,
		versions = deps.versions,
		version = deps.version,
		paused = deps.paused or function()
			return false
		end,
		toldVersion = {}, -- peer -> true once whispered this account's version, for the session
		answeredAt = {}, -- sender -> clock() of the last answer, for the session
		heardAt = {}, -- peer -> serverClock() when last heard, for the session
		loginAt = deps.clock(),
		loginSyncs = 0,
		toldNewer = false, -- the notice that a newer Mnemosyne exists, once a session
	}, Inbox)
end

-- Whether release a is later than release b ("1.10.0" after "1.9.0"), by
-- their major, minor and patch numbers.
-- shortcut: ignores a pre-release suffix ("2.0.0-beta.1" ties "2.0.0"), fine while releases have none.
local function laterRelease(a, b)
	local a1, a2, a3 = a:match("^(%d+)%.(%d+)%.(%d+)")
	local b1, b2, b3 = b:match("^(%d+)%.(%d+)%.(%d+)")
	a1, a2, a3, b1, b2, b3 = tonumber(a1), tonumber(a2), tonumber(a3), tonumber(b1), tonumber(b2), tonumber(b3)
	if a1 ~= b1 then
		return a1 > b1
	end
	if a2 ~= b2 then
		return a2 > b2
	end
	return a3 > b3
end

-- Starts the login window: the first peers answering within it get a sync.
function Inbox:loggedIn()
	self.loginAt = self.clock()
end

-- Queues what Sync returned, after everything else.
local function queueSync(self, outgoing)
	if outgoing[1] then
		self.outbox:addSyncs(outgoing)
		self.wake()
	end
end

-- Asks Sync for a sync with a peer. Returns whether it started or waits.
function Inbox:requestSync(peer)
	if not self.canSend() then
		return false
	end
	local outgoing, accepted = self.sync:request(peer, self.heardAt[peer] or self.serverClock(), self.paused())
	queueSync(self, outgoing)
	return accepted
end

-- Starts syncs with the peers heard this session, the most recently heard
-- first (/mnemosyne sync). Returns how many started or wait.
function Inbox:syncAll()
	local peers, heardAt = {}, self.heardAt
	for peer in pairs(heardAt) do
		peers[#peers + 1] = peer
	end
	table.sort(peers, function(a, b)
		return heardAt[a] > heardAt[b]
	end)
	local count = 0
	for _, peer in ipairs(peers) do
		if self:requestSync(peer) then
			count = count + 1
		end
	end
	return count
end

-- How many peers were heard this session.
function Inbox:peerCount()
	local count = 0
	for _ in pairs(self.heardAt) do
		count = count + 1
	end
	return count
end

-- Forgets having heard a peer (the echo peer, once turned off).
function Inbox:forget(peer)
	self.heardAt[peer] = nil
end

-- Takes a message the server delivered from sender on channel (both known).
function Inbox:receive(sender, channel, text)
	local log, playerName = self.log, self.playerName()
	if sender == "" or sender == playerName or not playerName then
		return
	end
	-- Only the guild's channel proves its sender is in scope: elsewhere, a friend or a
	-- guildmate, unless talking with everyone.
	if channel ~= "GUILD" and not self.inScope(sender) then
		log.dropped(sender, "scope", text)
		return
	end
	local message, reason = self.reader:read(sender, text)
	if not message then
		if not reason then
			log.received(sender, channel, text, "chunk") -- more to come
			return
		end
		log.dropped(sender, reason, text)
		if reason == "newer" and not self.toldNewer then
			self.toldNewer = true
			self.onNewer()
		end
		return
	end
	-- The whole message as read, not only its last chunk.
	log.received(sender, channel, log.isOn() and Protocol.write(message) or text, message.kind)
	self.heardAt[sender] = self.serverClock()
	local kind = message.kind
	if SYNC_KINDS[kind] then
		if channel == "WHISPER" then
			local outgoing, learned = self.sync:receive(sender, message)
			queueSync(self, outgoing)
			for _, identity in ipairs(learned or {}) do
				self.news:add(identity)
			end
		else
			log.dropped(sender, "channel", text)
		end
		return
	end
	if kind == "version" then
		self.versions[sender] = message.version
		local own = self.version()
		if own and not self.toldNewer and laterRelease(message.version, own) then
			self.toldNewer = true
			self.onNewer(message.version)
		end
		-- Heard on a channel, the sender may not know this one's: whispered back
		-- once, when this one has a version. Never back to a whisper, so two
		-- peers never loop.
		if
			channel ~= "WHISPER"
			and self.version()
			and not self.toldVersion[sender]
			and self.outbox:add("version", "WHISPER", sender)
		then
			self.toldVersion[sender] = true
			self.wake()
		end
		return
	end
	if kind == "news" then
		if channel ~= "GUILD" then
			log.dropped(sender, "channel", text)
		elseif not self.news:receive(sender, message.identity) then
			log.dropped(sender, "older", text)
		end
		return
	end
	-- Syncs with each new group member who is a peer, and after login with the
	-- first peers answering its asks. A new member asks as it joins; the members
	-- already there only announce themselves as the group grows, so a raid does
	-- not sync each of them with every other one.
	local now = self.clock()
	local afterLogin = now - self.loginAt < Inbox.LOGIN_WINDOW and self.loginSyncs < Inbox.LOGIN_SYNCS
	if GROUP_CHANNELS[channel] and kind == "ask" then
		self:requestSync(sender)
	elseif channel == "WHISPER" and kind ~= "ask" and afterLogin then
		if self:requestSync(sender) then
			self.loginSyncs = self.loginSyncs + 1
		end
	end
	if kind == "ask" then
		if self.answeredAt[sender] and now - self.answeredAt[sender] < Inbox.ANSWER_COOLDOWN then
			log.dropped(sender, "cooldown", text)
			return
		end
		if self.outbox:add("answer", "WHISPER", sender) then
			self.wake()
			self.answeredAt[sender] = now
		else
			log.dropped(sender, "unqueued", text)
		end
	elseif not self.memory:hear(sender, { nickname = message.nickname, revision = message.revision }) then
		log.dropped(sender, "older", text)
	end
end
