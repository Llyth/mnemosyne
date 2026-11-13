-- Commands: the slash commands that read the memory and the debug log
-- (lookup, status, debug, sync). Part of the Interface adapter (decision
-- 0004): it adds to the commands table of Interface.lua.
local _, ns = ...

local L = ns.L
local Client = ns.Client
local say = ns.say
local commands = ns.commands

local MAX_FOUND = 20 -- lines a lookup prints before it says how many more it found

function commands.lookup(text)
	if text == "" then
		say(L.LOOKUP_EMPTY)
		return
	end
	local found = ns.recognition:search(text)
	if not found[1] then
		say(L.LOOKUP_NONE:format(text))
		return
	end
	for i = 1, math.min(#found, MAX_FOUND) do
		say(ns.recognition:lookupLine(found[i]))
	end
	if #found > MAX_FOUND then
		say(L.LOOKUP_MORE:format(#found - MAX_FOUND))
	end
end

function commands.status()
	local characters = ns.characters
	local name = Client.playerName()
	say(L.STATUS_IDENTITIES:format(ns.recognition:count()))
	say(L.STATUS_CHARACTERS:format(characters:count("registered"), characters:count("anonymous")))
	local state = characters:state(name)
	if state == "registered" then
		say(L.STATUS_REGISTERED:format(characters:registration(name).nickname))
	elseif state == "anonymous" then
		say(L.STATUS_ANONYMOUS)
	elseif state == "unregistered" then
		say(L.STATUS_UNREGISTERED)
	else
		say(L.STATUS_NOT_ASKED)
	end
	if not Client.canSend() then
		say(L.STATUS_CANNOT_SEND)
	end
end

function commands.debug()
	say(ns.Debug.toggle() and L.DEBUG_ON or L.DEBUG_OFF)
end

function commands.sync()
	local count = Client.sync()
	say(count > 0 and L.SYNC_STARTED:format(count) or L.SYNC_NONE)
end
