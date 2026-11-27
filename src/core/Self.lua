-- Self: this account's characters and their registrations, keyed by full name.
-- Pure: it takes its saved table and the clock (the server time) as arguments
-- (decision 0004).
--
-- A character is in one of four states: "notAsked" (Mnemosyne has not asked
-- about it yet, or must ask again: Self.new), "registered" (with a nickname),
-- "anonymous" (its player chose not to register it) or "unregistered" (its
-- player withdrew its registration).
-- Each change gets a revision: the server time, or the previous revision plus
-- one if that is later, so it always moves forward (decision 0001).
--
-- It also keeps each character's professions, keyed by skill line ID, as read
-- from the game, and what peers may see of each: a copy given a revision only
-- when a sync stamps it (decision 0008).
local _, ns = ...

local Self = {}
Self.__index = Self
ns.Self = Self

-- The next revision after previous (nil for none): the server time, or previous
-- plus one if that is later.
local function nextRevision(self, previous)
	return math.max(self.clock(), previous and previous + 1 or 0)
end

-- Changes the registration, keeping the rest of the character's table (its
-- professions).
local function change(self, name, nickname, anonymous)
	local character = self.characters[name] or {}
	self.characters[name] = character
	character.revision = nextRevision(self, character.revision)
	character.nickname = nickname
	character.anonymous = anonymous
end

-- A nickname as the player typed it, tidied: without the emoji variation
-- selectors (U+FE0E, U+FE0F: a phone types "❤️" for the heart), which show
-- nothing and the rules refuse, without spaces around it, and with each run of
-- spaces inside it made one.
local function tidy(nickname)
	if type(nickname) ~= "string" then
		return nickname
	end
	return (nickname:gsub("\239\184[\142\143]", ""):gsub(" +", " "):match("^ ?(.-) ?$"))
end

-- saved: the table Self keeps the registrations in (MnemosyneDB.characters).
-- clock: returns the server time, in seconds.
-- settings: the saved settings (MnemosyneDB.settings): professions are shared
-- unless shareProfessions is false.
--
-- A saved nickname the rules now refuse (an older version took it) would stop
-- reaching updated peers, silently: it is tidied as a typed one is, with a new
-- revision so peers hear it, or else the character goes back to not asked, so
-- its player sees the registration prompt again.
function Self.new(saved, clock, settings)
	local self = setmetatable({ characters = saved, clock = clock, settings = settings }, Self)
	for name, character in pairs(saved) do
		if character.nickname and not ns.Protocol.checkNickname(character.nickname) then
			local nickname = tidy(character.nickname)
			if ns.Protocol.checkNickname(nickname) then
				change(self, name, nickname)
			else
				character.nickname, character.revision = nil, nil
			end
		end
	end
	return self
end

-- Registers a character with its player's nickname, or changes it. The
-- nickname is stored tidied (tidy). Returns true, or false and why the
-- nickname breaks the rules (Protocol.checkNickname).
function Self:register(name, nickname)
	nickname = tidy(nickname)
	local ok, reason = ns.Protocol.checkNickname(nickname)
	if not ok then
		return false, reason
	end
	change(self, name, nickname)
	return true
end

-- Withdraws a character's registration. Returns false when it was not
-- registered.
function Self:unregister(name)
	local character = self.characters[name]
	if not (character and character.nickname) then
		return false
	end
	change(self, name, nil)
	return true
end

-- Keeps a character anonymous: a change with a revision, so peers that held
-- its nickname forget it. Returns false when it already is anonymous.
function Self:keepAnonymous(name)
	if self:state(name) == "anonymous" then
		return false
	end
	change(self, name, nil, true)
	return true
end

-- The registration of a character, a copy: { nickname, revision } while it is
-- registered, { anonymous = true, revision } while it is anonymous, { revision }
-- once it unregistered, nil if it never registered.
function Self:registration(name)
	local character = self.characters[name]
	return character
		and character.revision
		and { nickname = character.nickname, anonymous = character.anonymous, revision = character.revision }
