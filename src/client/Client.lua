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
local WARM_COUNT = 15 -- professions hashed a frame after load (Professions:warm), about 1 ms

-- Results that mean "not now": the job stays at the head of the queue.
local RETRY = {
	[Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
	[Enum.SendAddonMessageResult.ChannelThrottle] = true,
	[Enum.SendAddonMessageResult.AddOnMessageLockdown] = true,
}

local playerName
local seeded -- whether this login copied the account's memory to the character (Seed)
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

-- Whether the guild roster shows a character offline. A character off the
-- roster, or with a secret name or status, counts as online: only the server
-- can tell. The roster is walked once into a set of the names it shows
-- offline, read again after it changes (GUILD_ROSTER_UPDATE), not at every
-- whisper.
local offline -- name -> true, nil until read
local function isOffline(name)
	if not offline then
		local isKnown = Client.isKnown
		offline = {}
		for i = 1, GetNumGuildMembers() do
			local member, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
			if isKnown(member) and isKnown(isOnline) and not isOnline then
				offline[member] = true
			end
		end
	end
	return offline[name] == true
end

-- Sends a message, or loops it back from the echo peer, and logs it. Returns
-- "sent", "retry" or "failed", as Outbox:flush needs.
local function send(out)
	local text, chatType, target = out.text, out.chatType, out.target
	local result
	if echoing and target == Client.ECHO then
		result = Enum.SendAddonMessageResult.Success -- no such character: never sent
	elseif chatType == "WHISPER" and isOffline(target) then
		-- Never sent: the server would answer "No player named ... is currently
		-- playing." in the chat, and still return Success.
		result = Enum.SendAddonMessageResult.TargetOffline
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

-- Whether the friends and guildmates were read (Client.inScope and
-- Client.onlineNames read them first): once, with the guild's roster if in a
-- guild. Once they change, they are read again on a timer, at most every 30
-- seconds and never in combat: the last read holds meanwhile. A big guild's
-- roster changes every few seconds, and each read walks it whole.
local scopeRead = false
local SCOPE_EVERY = 30 -- seconds
local scopeTimer -- the read due
local scopeAfterCombat = false -- whether the read waits for combat to end

local progressFirst = false -- which category's prune goes first at the next read (readScope)

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
	-- Whose professions and progress are kept; never both pruned at one read,
	-- each going first in turn so neither waits for ever.
	local first, second = ns.professions, ns.progress
	if progressFirst then
		first, second = second, first
	end
	progressFirst = not progressFirst
	second:seeLists(first:seeLists())
	-- A guild's roster read empty had not come from the server yet: read again at the next change.
	scopeRead = roster[1] ~= nil or not IsInGuild()
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
	if not scopeRead or scopeTimer or scopeAfterCombat then
		return -- read on the next look, or already due
	end
	scopeTimer = C_Timer.NewTimer(SCOPE_EVERY, function()
		scopeTimer = nil
		if InCombatLockdown() then
			scopeAfterCombat = true
		else
			readScope()
		end
	end)
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
	shareProgress = true, -- "Share my progress" (decision 0009)
}
Client.DEFAULTS = DEFAULTS

local frame = CreateFrame("Frame")
local handlers = {}

-- This character's professions (decision 0008), read into Self as they change;
-- peers get them only once a sync stamps them.

-- Redraws the professions' views (or those of key, "progress") that show once
-- this character's professions (or progress) changed: they show them as read now.
local function redraw(changed, key)
	if changed and ns.Window then
		ns.Window.refresh(key or "professions")
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
-- line may have spread). With sinceLast, only in the professions peers'
-- syncs brought since the last look. Returns true when it changed what was read.
local function findRecipes(sinceLast)
	local changed = false
	for skillLine, recipeIDs in pairs(ns.professions:recipesToFind(playerName, sinceLast)) do
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

-- This character's progress (decision 0009): the milestones' items it holds in
-- its bags, keyring and bank, and its quests, read into Self as they change;
-- peers get it only once a sync stamps it. Only the items Milestones tracks
-- are looked for (TRACKED).
local TRACKED = {}
for _, itemID in ipairs(ns.Milestones.ITEMS) do
	TRACKED[itemID] = true
end

-- Adds to held the tracked items in the containers from first to last.
-- Returns held, and whether the containers held any item at all.
local function readContainers(held, first, last)
	local any = false
	for bag = first, last do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			any = any or itemID ~= nil
			if TRACKED[itemID] then
				held[itemID] = true
			end
		end
	end
	return held, any
end

-- The bank is read only while it is open; the tracked items it held are
-- remembered (MnemosyneCharacterDB.progressBank) as last seen. A read that
-- finds no item at all is not the bank yet (or any more; its slots may still
-- answer with their items gone): what was seen is kept, so a key kept in the
-- bank never loses its tick to an early or late read. An empty bank keeps
-- what it held last, until it holds something again.
local bankOpen = false
local function readBank()
	local held, any = readContainers({}, Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_9)
	if any then
		MnemosyneCharacterDB.progressBank = held
	end
