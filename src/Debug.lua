-- Debug: the log of every message sent and received, and of the ones dropped
-- with the reason, in the chat frame (/mnemosyne debug). Part of the adapters:
-- it prints. What a peer sent is printed through Protocol.printable, so it
-- shows as text and never runs as an escape sequence.
local _, ns = ...

local L = ns.L
local printable = ns.Protocol.printable

local Debug = {}
ns.Debug = Debug

-- The name of each result of C_ChatInfo.SendAddonMessage, for the log.
local RESULT = {}
for name, value in pairs(Enum.SendAddonMessageResult) do
	RESULT[value] = name
end

function Debug.isOn()
	return MnemosyneDB ~= nil and MnemosyneDB.debug == true
end

-- Turns the log on or off, and remembers it across sessions. Returns whether
-- it is on.
function Debug.toggle()
	MnemosyneDB.debug = not Debug.isOn()
	return MnemosyneDB.debug
end

local function log(template, ...)
	if not Debug.isOn() then
		return
	end
	local values = { ... }
	for i = 1, select("#", ...) do
		values[i] = printable(tostring(values[i]))
	end
	ns.say(template:format(unpack(values, 1, select("#", ...))))
end

-- A message handed to the client: chatType, and the target of a whisper.
function Debug.sent(text, chatType, target, result)
	local channel = target and (chatType .. " " .. target) or chatType
	if result == Enum.SendAddonMessageResult.Success then
		log(L.DEBUG_SENT, channel, text)
	else
		log(L.DEBUG_NOT_SENT, channel, RESULT[result] or result, text)
	end
end

function Debug.received(sender, channel, text)
	log(L.DEBUG_RECEIVED, sender, channel, text)
end

-- A message from a peer that Mnemosyne did not act on, and why.
function Debug.dropped(sender, reason, text)
	log(L.DEBUG_DROPPED, sender, reason, text)
end