end

-- Remembers the GUID of a character as it is played: its full name can come
-- back on another player's character once it is deleted or renamed (decision
-- 0003). A character saved before Mnemosyne kept it has none until played.
function Self:see(name, guid)
	local character = self.characters[name] or {}
	self.characters[name] = character
	character.guid = guid
end

-- The GUID a character had when last played, or nil when unknown.
function Self:guid(name)
	local character = self.characters[name]
	return character and character.guid
end

-- A character's state: "notAsked", "registered", "anonymous" or "unregistered".
function Self:state(name)
	local character = self.characters[name]
	if not (character and character.revision) then -- a character with only professions read
		return "notAsked"
	elseif character.nickname then
		return "registered"
	elseif character.anonymous then
		return "anonymous"
	end
	return "unregistered"
end

-- The Protocol message a character sends for a job ("announce", "answer" or
-- "ask"), from its registration as it is now, or nil when it has nothing to
-- say. Every character asks. One that unregistered sends its removal, an
-- anonymous one "anonymous": it announces that only right after the change
-- (Client announces at login only when registered), and answers asks with it,
-- which is how the change reaches peers who were offline when it was announced.
function Self:message(name, job)
	if job == "ask" then
		return { kind = "ask" }
	end
	local character = self.characters[name]
	local state = self:state(name)
	if state == "registered" then
		local kind = job == "answer" and "answer" or "announcement"
		return { kind = kind, nickname = character.nickname, revision = character.revision }
	elseif state == "anonymous" then
		return { kind = "anonymous", revision = character.revision }
	elseif state == "unregistered" then
		return { kind = "removal", revision = character.revision }
	end
end

-- The registered and anonymous characters whose name or nickname contains the
-- text (Memory.matches), sorted by nickname (Memory.byNickname): { name, nickname }, nickname nil for
-- an anonymous one.
function Self:list(text)
	local found = {}
	for name, character in pairs(self.characters) do
		local state = self:state(name)
		if (state == "registered" or state == "anonymous") and ns.Memory.matches(text, name, character.nickname) then
			found[#found + 1] = { name = name, nickname = character.nickname }
		end
	end
	table.sort(found, ns.Memory.byNickname)
	return found
end

-- How many of this account's characters are in a state.
function Self:count(state)
	local count = 0
	for name in pairs(self.characters) do
		if self:state(name) == state then
			count = count + 1
		end
	end
	return count
end

-- What the registration prompt offers for a character, or nil when it should
-- not prompt (the character is registered, anonymous or unregistered: its
-- player has decided). A character not asked yet is prompted at each login
-- until its player answers. The offer pre-fills
-- the nickname of the player's latest registered character, or else what peers
-- say about this one (heard: Memory's identity for it, if any, flagged
-- fromPeers). The pre-fill is only an offer: nothing changes until the player
-- registers.
function Self:prompt(name, heard)
	if self:state(name) ~= "notAsked" then
		return nil
	end
	local latest
	for other, character in pairs(self.characters) do
		if other ~= name and character.nickname and not (latest and latest.revision >= character.revision) then
			latest = character
		end
	end
	if latest then
		return { nickname = latest.nickname }
	elseif heard and heard.nickname then
		return { nickname = heard.nickname, fromPeers = true }
	end
	return {}
end

local function copy(list)
	if not list then
		return nil
	end
	local result = {}
	for i, value in ipairs(list) do
		result[i] = value
	end
	return result
end

local function sorted(list)
	local result = copy(list)
	table.sort(result)
	return result
end

-- A character's professions as read, by skill line: { level, maxLevel,
-- recipeIDs (every recipe of the profession, sorted), learned (sorted), shared
-- (what peers may see: { level, maxLevel, recipes, revision }, or { revision }
-- for a removal) }. A dropped profession keeps only shared. create makes the
-- table, for a writer.
local function professionsOf(self, name, create)
	local character = self.characters[name]
	if create then
		character = character or {}
		self.characters[name] = character
		character.professions = character.professions or {}
	end
	return character and character.professions or {}
