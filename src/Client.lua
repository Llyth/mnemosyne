-- Client: the adapter that faces the game for data and messages (decision
-- 0004): the saved variables, the events, the paced queue and the addon
-- messages. The rules live in the pure modules; this file only wires them to
-- the WoW API (docs/agents/wow-api.md).
local addonName, ns = ...

local Protocol = ns.Protocol
local Debug = ns.Debug

local Client = {}
ns.Client = Client

local SCHEMA = 1
local ANSWER_COOLDOWN = 60 -- seconds before answering the same sender again
local BURST, REFILL = 10, 1 -- the client's allowance per prefix: 10 messages, then 1 per second
local TICK = 0.25 -- seconds between two looks at the queue
local MAX_ANSWERS = 20 -- once this many jobs wait, an ask is dropped, not answered

-- Results that mean "not now": the job stays at the head of the queue.
local RETRY = {
	[Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
	[Enum.SendAddonMessageResult.ChannelThrottle] = true,
	[Enum.SendAddonMessageResult.AddOnMessageLockdown] = true,
}

local playerName
local queue, waiting = {}, {} -- jobs in order, and the keys of those in it
local tokens, refilledAt = BURST, 0
local ticker
local answeredAt = {} -- sender -> GetTime() of the last answer, for the session
local groupSize, inGuild = 0, false

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
-- account, nor on a realm where the client restricts them.
function Client.canSend()
	return not (IsTrialAccount() or IsVeteranTrialAccount() or C_ChatInfo.AreOutgoingAddonChatMessagesRestricted())
end

local function isRegistered()
	local registration = ns.characters:registration(playerName)
	return registration and registration.nickname ~= nil
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
-- removal if the character unregistered meanwhile. Every character asks,
-- registered or not. A character that unregistered keeps answering asks with
-- its removal, and an anonymous one with "anonymous": that is how the change
-- reaches peers who were offline when it was announced. Returns nothing to
-- drop the job.
local function compose(job)
	local registration = ns.characters:registration(playerName)
	local message
	if job.kind == "ask" then
		message = { kind = "ask" }
	elseif not registration then
		return
	elseif registration.anonymous then
		message = { kind = "anonymous", revision = registration.revision }
	elseif not registration.nickname then
		message = { kind = "removal", revision = registration.revision }
	else
		local kind = job.kind == "answer" and "answer" or "announcement"
		message = { kind = kind, nickname = registration.nickname, revision = registration.revision }
	end
	local chatType = job.channel
	if chatType == "GROUP" then
		chatType = groupChannel()
	elseif chatType == "GUILD" and not IsInGuild() then
		chatType = nil
	end
	if chatType then
		return Protocol.write(message), chatType, job.target
	end
end

local function isPaused()
	return InCombatLockdown() or C_ChatInfo.InChatMessagingLockdown()
end

-- Sends what the allowance permits, oldest job first, unless in combat or in
-- lockdown; stops ticking once the queue is empty. Whispers outside instances
-- are exempt from the allowance (decision 0002), so answers spend no token.
local function flush()
	local now = GetTime()
	tokens = math.min(BURST, tokens + (now - refilledAt) * REFILL)
	refilledAt = now
	while queue[1] and not isPaused() do
		local job = queue[1]
		local text, chatType, target = compose(job)
		if text then
			local costs = chatType ~= "WHISPER" or IsInInstance()
			if costs and tokens < 1 then
				return
			end
			local result = C_ChatInfo.SendAddonMessage(Protocol.PREFIX, text, chatType, target)
			Debug.sent(text, chatType, target, result)
			if RETRY[result] then
				tokens = 0
				return
			end
			if costs then
				tokens = tokens - 1
			end
		end
		table.remove(queue, 1)
		waiting[job.key] = nil
	end
	if not queue[1] and ticker then
		ticker:Cancel()
		ticker = nil
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
	if not ticker then
		ticker = C_Timer.NewTicker(TICK, flush)
	end
	return true
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
	ns.memory = ns.Memory.new(db.memory, GetServerTime)
	ns.characters = ns.Self.new(db.characters, GetServerTime)
	db.settings = db.settings or {}
	if db.settings.chat == nil then
		db.settings.chat = true -- chat recognition; the settings panel exposes it later
	end
	ns.recognition = ns.Recognition.new(ns.memory, db.settings, ns.L, GetServerTime)
	-- The debug report (src/Report.lua): its events, the caught errors, the
	-- salt of its name hashes, and whether to offer it after an error.
	db.events = db.events or {}
	db.errors = db.errors or {}
	db.salt = db.salt or ("%08x"):format(math.random(0, 0x7fffffff))
	if db.settings.offerReport == nil then
		db.settings.offerReport = true
	end
	C_ChatInfo.RegisterAddonMessagePrefix(Protocol.PREFIX)
	for event in pairs(handlers) do
		if event ~= "ADDON_LOADED" then
			frame:RegisterEvent(event)
		end
	end
end

function handlers.PLAYER_LOGIN()
	playerName = GetUnitName("player")
	groupSize = GetNumGroupMembers()
	inGuild = IsInGuild()
	for _, channel in ipairs({ "GUILD", "GROUP" }) do
		if isRegistered() then
			enqueue("announce", channel)
		end
		enqueue("ask", channel)
	end
end

-- When the group grows, a registered character announces itself. It asks only
-- when it joins a group itself: a newcomer asks on its own, so the members
-- already there do not all ask again as a raid fills.
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

-- Everything a peer sends is untrusted: it is read only through Protocol, and
-- an identity is stored under the sender the server gives, never a name in
-- the message.
function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
	local isKnown = Client.isKnown
	if not isKnown(prefix) or prefix ~= Protocol.PREFIX then
		return
	end
	if not (isKnown(text) and isKnown(sender) and isKnown(channel)) then
		Debug.dropped("?", "secret", "?")
		return
	end
	if sender == "" or sender == playerName or not playerName then
		return
	end
	local message, reason = Protocol.read(text)
	if not message then
		Debug.dropped(sender, reason, text)
		return
	end
	Debug.received(sender, channel, text)
	if message.kind == "ask" then
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

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
frame:RegisterEvent("ADDON_LOADED")
