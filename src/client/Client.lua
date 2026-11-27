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

-- This copy's version, "1.4.1", read from the release's tag the packager wrote
-- in the .toc ("v1.4.1"); nil in a copy it did not build, which sends none.
Client.VERSION = Protocol.releaseVersion(C_AddOns.GetAddOnMetadata(addonName, "Version"))

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
	local message = job.kind == "version" and { kind = "version", version = Client.VERSION }
		or ns.characters:message(playerName, job.kind)
	if not message then
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
		return toSend(Protocol.write(message), chatType, job.target, message.kind)
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

-- Queues a job once (Outbox:add), an announcement with this account's
-- version after it (when it has one: Client.VERSION). Returns true when it
-- queued the job.
local function enqueue(kind, channel, target)
	if outbox:add(kind, channel, target) then
		if kind == "announce" and Client.VERSION then
			outbox:add("version", channel, target)
		end
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

-- Reads the friends and guildmates again on the next look (Client.inScope, Client.onlineNames).
local scopeRead = false

-- Reads the friends and the guild roster, and who of them is online, into
-- the scope, the one place that holds them (Scope).
local function readScope()
	local isKnown = Client.isKnown
	local friends, roster, online = {}, {}, {}
	-- On Forever a friend added by character name is listed with the Battle.net
	-- friends too: C_FriendList stays empty (docs/agents/wow-api.md).
	for i = 1, BNGetNumFriends() do
		for j = 1, C_BattleNet.GetFriendNumGameAccounts(i) do
			local account = C_BattleNet.GetFriendGameAccountInfo(i, j)
			if account and account.clientProgram == BNET_CLIENT_WOW and isKnown(account.characterName) then
				friends[#friends + 1] = account.characterName
				if account.isOnline then
					online[account.characterName] = true
				end
			end
		end
	end
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
		if isKnown(name) then
			roster[#roster + 1] = name
			if isKnown(isOnline) and isOnline then
				online[name] = true
			end
		end
	end
	ns.scope:see(friends, roster, online)
	-- Whose professions are kept.
	ns.professions:seeLists()
	scopeRead = true
end

-- Whether Mnemosyne talks with a character (Scope): a friend or a guildmate,
-- or anyone while "Talk with everyone" is on. The echo peer while it is on.
function Client.inScope(name)
	if echoing and name == Client.ECHO then
		return true
	end
	if not scopeRead then
		readScope()
	end
	return ns.scope:allows(name)
end

-- The characters online now that the game tells of, as a set of names: this
-- one, the friends' and the guildmates', as last read (readScope).
function Client.onlineNames()
	if not scopeRead then
		readScope()
	end
	local online = ns.scope:online()
	online[Client.playerName() or ""] = true
	return online
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

-- Redraws the window's open tab once this character's professions changed:
-- the Professions tab shows them as read now.
local function redraw(changed)
	if changed and ns.Window then
		ns.Window.refresh()
	end
end

-- This character's professions as the game has them now, secondary ones
-- included: { skillLine, name, icon, level, maxLevel } each, keyed by skill line
-- ID (GetProfessionInfo's 7th value), never by the name. Every slot is read, up
-- to the last one GetProfessions returns.
function Client.ownProfessions()
	local list = {}
	local indexes = { GetProfessions() } -- holes where a slot is empty
	for i = 1, table.maxn(indexes) do
		if indexes[i] then
			local name, icon, level, maxLevel, _, _, skillLine = GetProfessionInfo(indexes[i])
			if skillLine then
				list[#list + 1] =
					{ skillLine = skillLine, name = name, icon = icon, level = level, maxLevel = maxLevel }
			end
		end
	end
	return list
end

-- Reads the skill level of each profession (Client.ownProfessions). At login an
-- empty read is skipped: the game may not have the professions yet, and an
-- empty list would drop them all.
local function readProfessions(atLogin)
	local list = Client.ownProfessions()
	if list[1] or not atLogin then
		redraw(ns.characters:seeProfessions(playerName, list))
	end
end

-- Rechecks which saved recipes are learned, with the windows closed.
local function recheckRecipes()
	local changed = false
	for skillLine, recipeIDs in pairs(ns.characters:recipeIDs(playerName)) do
		local learned = {}
		for _, recipeID in ipairs(recipeIDs) do
			if C_SpellBook.IsSpellKnown(recipeID) then
				learned[#learned + 1] = recipeID
			end
		end
		changed = ns.characters:seeRecipes(playerName, skillLine, recipeIDs, learned) or changed
	end
	redraw(changed)
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
-- Read only once the game has switched its data to the profession shown, as
-- Blizzard's Professions window does: until then, GetBaseProfessionInfo can
-- still give the profession shown before while the recipes are the new one's.
local recipesReadFor -- the profession read since the window opened
local function readRecipes()
	if not playerName or not isOwnWindow() then
		return
	end
	if C_TradeSkillUI.IsDataSourceChanging and C_TradeSkillUI.IsDataSourceChanging() then
		return -- a TRADE_SKILL_LIST_UPDATE follows once it has changed
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
	redraw(ns.characters:seeRecipes(playerName, profession.professionID, recipeIDs, learned))
end

-- The read waits for TRADE_SKILL_LIST_UPDATE, which follows.
function handlers.TRADE_SKILL_SHOW()
	recipesReadFor = nil
end
handlers.TRADE_SKILL_LIST_UPDATE = readRecipes

-- The skill line the game places a recipe in (its parent profession's, as
-- ProfessionsUtil.OpenProfessionFrameToRecipe reads it), or nil when it cannot:
-- Professions drops a peer's recipe placed in another profession or nowhere.
-- Cached for the session, a recipe it cannot place as false once it placed
-- one (its data is loaded by then), so a peer's made-up IDs are looked up
-- once; at most 10,000 of those, so they cannot grow the cache without end.
-- A secret answer is not cached.
local skillLineOfRecipe = {}
local placesRecipes = false -- whether the game placed a recipe this session
local unplaced = 0 -- how many recipes the cache holds as false
local function recipeSkillLine(recipeID)
	local found = skillLineOfRecipe[recipeID]
	if found == nil and C_TradeSkillUI.GetTradeSkillLineForRecipe then
		local skillLine, _, parent = C_TradeSkillUI.GetTradeSkillLineForRecipe(recipeID)
		found = parent or skillLine
		if found ~= nil and not Client.isKnown(found) then
			return nil
		elseif type(found) ~= "number" then
			if placesRecipes and unplaced < 10000 then
				skillLineOfRecipe[recipeID] = false
				unplaced = unplaced + 1
			end
			return nil
		end
		placesRecipes = true
		skillLineOfRecipe[recipeID] = found
	end
	return found or nil
end

-- Looks with the windows closed for recipes peers know of this character's
-- professions: one counts as learned when the game knows its spell and puts it
-- in that profession (a recipe read by an older version under the wrong skill
-- line may have spread). Returns true when it changed what was read.
local function findRecipes()
	local changed = false
	for skillLine, recipeIDs in pairs(ns.professions:recipesToFind(playerName)) do
		local found = {}
		for _, recipeID in ipairs(recipeIDs) do
			if C_SpellBook.IsSpellKnown(recipeID) then
				found[recipeID] = recipeSkillLine(recipeID) -- nil when unknown: not taken
			end
		end
		changed = ns.characters:learnRecipes(playerName, skillLine, found) or changed
	end
	return changed
end

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
	-- Each character's own memory (decision 0001): at its first login since the
	-- update, a copy of the account's memory as 1.4.x left it (Seed).
	if type(MnemosyneCharacterDB) ~= "table" then
		MnemosyneCharacterDB = {}
	end
	local mine = MnemosyneCharacterDB
	ns.Seed.load(db, mine, GetServerTime(), SCHEMA)
	mine.memory = mine.memory or {}
	mine.forgotten = mine.forgotten or {}
	mine.professions = mine.professions or {}
	mine.asked = mine.asked or {}
	db.characters = db.characters or {}
	db.debug = db.debug == true
	db.settings = db.settings or {}
	for key, value in pairs(DEFAULTS) do
		if db.settings[key] == nil then
			db.settings[key] = value
		end
	end
	ns.characters = ns.Self.new(db.characters, GetServerTime, db.settings)
	ns.memory = ns.Memory.new(mine.memory, GetServerTime, mine.forgotten, ns.characters)
	-- Each character's syncs and early syncs (Sync), under keys of their own: 1.4.0
	-- reads syncs and earlySyncs as times and marks by peer, so emptying those keeps a
	-- downgrade working; what they held is let go (at most one more sync).
	db.syncs, db.earlySyncs = nil, nil
	db.characterSyncs = db.characterSyncs or {}
	db.characterEarlySyncs = db.characterEarlySyncs or {}
	db.window = db.window or {} -- Mnemosyne's window: its position and last tab
	-- The versions of Mnemosyne peers run, by name (Inbox).
	-- shortcut: never pruned, one short entry per peer ever heard; prune with the memory if it grows.
	db.versions = db.versions or {}
	ns.scope = ns.Scope.new(db.settings)
	ns.professions = ns.Professions.new(
		mine.professions,
		GetServerTime,
		ns.memory,
		ns.characters,
		db.settings,
		ns.scope,
		recipeSkillLine,
		Client.playerName
	)
	ns.sync = ns.Sync.new(
		db.characterSyncs,
		GetServerTime,
		ns.memory,
		db.settings,
		ns.professions,
		db.characterEarlySyncs,
		Client.playerName,
		ns.scope
	)
	ns.news = ns.News.new(GetTime, math.random, ns.memory, db.settings)
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
		versions = db.versions,
		version = function()
			return Client.VERSION
		end,
	})
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
	-- Its full name can come back on another player's character (Recognition:recall).
	local guid = UnitGUID("player")
	if Client.isKnown(guid) then
		ns.characters:see(playerName, guid)
	end
	forgetEcho() -- left by a session that ended with the echo peer on
	groupSize = GetNumGroupMembers()
	inGuild = IsInGuild()
	inbox:loggedIn()
	readProfessions(true)
	recheckRecipes()
	redraw(findRecipes())
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

local redrawPending -- a redraw for professions a sync brought, due soon

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
	local changes = ns.professions.changes
	inbox:receive(sender, channel, text)
	if ns.professions.changes ~= changes and not redrawPending then
		-- A sync brought professions: one look for this character's recipes
		-- and one redraw for a burst of messages.
		redrawPending = true
		C_Timer.After(0.5, function()
			redrawPending = false
			findRecipes()
			if ns.Window then
				ns.Window.refresh()
			end
		end)
	end
end

loopBack = handlers.CHAT_MSG_ADDON

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
frame:RegisterEvent("ADDON_LOADED")
