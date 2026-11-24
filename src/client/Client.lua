-- Client: the adapter that faces the game for data and messages (decision
-- 0004): the saved variables, the events and the addon messages, sent through
-- the paced queue (Outbox) and received through Inbox. The rules live in the
-- pure modules; this file only wires them to the WoW API
-- (docs/agents/wow-api.md).
local addonName, ns = ...

local Protocol = ns.Protocol
local Debug = ns.Debug
local L = ns.L

local Client = {}
ns.Client = Client

local SCHEMA = 1
local TICK = 0.25 -- seconds between two looks at the queue
local SYNC_TICK = 5 -- seconds between two looks at the syncs (cut, start waiting ones)
local NEWS_TICK = 1 -- seconds between two looks at the news due

-- Results that mean "not now": the job stays at the head of the queue.
local RETRY = {
	[Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
	[Enum.SendAddonMessageResult.ChannelThrottle] = true,
	[Enum.SendAddonMessageResult.AddOnMessageLockdown] = true,
}

local playerName
local outbox -- the paced queue, once loaded
local ticker
local groupSize, inGuild = 0, false
local inbox -- where every peer's message comes in, once loaded

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

-- A job's message: { text, chatType, target, kind }, and costs when it spends
-- the per-prefix allowance; whispers outside instances are exempt (decision
-- 0002), so answers and syncs spend no token.
local function toSend(text, chatType, target, kind)
	local costs = chatType ~= "WHISPER" or IsInInstance()
	return { text = text, chatType = chatType, target = target, kind = kind, costs = costs }
end

-- Builds a job's message when it is sent, from the registration as it is then:
-- a job that waited through a lockdown carries the latest nickname, or the
-- removal if the character unregistered meanwhile (Self:message). Returns
-- nothing to drop the job.
local function compose(job)
	if job.text then
		return toSend(job.text, "WHISPER", job.target, job.kind)
	elseif job.news then
		return toSend(Protocol.write({ kind = "news", identity = job.news }), "GUILD", nil, "news")
	end
	local registration = ns.characters:message(playerName, job.kind)
	if not registration then
		return
	end
	local chatType = job.channel
	if chatType == "GROUP" then
		-- A group's channel reaches players outside the scope: only while talking with everyone.
		chatType = MnemosyneDB.settings.everyone and groupChannel() or nil
	elseif chatType == "GUILD" and not IsInGuild() then
		chatType = nil
	end
	if chatType then
		return toSend(Protocol.write(registration), chatType, job.target, registration.kind)
	end
end

-- In combat or in lockdown: no addon message would go out.
function Client.isPaused()
	return InCombatLockdown() or C_ChatInfo.InChatMessagingLockdown()
end

-- Sends a message, or loops it back from the echo peer, and logs it. Returns
-- "sent", "retry" or "failed", as Outbox:flush needs.
local function send(out)
	local text, chatType, target = out.text, out.chatType, out.target
	local result
	if echoing and target == Client.ECHO then
		result = Enum.SendAddonMessageResult.Success -- no such character: never sent
	else
		result = C_ChatInfo.SendAddonMessage(Protocol.PREFIX, text, chatType, target)
	end
	Debug.sent(text, chatType, target, result, out.kind)
	if RETRY[result] then
		return "retry"
	elseif result ~= Enum.SendAddonMessageResult.Success then
		return "failed"
	end
	if echoing and (target == Client.ECHO or chatType ~= "WHISPER") then
		C_Timer.After(0, function()
			loopBack(Protocol.PREFIX, text, chatType, Client.ECHO)
		end)
	end
	return "sent"
end

local port = { paused = Client.isPaused, compose = compose, send = send }

-- Sends what the paced queue allows; stops ticking once it is empty.
local function flush()
	if not outbox:flush(port) and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function wake()
	if not ticker then
		ticker = C_Timer.NewTicker(TICK, flush)
	end
end

-- Queues a job once (Outbox:add). Returns true when it queued the job.
local function enqueue(kind, channel, target)
	if outbox:add(kind, channel, target) then
		wake()
		return true
	end
	return false
end

-- Queues what Sync returned, after everything else (Outbox:addSyncs).
local function sendSync(outgoing)
	if outgoing[1] then
		outbox:addSyncs(outgoing)
		wake()
	end
end

-- Queues one news due, to the guild if any, once the queue is empty: until
-- then, and in combat or in lockdown, news waits in News, where a guildmate's
-- post can still cancel it.
local function postNews()
	if Client.isPaused() or outbox:hasJobs() then
		return
	end
	local identity = ns.news:due()
	if identity and Client.canSend() and IsInGuild() then
		outbox:addNews(identity)
		wake()
	end
end

-- Starts syncs with the peers heard this session, the most recently heard
-- first (/mnemosyne sync). Returns how many started or wait.
function Client.sync()
	return inbox:syncAll()
end

-- How many peers were heard this session.
function Client.peerCount()
	return inbox:peerCount()
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
	local friends, roster = {}, {}
	scope:reset()
	-- On Forever a friend added by character name is listed with the Battle.net
	-- friends too: C_FriendList stays empty (docs/agents/wow-api.md).
	for i = 1, BNGetNumFriends() do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
			local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if account and account.clientProgram == BNET_CLIENT_WOW and isKnown(account.characterName) then
				scope:add(account.characterName)
				friends[#friends + 1] = account.characterName
			end
		end
	end
	for i = 1, GetNumGuildMembers() do
		local name = GetGuildRosterInfo(i)
		if isKnown(name) then
			scope:add(name)
			roster[#roster + 1] = name
		end
	end
	-- Whose professions are kept, and which peers may keep the roster's.
	ns.professions:seeLists(friends, roster)
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
	inbox:forget(Client.ECHO)
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
	shareProfessions = true, -- "Share my professions" (decision 0008)
}
Client.DEFAULTS = DEFAULTS

local frame = CreateFrame("Frame")
local handlers = {}

-- This character's professions (decision 0008), read into Self as they change;
-- peers get them only once a sync stamps them.

-- Reads the skill level of each profession, secondary ones included, keyed by
-- skill line ID (GetProfessionInfo's 7th value), never by the name. At login an
-- empty read is skipped: the game may not have the professions yet, and an
-- empty list would drop them all.
local function readProfessions(atLogin)
	local list = {}
	local indexes = { GetProfessions() } -- holes where a slot is empty
	for i = 1, table.maxn(indexes) do
		if indexes[i] then
			local _, _, level, maxLevel, _, _, skillLine = GetProfessionInfo(indexes[i])
			if skillLine then
				list[#list + 1] = { skillLine = skillLine, level = level, maxLevel = maxLevel }
			end
		end
	end
	if list[1] or not atLogin then
		ns.characters:seeProfessions(playerName, list)
	end
end

-- Rechecks which saved recipes are learned, with the windows closed.
local function recheckRecipes()
	for skillLine, recipeIDs in pairs(ns.characters:recipeIDs(playerName)) do
		local learned = {}
		for _, recipeID in ipairs(recipeIDs) do
			if C_SpellBook.IsSpellKnown(recipeID) then
				learned[#learned + 1] = recipeID
			end
		end
		ns.characters:seeRecipes(playerName, skillLine, recipeIDs, learned)
	end
end

-- Whether the open profession window is the player's own: not a linked
-- profession, the guild view or an NPC's crafting. Each check is asked only
-- where the client has it.
local function isOwnWindow()
	for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
		if C_TradeSkillUI[check] and C_TradeSkillUI[check]() then
			return false
		end
	end
	return true
end

-- Saves every recipe of the profession whose window the player opened, and the
-- learned ones: the list is empty while no window is open. Mnemosyne never
-- opens one itself. Read once per window open: the list update fires again
-- and again while crafting, and NEW_RECIPE_LEARNED covers what changes after.
-- Switching to another profession with the window open reads that one too.
local recipesReadFor -- the profession read since the window opened
local function readRecipes()
	if not playerName or not isOwnWindow() then
		return
	end
	local profession = C_TradeSkillUI.GetBaseProfessionInfo()
	local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
	if
		not (profession and profession.professionID and recipeIDs and recipeIDs[1])
		or profession.professionID == recipesReadFor
	then
		return
	end
	recipesReadFor = profession.professionID
	local learned = {}
	for _, recipeID in ipairs(recipeIDs) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe and recipe.learned then
			learned[#learned + 1] = recipeID
		end
	end
	ns.characters:seeRecipes(playerName, profession.professionID, recipeIDs, learned)
end

function handlers.TRADE_SKILL_SHOW()
	recipesReadFor = nil
	readRecipes()
end
handlers.TRADE_SKILL_LIST_UPDATE = readRecipes

-- Fires before login too: read only once the character is known.
function handlers.SKILL_LINES_CHANGED()
	if playerName then
		readProfessions()
	end
end

function handlers.NEW_RECIPE_LEARNED()
	if playerName then
		recheckRecipes()
	end
end

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
	db.settings = db.settings or {}
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then
			db.settings[key] = value
		end
	end
	ns.characters = ns.Self.new(db.characters, GetServerTime, db.settings)
	db.asked = db.asked or {}
	db.syncs = db.syncs or {}
	db.window = db.window or {} -- Mnemosyne's window: its position and last tab
	db.professions = db.professions or {}
	ns.professions = ns.Professions.new(db.professions, GetServerTime, ns.memory, ns.characters, db.settings)
	ns.sync = ns.Sync.new(db.syncs, GetServerTime, ns.memory, db.settings, ns.characters, ns.professions)
	ns.news = ns.News.new(GetTime, math.random, ns.memory, ns.characters, db.settings)
	outbox = ns.Outbox.new(GetTime, Client.canSend)
	inbox = ns.Inbox.new({
		clock = GetTime,
		serverClock = GetServerTime,
		memory = ns.memory,
		sync = ns.sync,
		news = ns.news,
		reader = Protocol.newReader(GetTime),
		outbox = outbox,
		wake = wake,
		canSend = Client.canSend,
		inScope = Client.inScope,
		playerName = Client.playerName,
		log = Debug,
		onNewer = function()
			ns.say(L.NEWER_VERSION)
		end,
	})
	ns.scope = ns.Scope.new(db.settings)
	ns.recognition = ns.Recognition.new(ns.memory, db.settings, ns.L, GetServerTime, ns.characters, ns.professions)
	-- The debug report (src/core/Report.lua): its events, the caught errors, and
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
	inbox:loggedIn()
	readProfessions(true)
	recheckRecipes()
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

-- A message from a peer goes to Inbox once known to hold no secret value
-- (comparing one raises an error).
function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
	local isKnown = Client.isKnown
	if not isKnown(prefix) or prefix ~= Protocol.PREFIX then
		return
	end
	if not (isKnown(text) and isKnown(sender) and isKnown(channel)) then
		Debug.dropped(nil, "secret", "?")
		return
	end
	inbox:receive(sender, channel, text)
end

loopBack = handlers.CHAT_MSG_ADDON

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
frame:RegisterEvent("ADDON_LOADED")
