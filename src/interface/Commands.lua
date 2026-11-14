-- Commands: the slash commands that read the memory and the debug log
-- (lookup, status, debug, echo, sync, forget, unforget). Part of the Interface
-- adapter (decision 0004): it adds to the commands table of Interface.lua.
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

-- This character's registration, in words.
function ns.registrationLine()
	local characters = ns.characters
	local name = Client.playerName()
	local state = characters:state(name)
	if state == "registered" then
		return L.STATUS_REGISTERED:format(characters:registration(name).nickname)
	elseif state == "anonymous" then
		return L.STATUS_ANONYMOUS
	elseif state == "unregistered" then
		return L.STATUS_UNREGISTERED
	end
	return L.STATUS_NOT_ASKED
end

-- What the memory holds and whom it synced with, as lines: the status command
-- and the settings panel's Status.
function ns.statusLines()
	local syncs = {}
	for i, synced in ipairs(ns.sync:recent()) do
		syncs[i] = L.STATUS_SYNC:format(synced.peer, ns.recognition:ago(synced.at))
	end
	return {
		L.STATUS_IDENTITIES:format(ns.recognition:count()),
		L.STATUS_CHARACTERS:format(ns.characters:count("registered"), ns.characters:count("anonymous")),
		L.STATUS_PEERS:format(Client.peerCount()),
		syncs[1] and L.STATUS_SYNCS:format(table.concat(syncs, ", ")) or L.STATUS_NO_SYNC,
	}
end

function commands.status()
	for _, line in ipairs(ns.statusLines()) do
		say(line)
	end
	say(ns.registrationLine())
	if not Client.canSend() then
		say(L.STATUS_CANNOT_SEND)
	end
end

function commands.debug(text)
	if text:lower() == "copy" then
		ns.showDebugLog() -- ReportWindow loads after this file
		return
	end
	say(ns.Debug.toggle() and L.DEBUG_ON or L.DEBUG_OFF)
end

function commands.echo()
	say(Client.toggleEcho() and L.ECHO_ON or L.ECHO_OFF)
end

function commands.sync()
	local count = Client.sync()
	say(count > 0 and L.SYNC_STARTED:format(count) or L.SYNC_NONE)
end

-- The forgotten characters, or how to forget one.
local function sayForgotten()
	local names = ns.memory:forgotten()
	say(names[1] and L.FORGOTTEN_LIST:format(table.concat(names, ", ")) or L.FORGOTTEN_NONE)
end

-- The full name held or forgotten that the player typed, else the text as
-- typed when it is a full name ("First Last"); nil after saying so.
local function fullName(text)
	local name = ns.memory:fullName(text) or (text:find(" ", 1, true) and text)
	if not name then
		say(L.FORGET_FULL_NAME)
	end
	return name
end

function commands.forget(text)
	if text == "" then
		sayForgotten()
		return
	end
	local name = fullName(text)
	if not name then
		return
	end
	say((ns.memory:forget(name) and L.FORGOTTEN or L.ALREADY_FORGOTTEN):format(name, name))
end

function commands.unforget(text)
	if text == "" then
		sayForgotten()
		return
	end
	local name = ns.memory:fullName(text) or text
	say((ns.memory:unforget(name) and L.UNFORGOTTEN or L.NOT_FORGOTTEN):format(name))
end