end

-- Reads each milestone's cell (Milestones.cells) from the bags, the keyring
-- (bag -1 on Forever), the bank as last seen and the quests. At login a read
-- with no milestone at all is skipped, as for the professions: the bags may
-- not be there yet; one more read follows a few seconds later, so a key gone
-- since the last session (sold on another computer) loses its tick.
local LOGIN_READ_AGAIN = 5 -- seconds
local readProgressSoon
local function readProgress(atLogin)
	if bankOpen then
		readBank()
	end
	local held = readContainers({}, Enum.BagIndex.Keyring, Enum.BagIndex.Keyring)
	readContainers(held, Enum.BagIndex.Backpack, NUM_BAG_SLOTS)
	for itemID in pairs(MnemosyneCharacterDB.progressBank) do
		held[itemID] = true
	end
	local completed, inLog = {}, {}
	for _, questID in ipairs(ns.Milestones.QUESTS) do
		completed[questID] = C_QuestLog.IsQuestFlaggedCompleted(questID)
		inLog[questID] = C_QuestLog.IsOnQuest(questID)
	end
	local cells = ns.Milestones.cells(held, completed, inLog)
	if next(cells) or not atLogin then
		redraw(ns.characters:seeProgress(playerName, cells), "progress")
	else
		C_Timer.After(LOGIN_READ_AGAIN, readProgressSoon)
	end
end

-- One read for every change of a frame (a loot fires several), never in
-- combat, where it waits for the end.
local progressDue, progressAfterCombat = false, false
function readProgressSoon()
	if not playerName or progressDue or progressAfterCombat then
		return
	end
	progressDue = true
	C_Timer.After(0, function()
		progressDue = false
		if InCombatLockdown() then
			progressAfterCombat = true
		else
			readProgress()
		end
	end)
end

handlers.BAG_UPDATE_DELAYED = readProgressSoon
handlers.QUEST_ACCEPTED = readProgressSoon
handlers.QUEST_TURNED_IN = readProgressSoon
handlers.QUEST_REMOVED = readProgressSoon

function handlers.BANKFRAME_OPENED()
	bankOpen = true
	readProgressSoon()
end

-- The bank is read a last time as it closes, if it still can be (readBank).
function handlers.BANKFRAME_CLOSED()
	if bankOpen and not InCombatLockdown() then
		readBank()
	end
	bankOpen = false
	readProgressSoon()
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
	seeded = ns.Seed.load(db, mine, GetServerTime(), SCHEMA)
	mine.memory = mine.memory or {}
	mine.forgotten = mine.forgotten or {}
	mine.professions = mine.professions or {}
	mine.progress = mine.progress or {}
	mine.progressBank = mine.progressBank or {} -- the tracked items the bank held, as last seen
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
	ns.progress = ns.Progress.new(
		mine.progress,
		GetServerTime,
		ns.memory,
		ns.characters,
		db.settings,
		ns.scope,
		Client.playerName
	)
	ns.sync = ns.Sync.new(
		db.characterSyncs,
		GetServerTime,
		ns.memory,
		db.settings,
		ns.professions,
		ns.progress,
		db.characterEarlySyncs,
		Client.playerName,
		ns.scope,
		true -- lazy: each answer made as the paced queue sends it
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
		paused = Client.isPaused,
	})
	ns.recognition =
		ns.Recognition.new(ns.memory, db.settings, ns.L, GetServerTime, ns.characters, ns.professions, ns.progress)
	-- The debug report (src/core/Report.lua): its events, the caught errors, and
	-- whether to offer it after an error.
	db.events = db.events or {}
	db.errors = db.errors or {}
	C_ChatInfo.RegisterAddonMessagePrefix(Protocol.PREFIX)
	-- The professions' hashes, then the progress', a few each frame out of
	-- combat, so the first sync's digest does not compute them all in one frame.
	local warming
	warming = C_Timer.NewTicker(0, function()
		if not InCombatLockdown() and not (ns.professions:warm(WARM_COUNT) or ns.progress:warm(WARM_COUNT)) then
			warming:Cancel()
		end
	end)
	for event in pairs(handlers) do
		if event ~= "ADDON_LOADED" then
			frame:RegisterEvent(event)
		end
	end
end

