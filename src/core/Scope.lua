-- Scope: whom Mnemosyne talks with (decision 0007). By default only friends
-- (the friend list and Battle.net friends' characters) and guildmates; with
-- "Talk with everyone" on, anyone. Pure: Client reads the lists from the game
-- and adds each name (decision 0004).
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
	return setmetatable({ settings = settings, names = {} }, Scope)
end

-- Forgets every friend and guildmate, before the lists are read again.
function Scope:reset()
	self.names = {}
end

-- Adds a friend's or a guildmate's name; a missing or empty one is ignored.
function Scope:add(name)
	if type(name) == "string" and name ~= "" then
		self.names[key(name)] = true
	end
end

-- Whether Mnemosyne talks with a character: anyone while everyone is on, else
-- a friend or a guildmate.
function Scope:allows(name)
	return self.settings.everyone == true or self.names[key(name)] == true
end
