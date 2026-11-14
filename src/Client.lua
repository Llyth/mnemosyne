-- Client: the adapter that faces the game for data and messages (decision
-- 0004): the saved variables, the events, the paced queue and the addon
-- messages. The rules live in the pure modules; this file only wires them to
-- the WoW API (docs/agents/wow-api.md).
local addonName, ns = ...

local Protocol = ns.Protocol
local Debug = ns.Debug
local L = ns.L

local Client = {}
ns.Client = Client

local SCHEMA = 1
local ANSWER_COOLDOWN = 60 -- seconds before answering the same sender again
local BURST, REFILL = 10, 1 -- the client's allowance per prefix: 10 messages, then 1 per second
local TICK = 0.25 -- seconds between two looks at the queue
local MAX_ANSWERS = 20 -- once this many jobs wait, an ask is dropped, not answered
local BYTES_PER_SECOND = 1000 -- the paced queue's pace, all messages together (decision 0002)
local SYNC_TICK = 5 -- seconds between two looks at the syncs (cut, start waiting ones)
local NEWS_TICK = 1 -- seconds between two looks at the news due
local LOGIN_WINDOW, LOGIN_SYNCS = 60, 3 -- after login, sync with the first 3 peers answering within a minute
-- Chunks the sync queue holds at most, about a whole memory's worth: what comes
-- beyond is dropped, so peers asking for syncs one after another cannot grow it.
local MAX_SYNC_CHUNKS = 4000