end

-- Whether peers may see a character's professions: registered, and sharing on.
local function sharing(self, name)
	return self:state(name) == "registered" and self.settings.shareProfessions ~= false
end

local function sameList(a, b)
	if not (a and b) then
		return a == b
	end
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- Reads a character's professions as the game gives them, each
-- { skillLine, level, maxLevel }. A profession missing from the list is
-- dropped: peers hear of it as a removal at the next stamp. Returns true when
-- it changed what was read.
function Self:seeProfessions(name, list)
	local professions = professionsOf(self, name, true)
	local seen, changed = {}, false
	for _, read in ipairs(list) do
		local profession = professions[read.skillLine] or {}
		professions[read.skillLine] = profession
		changed = changed or profession.level ~= read.level or profession.maxLevel ~= read.maxLevel
		profession.level, profession.maxLevel = read.level, read.maxLevel
		seen[read.skillLine] = true
	end
	for skillLine, profession in pairs(professions) do
		if not seen[skillLine] then
			changed = changed or profession.level ~= nil
			professions[skillLine] = profession.shared and { shared = profession.shared } or nil
		end
	end
	return changed
end

-- Reads a profession's recipes: every recipe ID of the profession (read while
-- its window is open) and the learned ones. Ignored for a profession the
-- character does not have. A recipe belongs to one profession: another of the
-- character's holding any of them read them under the wrong skill line, and
-- loses its recipes until its own window is read. Returns true when it
-- changed what was read.
function Self:seeRecipes(name, skillLine, recipeIDs, learned)
	local professions = professionsOf(self, name)
	local profession = professions[skillLine]
	if not (profession and profession.level) then
		return false
	end
	recipeIDs, learned = sorted(recipeIDs), sorted(learned)
	local changed = not (sameList(recipeIDs, profession.recipeIDs) and sameList(learned, profession.learned))
	profession.recipeIDs, profession.learned = recipeIDs, learned
	local read = {}
	for _, id in ipairs(recipeIDs) do
		read[id] = true
	end
	for other, held in pairs(professions) do
		for _, id in ipairs(other ~= skillLine and held.recipeIDs or {}) do
			if read[id] then
				held.recipeIDs, held.learned, changed = nil, nil, true
				break
			end
		end
	end
	return changed
end

