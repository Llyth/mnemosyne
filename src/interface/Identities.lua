-- Identities: the window's first tab, the list of identities that was the
-- settings panel's. Part of the Interface adapter (decision 0004): it draws
-- what Recognition:rows gives (one row per character, by nickname) with the
-- forget, undo and whisper actions, and Recognition:syncStatus in its footer.
local _, ns = ...

local L = ns.L
local Client = ns.Client
local commands = ns.commands
local text, fit, button = ns.widgets.text, ns.widgets.fit, ns.widgets.button

local WIDTH = ns.Window.WIDTH
local MAX_ROWS = 50 -- rows the list shows before it says how many more it found
local ROW = 22
local STATUS_EVERY = 5 -- seconds between two redraws of the sync status

-- The list's columns: the row field each shows, its x and its width.
local COLUMNS = {
	{ "name", L.PANEL_COLUMN_CHARACTER, 7, 150 },
	{ "nickname", L.PANEL_COLUMN_NICKNAME, 160, 120 },
	{ "heard", L.PANEL_COLUMN_HEARD, 285, 140 },
	{ "ago", L.PANEL_COLUMN_AGO, 430, 85 },
}

local tab = ns.Window.addTab("identities", L.PANEL_IDENTITIES)
local refresh

local search = CreateFrame("EditBox", nil, tab, "SearchBoxTemplate")
search:SetSize(240, 20)
search:SetPoint("TOPLEFT", 12, -4)
search.Instructions:SetText(L.PANEL_SEARCH)
search:HookScript("OnTextChanged", function()
	refresh()
end)
for _, column in ipairs(COLUMNS) do
	text(tab, "GameFontNormalSmall", column[3], 34, column[4]):SetText(column[2])
end

-- The sync status, under the list, redrawn every few seconds while it shows.
local footer = CreateFrame("Frame", nil, tab)
footer:SetPoint("BOTTOMLEFT", 0, 0)
footer:SetSize(WIDTH, 20)
local status = text(footer, "GameFontHighlightSmall", 7, 4, WIDTH - 7)
local function refreshStatus()
	status:SetText(ns.recognition:syncStatus(ns.sync:recent(), ns.sync:waitingCount()))
end
local sinceStatus = 0
footer:SetScript("OnUpdate", function(_, elapsed)
	sinceStatus = sinceStatus + elapsed
	if sinceStatus >= STATUS_EVERY then
		sinceStatus = 0
		refreshStatus()
	end
end)

local scroll = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -52)
scroll:SetPoint("BOTTOMRIGHT", -28, 24)
local list = CreateFrame("Frame", nil, scroll)
list:SetSize(WIDTH - 28, 1)
scroll:SetScrollChild(list)
local more = text(list, "GameFontDisableSmall", 7, 0, WIDTH - 35)

local rows = {}
local function rowFrame(i)
	if not rows[i] then
		local row = CreateFrame("Frame", nil, list)
		row:SetSize(WIDTH - 28, ROW)
		row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW))
		for _, column in ipairs(COLUMNS) do
			row[column[1]] = text(row, "GameFontHighlightSmall", column[3], 5, column[4])
			row[column[1]]:SetWordWrap(false)
		end
		row.button = button(row, "", -665, 0, 70, function(self)
			local name = self:GetParent().name:GetText()
			if self:GetParent().forgotten then
				commands.unforget(name)
			else
				commands.forget(name)
			end
			refresh()
		end)
		fit(row.button, L.PANEL_FORGET, L.PANEL_UNDO)
		row.whisper = button(row, L.WINDOW_WHISPER, 0, 0, 70, function(self)
			ChatFrameUtil.SendTell(self:GetParent().name:GetText())
		end)
		row.whisper:ClearAllPoints()
		row.whisper:SetPoint("RIGHT", row.button, "LEFT", -4, 0)
		rows[i] = row
	end
	return rows[i]
end

-- The identities found for the search, and the sync status.
function refresh()
	if not Client.playerName() then
		return -- before login: nothing to show yet
	end
	local found, total = ns.recognition:rows(search:GetText(), MAX_ROWS)
	for i, row in ipairs(found) do
		local frame = rowFrame(i)
		for _, column in ipairs(COLUMNS) do
			frame[column[1]]:SetText(row[column[1]])
		end
		frame.forgotten = row.forgotten
		frame.button:SetText(row.forgotten and L.PANEL_UNDO or L.PANEL_FORGET)
		frame.button:SetShown(not row.own) -- your own characters are never forgotten
		frame.whisper:SetShown(not row.own)
		frame:Show()
	end
	for i = #found + 1, #rows do
		rows[i]:Hide()
	end
	more:SetPoint("TOPLEFT", 7, -(#found * ROW + 4))
	more:SetText(total > MAX_ROWS and L.LOOKUP_MORE:format(total - MAX_ROWS) or (total == 0 and L.PANEL_NONE or ""))
	list:SetHeight(#found * ROW + 30)
	refreshStatus()
end
tab.refresh = refresh
tab:SetScript("OnShow", refresh)
