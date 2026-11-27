-- Scope: whom Mnemosyne talks with (decision 0007). By default only friends
-- (the friend list and Battle.net friends' characters) and guildmates; with
-- "Talk with everyone" on, anyone. It holds who is a friend or a guildmate,
-- and who of them is online, as Client last read the lists: Sync asks it who
-- is a guildmate (the shorter cooldown), Professions whose professions go to
-- whom. Pure: Client reads the lists from the game (decision 0004).
local _, ns = ...

local Scope = {}
Scope.__index = Scope
ns.Scope = Scope

-- A name without its realm: a whisper from another realm carries it
-- ("Mip Wiq-Realm"), a list may not.
local function key(name)
	return (name:gsub("%-.*$", ""))
end

-- settings: the saved settings; settings.everyone opens the scope to anyone.
function Scope.new(settings)
	return setmetatable({ settings = settings, names = {}, guildmates = {}, read = {}, onlineNames = {} }, Scope)
end

-- Adds the names of one list; guild says whether it is the guild roster.
local function add(self, list, guild, online)
	for _, name in ipairs(list) do
		if type(name) == "string" and name ~= "" then
			self.names[key(name)] = true
			if guild then
				self.guildmates[key(name)] = true
			end
			self.read[#self.read + 1] = name
			if online and online[name] then
				self.onlineNames[name] = true
			end
		end
	end
end

-- Sees the lists as Client reads them, forgetting the ones before: friends
-- (Battle.net friends' characters) and guildmates (the guild roster), arrays
-- of full names, and online, the set of those online now (none when left
-- out). A missing or empty name is ignored.
function Scope:see(friends, guildmates, online)
	self.names, self.guildmates, self.read, self.onlineNames = {}, {}, {}, {}
	add(self, friends, false, online)
	add(self, guildmates, true, online)
end

-- Whether Mnemosyne talks with a character: anyone while everyone is on, else
-- a friend or a guildmate.
function Scope:allows(name)
	return self.settings.everyone == true or self.names[key(name)] == true
end

-- Whether a character is on the guild roster, whoever Mnemosyne talks with.
function Scope:isGuildmate(name)
	return self.guildmates[key(name)] == true
end

-- Every friend and guildmate, as read: an array of full names.
function Scope:listed()
	return self.read
end

-- The friends and guildmates online, as a set of full names of its own.
function Scope:online()
	local online = {}
	for name in pairs(self.onlineNames) do
		online[name] = true
	end
	return online
end