-- The channels of the group: a message there from a peer is a group member's.
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- Results that mean "not now": the job stays at the head of the queue.
local RETRY = {
	[Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
	[Enum.SendAddonMessageResult.ChannelThrottle] = true,
	[Enum.SendAddonMessageResult.AddOnMessageLockdown] = true,
}

local playerName
local queue, waiting = {}, {} -- jobs in order, and the keys of those in it
local syncQueue = {} -- sync messages, sent once the queue is empty: { text, target, kind }
local syncSends, servedAt = 0, {} -- sync messages sent, and the count when each peer was last sent one
local tokens, bytes, refilledAt = BURST, BYTES_PER_SECOND, 0
local ticker
local answeredAt = {} -- sender -> GetTime() of the last answer, for the session
local groupSize, inGuild = 0, false
local reader -- puts chunked messages back together
local peersHeard = {} -- peer -> GetServerTime() when last heard, for the session
local loginAt, loginSyncs = 0, 0
local toldNewer = false -- the notice that a newer Mnemosyne exists, once a session

-- The echo peer (/mnemosyne echo): a made-up peer that sends back, under its
-- name, what this character whispers to it or broadcasts, so one player alone
-- can test the receiving side. For the session only.
Client.ECHO = "Echo Mnemosyne"
local echoing = false
local loopBack -- handlers.CHAT_MSG_ADDON, once defined

-- A value read from the game that addon code can use: present and not secret.
-- A secret value counts as unknown (comparing one raises an error).
function Client.isKnown(value)
	return value ~= nil and not issecretvalue(value)
end

-- The full name of the character being played, "First Last", once logged in.
function Client.playerName()
	return playerName
end

-- Whether this account can send addon messages here at all: never on a trial
-- account. C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() is not asked: on
-- Forever it is true on a realm where addon messages do go out (checked in the
-- game, see docs/agents/wow-api.md).
function Client.canSend()
	return not (IsTrialAccount() or IsVeteranTrialAccount())
end

local function isRegistered()
	return ns.characters:state(playerName) == "registered"
end

-- The group's channel: the instance group's, or the raid's, or the party's.
local function groupChannel()
	local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
	if channel and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
		channel = "INSTANCE_CHAT"
	end
	return channel
end

-- Builds a job's message when it is sent, from the registration as it is then:
-- a job that waited through a lockdown carries the latest nickname, or the
-- removal if the character unregistered meanwhile (Self:message). Returns
-- nothing to drop the job.
local function compose(job)
	if job.text then
		return job.text, "WHISPER", job.target, job.kind
	elseif job.news then
		return Protocol.write({ kind = "news", identity = job.news }), "GUILD", nil, "news"
	end
	local message = ns.characters:message(playerName, job.kind)
	if not message then
		return
	end
	local chatType = job.channel
	if chatType == "GROUP" then
		-- A group's channel reaches strangers: only while talking with everyone.
		chatType = MnemosyneDB.settings.everyone and groupChannel() or nil
	elseif chatType == "GUILD" and not IsInGuild() then
		chatType = nil
	end
	if chatType then
		return Protocol.write(message), chatType, job.target, message.kind
	end
end

-- In combat or in lockdown: no addon message would go out.
function Client.isPaused()
	return InCombatLockdown() or C_ChatInfo.InChatMessagingLockdown()
end

-- Sends what the allowance permits, oldest job first and syncs last, about
-- 1 KB a second in all, unless in combat or in lockdown; stops ticking once
-- both queues are empty. Whispers outside instances are exempt from the
-- per-prefix allowance (decision 0002), so answers and syncs spend no token.
local function flush()
	local now = GetTime()
	tokens = math.min(BURST, tokens + (now - refilledAt) * REFILL)
	bytes = math.min(BYTES_PER_SECOND, bytes + (now - refilledAt) * BYTES_PER_SECOND)
	refilledAt = now
	while (queue[1] or syncQueue[1]) and not Client.isPaused() do
		local jobs, at = queue, 1
		if not queue[1] then
			-- Syncs take turns, the peer served longest ago first, so each keeps
			-- hearing from its sync and none times out.
			jobs = syncQueue
			local oldest
			for i, job in ipairs(syncQueue) do
				local served = servedAt[job.target] or 0
				if not oldest or served < oldest then
					at, oldest = i, served
				end
			end
		end
		local job = jobs[at]
		local text, chatType, target, kind = compose(job)
		if text then
			local costs = chatType ~= "WHISPER" or IsInInstance()
			if (costs and tokens < 1) or bytes < #text then
				return
			end
			local result
			if echoing and target == Client.ECHO then
				result = Enum.SendAddonMessageResult.Success -- no such character: never sent
			else
				result = C_ChatInfo.SendAddonMessage(Protocol.PREFIX, text, chatType, target)
			end
			Debug.sent(text, chatType, target, result, kind)
			if
				echoing
				and result == Enum.SendAddonMessageResult.Success
				and (target == Client.ECHO or chatType ~= "WHISPER")
			then
				C_Timer.After(0, function()
					loopBack(Protocol.PREFIX, text, chatType, Client.ECHO)
				end)
			end
			if RETRY[result] then
				tokens = 0
				return
			end
			if costs then
				tokens = tokens - 1
			end
			bytes = bytes - #text
			if job.text then
				syncSends = syncSends + 1
				servedAt[target] = syncSends
			end
			if job.text and result ~= Enum.SendAddonMessageResult.Success then
				-- The peer cannot get it (offline): the rest of its sync, this one
				-- included, would go nowhere.
				local kept = {}
				for _, other in ipairs(syncQueue) do
					if other.target ~= target then
						kept[#kept + 1] = other
					end
				end
				syncQueue, at = kept, nil
			end
		end
		if at then
			table.remove(jobs, at)
		end
		if job.key then
			waiting[job.key] = nil
		end
	end
	if not queue[1] and not syncQueue[1] and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function wake()
	if not ticker then
		ticker = C_Timer.NewTicker(TICK, flush)
	end
end

-- Queues a job once: a job already waiting (one announcement per channel, one
-- answer per sender) is not queued twice. Returns true when it queued the job.
local function enqueue(kind, channel, target)
	if not Client.canSend() then
		return false
	end
	local key = kind .. ":" .. channel .. ":" .. (target or "")
	if waiting[key] or (kind == "answer" and #queue >= MAX_ANSWERS) then
		return false
	end
	waiting[key] = true
	queue[#queue + 1] = { key = key, kind = kind, channel = channel, target = target }
	wake()
	return true
end

-- Queues what Sync returned, each message as its chunks, after everything else.
-- A sync that does not fit is cut from the first message that does not fit:
-- the peer stops hearing it and lets it go.
local function sendSync(outgoing)
	if not Client.canSend() then
		return
	end
	local cut = {}
	for _, out in ipairs(outgoing) do
		local chunks = Protocol.split(out.text)
		if cut[out.peer] or #syncQueue + #chunks > MAX_SYNC_CHUNKS then
			cut[out.peer] = true
		else
			for i, text in ipairs(chunks) do
				-- The kind, for the debug log: the message's on its first chunk.
				syncQueue[#syncQueue + 1] = { text = text, target = out.peer, kind = i == 1 and out.kind or "chunk" }
			end
		end
	end
	if syncQueue[1] then
		wake()
	end
end

-- Queues one news due, to the guild if any, once the queue is empty: until
-- then, and in combat or in lockdown, news waits in News, where a guildmate's
-- post can still cancel it.
local function postNews()
	if Client.isPaused() or queue[1] then
		return
	end
	local identity = ns.news:due()
	if identity and Client.canSend() and IsInGuild() then
		queue[1] = { news = identity }
		wake()
	end
end

-- Asks Sync for a sync with a peer. Returns whether it started or waits.
local function requestSync(peer)
	if not Client.canSend() then
		return false
	end
	local outgoing, accepted = ns.sync:request(peer, peersHeard[peer] or GetServerTime())
	sendSync(outgoing)
	return accepted
end

-- Starts syncs with the peers heard this session, the most recently heard
-- first (/mnemosyne sync). Returns how many started or wait.
function Client.sync()
	local peers = {}
	for peer in pairs(peersHeard) do
		peers[#peers + 1] = peer
	end
	table.sort(peers, function(a, b)
		return peersHeard[a] > peersHeard[b]
	end)
	local count = 0
	for _, peer in ipairs(peers) do
		if requestSync(peer) then
			count = count + 1
		end
	end
	return count
end

-- How many peers were heard this session.
function Client.peerCount()
	local count = 0
	for _ in pairs(peersHeard) do
		count = count + 1
	end
	return count
end

-- Tells the guild and the group the character's registration has changed: its
-- nickname, its removal or that it is anonymous; with ask, also asks who the
-- others are.
function Client.announce(ask)
	for _, channel in ipairs({ "GUILD", "GROUP" }) do
		enqueue("announce", channel)
		if ask then
			enqueue("ask", channel)
		end
	end
end

-- Asks one character, by addon whisper, who plays it. Returns true when it
-- queued the ask.
function Client.ask(name)
	return enqueue("ask", "WHISPER", name)
end

-- Reads the friends and guildmates again on the next look (Client.inScope).
local scopeRead = false

local function readScope()
	local scope, isKnown = ns.scope, Client.isKnown
	scope:reset()
	-- On Forever a friend added by character name is listed with the Battle.net
	-- friends too: C_FriendList stays empty (docs/agents/wow-api.md).
	for i = 1, BNGetNumFriends() do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
			local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if account and account.clientProgram == BNET_CLIENT_WOW and isKnown(account.characterName) then
				scope:add(account.characterName)
			end
		end
	end
	for i = 1, GetNumGuildMembers() do
		local name = GetGuildRosterInfo(i)
		if isKnown(name) then
			scope:add(name)
		end
	end
	scopeRead = true
end

-- Whether Mnemosyne talks with a character (Scope): a friend or a guildmate,
-- or anyone while "Talk with everyone" is on. The echo peer always.
function Client.inScope(name)
	if name == Client.ECHO then
		return true
	end
	if not scopeRead then
		readScope()
	end
	return ns.scope:allows(name)
end

local function listsChanged()
	scopeRead = false
end

-- Drops what the echo peer left in the memory, so it never reaches a real peer.
local function forgetEcho()
	if ns.memory:knows(Client.ECHO) then
		ns.memory:forget(Client.ECHO)
		ns.memory:unforget(Client.ECHO)
	end
	peersHeard[Client.ECHO] = nil
end

-- Turns the echo peer on and asks it who plays it, or off and forgets it.
-- Returns whether it is on.
function Client.toggleEcho()
	echoing = not echoing
	if echoing then
		Client.ask(Client.ECHO)
	else
		forgetEcho()
	end
	return echoing
end

-- The settings and their defaults, all on: the switches of the settings panel.
local DEFAULTS = {
	tooltip = true, -- tooltip recognition
	chat = true, -- chat recognition
	showSecondHand = true, -- "Show second-hand"
	passOn = true, -- "Pass on what I know"
	askStrangers = true, -- "Ask strangers"
	everyone = false, -- "Talk with everyone": off, only friends and guildmates (decision 0007)
	offerReport = true, -- offer the debug report after an error
}
Client.DEFAULTS = DEFAULTS

local frame = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	frame:UnregisterEvent("ADDON_LOADED")
	-- Some Forever builds do not restore saved variables: initialize every field.
	if type(MnemosyneDB) ~= "table" then
		MnemosyneDB = {}
	end
	local db = MnemosyneDB
	db.schema = db.schema or SCHEMA
	db.memory = db.memory or {}
	db.characters = db.characters or {}
	db.debug = db.debug == true
	db.forgotten = db.forgotten or {}
	ns.memory = ns.Memory.new(db.memory, GetServerTime, db.forgotten)
	ns.characters = ns.Self.new(db.characters, GetServerTime)
	db.settings = db.settings or {}
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then
			db.settings[key] = value
		end
	end
	db.asked = db.asked or {}
	db.syncs = db.syncs or {}
	ns.sync = ns.Sync.new(db.syncs, GetServerTime, ns.memory, db.settings, ns.characters)
	ns.news = ns.News.new(GetTime, math.random, ns.memory, ns.characters, db.settings)
	reader = Protocol.newReader(GetTime)
	ns.scope = ns.Scope.new(db.settings)
	ns.recognition = ns.Recognition.new(ns.memory, db.settings, ns.L, GetServerTime, ns.characters)
	-- The debug report (src/Report.lua): its events, the caught errors, and
	-- whether to offer it after an error.
	db.events = db.events or {}
	db.errors = db.errors or {}
	C_ChatInfo.RegisterAddonMessagePrefix(Protocol.PREFIX)
	for event in pairs(handlers) do
		if event ~= "ADDON_LOADED" then
			frame:RegisterEvent(event)
		end
	end
end

function handlers.PLAYER_LOGIN()
	playerName = GetUnitName("player")
	forgetEcho() -- left by a session that ended with the echo peer on
	groupSize = GetNumGroupMembers()
	inGuild = IsInGuild()
	loginAt = GetTime()
	C_Timer.NewTicker(SYNC_TICK, function()
		sendSync(ns.sync:tick())
	end)
	C_Timer.NewTicker(NEWS_TICK, postNews)
	for _, channel in ipairs({ "GUILD", "GROUP" }) do
		if isRegistered() then
			enqueue("announce", channel)
		end
		enqueue("ask", channel)
	end
	-- Asks the server for the guild roster (GUILD_ROSTER_UPDATE), for the scope;
	-- last, and only where the client has it, so the rest of the login runs.
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	end
end

-- When the group grows, a registered character announces itself. It asks only
-- when it joins a group itself: a character that joins asks on its own, so
-- the members already there do not all ask again as a raid fills.
function handlers.GROUP_ROSTER_UPDATE()
	local size = GetNumGroupMembers()
	if size > groupSize then
		if isRegistered() then
			enqueue("announce", "GROUP")
		end
		if groupSize == 0 then
			enqueue("ask", "GROUP")
		end
	end
	groupSize = size
end

-- On joining a guild (also when the guild is known only after login), a
-- registered character announces itself, and every character asks.
function handlers.PLAYER_GUILD_UPDATE()
	local nowInGuild = IsInGuild()
	if nowInGuild and not inGuild then
		if isRegistered() then
			enqueue("announce", "GUILD")
		end
		enqueue("ask", "GUILD")
	end
	inGuild = nowInGuild
end

handlers.BN_FRIEND_INFO_CHANGED = listsChanged
handlers.GUILD_ROSTER_UPDATE = listsChanged

-- Everything a peer sends is untrusted: it is read only through Protocol, and
-- an identity is stored under the sender the server gives, never a name in
-- the message.
function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
	local isKnown = Client.isKnown
	if not isKnown(prefix) or prefix ~= Protocol.PREFIX then
		return
	end
	if not (isKnown(text) and isKnown(sender) and isKnown(channel)) then
		Debug.dropped(nil, "secret", "?")
		return
	end
	if sender == "" or sender == playerName or not playerName then
		return
	end
	-- Only the guild's channel vouches for its sender: elsewhere, a friend or a
	-- guildmate, unless talking with everyone.
	if channel ~= "GUILD" and not Client.inScope(sender) then
		Debug.dropped(sender, "scope", text)
		return
	end
	local message, reason = reader:read(sender, text)
	if not message then
		if not reason then
			Debug.received(sender, channel, text, "chunk") -- more to come
			return
		end
		Debug.dropped(sender, reason, text)
		if reason == "newer" and not toldNewer then
			toldNewer = true
			ns.say(L.NEWER_VERSION)
		end
		return
	end
	-- The whole message as read, not only its last chunk.
	Debug.received(sender, channel, Debug.isOn() and Protocol.write(message) or text, message.kind)
	peersHeard[sender] = GetServerTime()
	local kind = message.kind
	if kind == "digest" or kind == "identities" or kind == "done" then
		if channel == "WHISPER" then
			local outgoing, learned = ns.sync:receive(sender, message)
			sendSync(outgoing)
			for _, identity in ipairs(learned or {}) do
				ns.news:add(identity)
			end
		else
			Debug.dropped(sender, "channel", text)
		end
		return
	end
	if kind == "news" then
		if channel ~= "GUILD" then
			Debug.dropped(sender, "channel", text)
		elseif not ns.news:receive(sender, message.identity) then
			Debug.dropped(sender, "older", text)
		end
		return
	end
	-- Syncs with each new group member who is a peer, and after login with the
	-- first peers answering its asks.
	local afterLogin = GetTime() - loginAt < LOGIN_WINDOW and loginSyncs < LOGIN_SYNCS
	if GROUP_CHANNELS[channel] then
		requestSync(sender)
	elseif channel == "WHISPER" and kind ~= "ask" and afterLogin then
		if requestSync(sender) then
			loginSyncs = loginSyncs + 1
		end
	end
	if kind == "ask" then
		local now = GetTime()
		if answeredAt[sender] and now - answeredAt[sender] < ANSWER_COOLDOWN then
			Debug.dropped(sender, "cooldown", text)
			return
		end
		if enqueue("answer", "WHISPER", sender) then
			answeredAt[sender] = now
		else
			Debug.dropped(sender, "unqueued", text)
		end
	elseif not ns.memory:hear(sender, { nickname = message.nickname, revision = message.revision }) then
		Debug.dropped(sender, "older", text)
	end
end

loopBack = handlers.CHAT_MSG_ADDON

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
frame:RegisterEvent("ADDON_LOADED")
