-- Report: the debug report a player pastes in a bug report (/mnemosyne
-- report), and the link that opens the bug report form already filled in with
-- it. Pure: it takes the facts and the saved events and errors as
-- arguments (decision 0004); src/interface/ReportWindow.lua shows it.
--
-- Other players' names never appear in a report: an event names its peer only
-- by a label numbered within that report ("peer1", "peer2"...), so nothing in
-- it can be matched against a list of names (a short hash of the name could
-- be, from a guild roster). Events hold no nickname and no message text.
local _, ns = ...

local Report = {}
ns.Report = Report

Report.MAX_EVENTS = 200
Report.MAX_ERRORS = 5
-- A few KB: browsers and GitHub open a link this long. The full text is the fallback.
Report.MAX_LINK_BYTES = 4096

-- The form's query parameters are the field ids of .github/ISSUE_TEMPLATE/bug_report.yml.
local FORM = "https://github.com/Llyth/mnemosyne/issues/new?template=bug_report.yml"

-- Appends an entry to a saved list (the events, the errors) and drops the
-- oldest beyond max, so the list survives a /reload and stays bounded.
function Report.keep(list, entry, max)
	list[#list + 1] = entry
	while #list > max do
		table.remove(list, 1)
	end
end

-- A sync's identities, professions and chunks, hundreds at a time, would push every other
-- event out of the report.
local BULK = { identities = true, professions = true, chunk = true }

-- Keeps an event for the report, kind being the kind of message it is about,
-- if any: a sync's identities and chunks are left out, unless a send failed.
function Report.record(events, event, kind, failed)
	if failed or not BULK[kind] then
		Report.keep(events, event, Report.MAX_EVENTS)
	end
end

-- Whether a Lua error comes from one of this addon's files: its message starts
-- with the file's path, whatever path its text goes on to name. addonName is
-- the addon's folder.
function Report.isOwnError(message, addonName)
	local path = message:gsub("^Interface[/\\]", "", 1)
	local slash, backslash = "AddOns/" .. addonName .. "/", "AddOns\\" .. addonName .. "\\"
	return path:sub(1, #slash) == slash or path:sub(1, #backslash) == backslash
end

-- Keeps a Lua error from one of this addon's files in the saved errors, once
-- when it repeats back to back (an error every frame must not push out the
-- first). Returns whether it was one of ours, so the caller offers the report.
function Report.keepError(errors, message, at, addonName)
	if not Report.isOwnError(message, addonName) then
		return false
	end
	local last = errors[#errors]
	if not (last and last.message == message) then
		Report.keep(errors, { at = at, message = message }, Report.MAX_ERRORS)
	end
	return true
end

-- "a=1, b=2", sorted by key.
local function pairsText(values)
	local keys = {}
	for key in pairs(values) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for i, key in ipairs(keys) do
		keys[i] = key .. "=" .. tostring(values[key])
	end
	return table.concat(keys, ", ")
end

-- The report's text. facts: version, build, interface, locale, now (the server
-- time), settings and counts (tables of values). events: { at, what, peer,
-- detail }, oldest first, peer a character's name or nil. errors: { at,
-- message }, oldest first. Newest first in the text, so a link cut short
-- keeps the latest.
function Report.text(facts, events, errors)
	local lines = {
		"Mnemosyne " .. facts.version,
		("Client %s (Interface %s), %s"):format(facts.build, facts.interface, facts.locale),
		"Settings: " .. pairsText(facts.settings),
		"Counts: " .. pairsText(facts.counts),
		"Errors, newest first:",
	}
	for i = #errors, 1, -1 do
		lines[#lines + 1] = ("-%ds %s"):format(facts.now - errors[i].at, errors[i].message)
	end
	lines[#lines + 1] = "Events, newest first:"
	local labels, peers = {}, 0
	for i = #events, 1, -1 do
		local event = events[i]
		local peer = "-"
		if event.peer then
			if not labels[event.peer] then
				peers = peers + 1
				labels[event.peer] = "peer" .. peers
			end
			peer = labels[event.peer]
		end
		lines[#lines + 1] = ("-%ds %s %s %s"):format(facts.now - event.at, event.what, peer, event.detail)
	end
	return table.concat(lines, "\n")
end

local function encode(text)
	return (text:gsub("[^%w%-%._~]", function(character)
		return ("%%%02X"):format(character:byte())
	end))
end

local NEWLINE, CUT = encode("\n"), encode("\n...")

-- The link to the bug report form, pre-filled with the report and the
-- version. A report too long for MAX_LINK_BYTES is cut after its last whole
-- line that fits, marked "...".
function Report.link(text, version)
	local link = FORM .. "&version=" .. encode(version) .. "&report="
	local budget = Report.MAX_LINK_BYTES - #link - #CUT
	local parts = {}
	for line in (text .. "\n"):gmatch("(.-)\n") do
		local part = encode(line)
		local cost = #part + (parts[1] and #NEWLINE or 0)
		if cost > budget then
			return link .. table.concat(parts, NEWLINE) .. CUT
		end
		budget = budget - cost
		parts[#parts + 1] = part
	end
	return link .. table.concat(parts, NEWLINE)
end
