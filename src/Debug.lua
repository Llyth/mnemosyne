-- Debug: the log of every message sent and received, and of the ones dropped
-- with the reason, in the chat frame (/mnemosyne debug). Part of the adapters:
-- it prints. What a peer sent is printed through Protocol.printable, so it
-- shows as text and never runs as an escape sequence.
--
-- Each of these events is also kept, debug log on or off, in the last 200
-- events of the saved variables for the debug report (src/core/Report.lua): the
-- peer's name, the channel, the kind of message or the reason, never the text.
-- A sync's identities and chunks are left out, unless a send fails.
local _, ns = ...

local L = ns.L
local Report = ns.Report
local printable = ns.Protocol.printable

local Debug = {}
ns.Debug = Debug

local MAX_LINES = 500 -- log lines kept for /mnemosyne debug copy, the session's last
local lines = {}

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

-- Keeps an event for the debug report, once the saved variables are loaded.
local function record(what, peer, detail, kind, failed)
	if MnemosyneDB and MnemosyneDB.events then
		local event = { at = GetServerTime(), what = what, peer = peer, detail = detail }
		Report.record(MnemosyneDB.events, event, kind, failed)
	end
end

local function log(template, ...)
	if not Debug.isOn() then
		return
	end
	local values = { ... }
	for i = 1, select("#", ...) do
		values[i] = printable(tostring(values[i]))
	end
	local line = template:format(unpack(values, 1, select("#", ...)))
	lines[#lines + 1] = date("%H:%M:%S ") .. line
	if #lines > MAX_LINES then
		table.remove(lines, 1)
	end
	ns.say(line)
end

-- The log lines printed this session, oldest first, one a line.
function Debug.text()
	return table.concat(lines, "\n")
end

-- A message handed to the client: chatType, the target of a whisper, and the
-- kind of message ("ask", "announcement"...).
function Debug.sent(text, chatType, target, result, kind)
	local channel = target and (chatType .. " " .. target) or chatType
	local sent = result == Enum.SendAddonMessageResult.Success
	record("sent", target, ("%s %s %s"):format(chatType, kind, RESULT[result] or tostring(result)), kind, not sent)
	if sent then
		log(L.DEBUG_SENT, channel, text)
	else
		log(L.DEBUG_NOT_SENT, channel, RESULT[result] or result, text)
	end
end

function Debug.received(sender, channel, text, kind)
	record("received", sender, channel .. " " .. kind, kind)
	log(L.DEBUG_RECEIVED, sender, channel, text)
end

-- A message from a peer that Mnemosyne did not act on, and why.
function Debug.dropped(sender, reason, text)
	record("dropped", sender, reason)
	log(L.DEBUG_DROPPED, sender, reason, text)
end