function handlers.PLAYER_LOGIN()
	playerName = GetUnitName("player")
	local guid = UnitGUID("player")
	if not Client.isKnown(guid) then
		guid = nil
	end
	-- A character created since the update starts empty (decision 0001): told
	-- by its name, read here as everywhere (not at ADDON_LOADED, which copied
	-- the seed), before any sync. Then Self learns its GUID: its full name can
	-- come back on another player's character (Recognition:recall).
	ns.Seed.login(ns.characters, playerName, guid, seeded, ns.memory, ns.professions)
	forgetEcho() -- left by a session that ended with the echo peer on
	groupSize = GetNumGroupMembers()
	inGuild = IsInGuild()
	inbox:loggedIn()
	readProfessions(true)
	if InCombatLockdown() then
		progressAfterCombat = true
	else
		readProgress(true)
	end
	recheckRecipes()
	redraw(findRecipes())
	C_Timer.NewTicker(SYNC_TICK, function()
		-- In combat or lockdown it only cuts: the waiting syncs start after.
		sendSync(ns.sync:tick(Client.isPaused()))
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
	offline = nil -- the roster read again (isOffline)
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
function handlers.GUILD_ROSTER_UPDATE()
	offline = nil -- the roster read again (isOffline)
	listsChanged()
end

local REDRAW_EVERY = 2 -- seconds: at most one redraw this often while a sync brings professions
local redrawPending -- a redraw for professions a sync brought, due soon
local redrawDue = { professions = false, progress = false } -- what a sync brought since the last redraw

-- The look for this character's recipes (findRecipes) after a sync brought
-- professions: once, 15 seconds after the last of them, so a sync's burst
-- of messages (about one every 4 seconds) costs one look, in the professions
-- heard since; never in combat, where it waits for the end.
local FIND_RECIPES_AFTER = 15 -- seconds
local findTimer -- the look due, restarted at each change
local findAfterCombat = false -- whether the look waits for combat to end

local function findRecipesSoon()
	if findTimer then
		findTimer:Cancel()
	end
	findTimer = C_Timer.NewTimer(FIND_RECIPES_AFTER, function()
		findTimer = nil
		if InCombatLockdown() then
			findAfterCombat = true
		else
			redraw(findRecipes(true))
		end
	end)
end

function handlers.PLAYER_REGEN_ENABLED()
	if findAfterCombat then
		findAfterCombat = false
		redraw(findRecipes(true))
	end
	if scopeAfterCombat then
		scopeAfterCombat = false
		readScope()
	end
	if progressAfterCombat then
		progressAfterCombat = false
		readProgress()
	end
end

-- Whispers heard in combat or lockdown (syncs, mostly) wait to be read until
-- it ends, a few at each look: nothing could be sent meanwhile, and reading
-- a sync costs. At most 1,000 wait; one more is dropped, as a lost chunk.
local PARK_MAX = 1000
local REPLAY_EVERY, REPLAY_COUNT = 0.25, 10 -- seconds, whispers read at each look
local parked, parkedFirst, parkedLast = {}, 1, 0
local replayTicker
local receive -- the whisper's way to Inbox, defined below

local function replay()
	if Client.isPaused() then
		return
	end
	for _ = 1, REPLAY_COUNT do
		local message = parked[parkedFirst]
		if not message then
			break
		end
		parked[parkedFirst], parkedFirst = nil, parkedFirst + 1
		receive(message[1], message[2], message[3])
	end
	if parkedFirst > parkedLast then
		parkedFirst, parkedLast = 1, 0
		replayTicker:Cancel()
		replayTicker = nil
	end
end

local function park(text, channel, sender)
	if parkedLast - parkedFirst + 1 >= PARK_MAX then
		Debug.dropped(sender, "paused", text)
		return
	end
	parkedLast = parkedLast + 1
	parked[parkedLast] = { text, channel, sender }
	replayTicker = replayTicker or C_Timer.NewTicker(REPLAY_EVERY, replay)
end

-- A message from a peer goes to Inbox once known to hold no secret value
-- (comparing one raises an error); a whisper in scope waits while paused, or
-- while others wait (park).
function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
	local isKnown = Client.isKnown
	if not isKnown(prefix) or prefix ~= Protocol.PREFIX then
		return
	end
	if not (isKnown(text) and isKnown(sender) and isKnown(channel)) then
		Debug.dropped(nil, "secret", "?")
		return
	end
	if channel == "WHISPER" and (replayTicker or Client.isPaused()) then
		-- Checked before it waits, as Inbox would: anyone's whispers would
		-- otherwise fill the 1,000 places and drop the syncs in scope.
		if Client.inScope(sender) then
			park(text, channel, sender)
		else
			Debug.dropped(sender, "scope", text)
		end
		return
	end
	receive(text, channel, sender)
end

function receive(text, channel, sender)
	local changes, progressChanges = ns.professions.changes, ns.progress.changes
	inbox:receive(sender, channel, text)
	if ns.professions.changes ~= changes then
		findRecipesSoon()
	end
	-- A sync brought professions or progress: one redraw of the views of what
	-- came in the next 2 seconds, each only if some came.
	redrawDue.professions = redrawDue.professions or ns.professions.changes ~= changes
	redrawDue.progress = redrawDue.progress or ns.progress.changes ~= progressChanges
	if (redrawDue.professions or redrawDue.progress) and not redrawPending then
		redrawPending = true
		C_Timer.After(REDRAW_EVERY, function()
			redrawPending = false
			redraw(redrawDue.professions)
			redraw(redrawDue.progress, "progress")
			redrawDue.professions, redrawDue.progress = false, false
		end)
	end
end

loopBack = handlers.CHAT_MSG_ADDON

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
frame:RegisterEvent("ADDON_LOADED")