-- Adds the recipes found learned with the profession's window closed: found
-- maps each recipe ID to the skill line the game puts it in, and only those of
-- this profession count (a peer may have read a recipe under the wrong one).
-- Ignored for a profession the character does not have; its full recipe list
-- stays the window's. Returns true when it changed what was read.
function Self:learnRecipes(name, skillLine, found)
	local profession = professionsOf(self, name)[skillLine]
	if not (profession and profession.level) then
		return false
	end
	local learned, known = copy(profession.learned) or {}, {}
	for _, recipe in ipairs(learned) do
		known[recipe] = true
	end
	local changed = false
	for recipe, line in pairs(found) do
		if line == skillLine and not known[recipe] then
			learned[#learned + 1], changed = recipe, true
		end
	end
	if changed then
		table.sort(learned)
		profession.learned = learned
	end
	return changed
end

-- The professions to name in the one-time hint to open each profession's
-- window once (its recipes are shared only then): the skill lines of those
-- with no saved recipe list, sorted. In the registration prompt (prompting)
-- any such profession counts; at login only for a registered character none
-- of whose professions has a saved list. nil once the hint was shown
-- (hintRecipes) or when there is nothing to name.
function Self:recipeHint(name, prompting)
	local character = self.characters[name]
	if not character or character.recipesHinted then
		return nil
	end
	local unread, count = {}, 0
	for skillLine, profession in pairs(professionsOf(self, name)) do
		if profession.level then
			count = count + 1
			if not profession.recipeIDs then
				unread[#unread + 1] = skillLine
			end
		end
	end
	if not unread[1] or not (prompting or (self:state(name) == "registered" and #unread == count)) then
		return nil
	end
	table.sort(unread)
	return unread
end

-- Remembers that the hint to open the profession windows was shown.
function Self:hintRecipes(name)
	local character = self.characters[name] or {}
	self.characters[name] = character
	character.recipesHinted = true
end

-- This account's characters with a profession read now, sorted by name: what
-- they show to their own player never depends on what is shared.
function Self:withProfessions()
	local found = {}
	for name in pairs(self.characters) do
		if self:currentProfessions(name)[1] then
			found[#found + 1] = name
		end
	end
	table.sort(found)
	return found
end

-- A character's professions as read now, whatever was stamped or is shared,
-- sorted by skill line, copies: { skillLine, level, maxLevel, recipes (the
-- learned ones, sorted, nil until its window was opened) }. Dropped ones are
-- left out.
function Self:currentProfessions(name)
	local found = {}
	for skillLine, profession in pairs(professionsOf(self, name)) do
		if profession.level then
			found[#found + 1] = {
				skillLine = skillLine,
				level = profession.level,
				maxLevel = profession.maxLevel,
				recipes = copy(profession.learned),
			}
		end
	end
	table.sort(found, function(a, b)
		return a.skillLine < b.skillLine
	end)
	return found
end

-- The saved recipe IDs of each of a character's professions, by skill line,
-- copies: to recheck which are learned with the window closed.
function Self:recipeIDs(name)
	local found = {}
	for skillLine, profession in pairs(professionsOf(self, name)) do
		found[skillLine] = copy(profession.recipeIDs)
	end
	return found
end

-- Gives a new revision to each of a character's professions that changed since
-- its last one (a sync starts): its level, its learned recipes, or that it was
-- dropped or withdrawn (the character is not registered, or sharing is off).
-- skillLines (optional): the game's skill lines, a set; while the character is
-- registered, each it lacks gets a removal too, once, so the character's own
-- share drops a copy a peer forged of a profession it never had (first-hand
-- wins over any second-hand copy).
function Self:stampProfessions(name, skillLines)
	local shared = sharing(self, name)
	local registered = skillLines ~= nil and self:state(name) == "registered"
	local professions = professionsOf(self, name, registered)
	for skillLine in pairs(registered and skillLines or {}) do
		professions[skillLine] = professions[skillLine] or {}
	end
	for _, profession in pairs(professions) do
		local last = profession.shared
		local now = {}
		if shared and profession.level then
			now = { level = profession.level, maxLevel = profession.maxLevel, recipes = copy(profession.learned) }
		end
		local unchanged = last
			and now.level == last.level
			and now.maxLevel == last.maxLevel
			and sameList(now.recipes, last.recipes)
		-- A profession never stamped needs no removal, no peer heard of it,
		-- unless a peer may have forged it (registered).
		if (last or now.level or registered) and not unchanged then
			now.revision = nextRevision(self, last and last.revision)
			profession.shared = now
		end
	end
end

-- What peers may see of a character's professions, as last stamped, sorted by
-- skill line, copies: { skillLine, level, maxLevel, recipes (nil until its
-- window was opened), revision }, or { skillLine, revision } for a removal.
-- While the character is not registered or sharing is off, every profession is
-- a removal. Professions never stamped are left out.
function Self:professions(name)
	local shared = sharing(self, name)
	local found = {}
	for skillLine, profession in pairs(professionsOf(self, name)) do
		local last = profession.shared
		if last then
			local entry = { skillLine = skillLine, revision = last.revision }
			if shared and last.level then
				entry.level, entry.maxLevel, entry.recipes = last.level, last.maxLevel, copy(last.recipes)
			end
			found[#found + 1] = entry
		end
	end
	table.sort(found, function(a, b)
		return a.skillLine < b.skillLine
	end)
	return found
end
