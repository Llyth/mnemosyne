-- ProgressTab: the window's Progress tab (decision 0009), and the Guild &
-- Communities window's (CommunitiesTab.lua). Part of the Interface adapter
-- (decision 0004): it draws what Grid gives, one sub-tab per category of
-- Milestones, looking up names, icons and tooltips in the game when shown.
local _, ns = ...

local L = ns.L
local Client = ns.Client
local Grid = ns.Grid
local text, button = ns.widgets.text, ns.widgets.button

local WIDTH = ns.Window.WIDTH
local ROW = 20 -- as ProfessionsTab's scrolled lists
local WHISPER = 74 -- right of the cells: the Whisper button
local SCROLL = 28 -- the scroll bar
local MAX_CELL = 120
local TOP = 78 -- the rows, under the sub-tabs, the search and the headers
local UNKNOWN_ICON = 134400 -- the question mark
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NONE = "-"
local GREY = 0.5

-- The sub-tabs, in order: the category of Milestones each shows, its label.
local CATEGORIES = {
	{ "attunements", L.PROGRESS_ATTUNEMENTS },
	{ "entrances", L.PROGRESS_ENTRANCES },
	{ "summons", L.PROGRESS_SUMMONS },
	{ "leveling", L.PROGRESS_LEVELING },
}

-- The instance IDs (GetRealZoneText) of the milestones named after a dungeon
-- or raid the game names; the others are the locale's (MILESTONE_*).
local ZONES = {
	onyxia = 249,
	moltenCore = 409,
	blackrockDepths = 230,
	direMaul = 429,
	scholomance = 289,
	stratholme = 329,
	scarletMonastery = 189,
	gnomeregan = 90,
	maraudon = 349,
}

local function milestoneName(milestone)
	local zone = ZONES[milestone.key] and GetRealZoneText(ZONES[milestone.key])
	if zone and zone ~= "" then
		return zone
	end
	return L["MILESTONE_" .. milestone.key:upper()] or milestone.key
end

-- An item's icon; the question mark until the game has it: its data is asked
-- for, and the views are drawn again once an item asked for arrives (not for
-- every item the game loads elsewhere).
local awaited, redrawPending = {}, false
local function itemIcon(item)
	local icon = C_Item.GetItemIconByID(item)
	if not icon and not awaited[item] then
		awaited[item] = true
		C_Item.RequestLoadItemDataByID(item)
	end
	return icon or UNKNOWN_ICON
end
local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, _, item)
	if awaited[item] then
		awaited[item] = nil
		if not redrawPending then
			redrawPending = true
			C_Timer.After(0.2, function()
				redrawPending = false
				ns.Window.refresh("progress")
			end)
		end
	end
end)

-- A character's nickname as it shows ("~" when second-hand) and bare, or nil.
local function nickname(name)
	local identity = ns.recognition:recall(name)
	if identity then
		return ns.recognition:nickname(identity), identity.nickname
	end
end

-- A row's name: "Nickname (Character Name)" when its identity shows.
local function label(row)
	return row.nickname and L.PROGRESS_NAME:format(row.nickname, row.name) or row.name
end

local function among(value, values)
	for _, candidate in ipairs(values or {}) do
		if candidate == value then
			return true
		end
	end
	return false
end

local function hideTooltip()
	GameTooltip:Hide()
end

-- A cell's tooltip: its quest's name, else its item's, else the milestone's
-- name; then why it shows so (heard from, disputed, not in Forever).
local function showCell(cell)
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	if cell.quest then
		local title = C_QuestLog.GetTitleForQuestID(cell.quest)
		if not title then
			C_QuestLog.RequestLoadQuestByID(cell.quest) -- for the next hover
		end
		GameTooltip:SetText(title or milestoneName(cell.milestone))
		GameTooltip:AddLine(cell.status, 1, 1, 1)
	elseif cell.item then
		GameTooltip:SetItemByID(cell.item)
	else
		GameTooltip:SetText(milestoneName(cell.milestone))
	end
	if cell.note then
		GameTooltip:AddLine(cell.note, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

-- Builds the progress view in content, viewWidth wide: Mnemosyne's window's
-- Progress tab, and the Guild & Communities window's. place names the view in
-- the saved last sub-tab (MnemosyneDB.window.progress). Each view keeps its
-- own sub-tab, search, sort and Show everyone.
local function newView(content, viewWidth, place)
	local refresh
	local LABEL = math.floor(190 * viewWidth / WIDTH)
	local grid, rows, columns -- the Grid, kept until the data changes; the rows and columns shown
	local sortBy -- the milestone ID sorted by, nil for by name
	local width -- of a cell

	local function category()
		local saved = MnemosyneDB.window.progress or {}
		MnemosyneDB.window.progress = saved
		for _, known in ipairs(CATEGORIES) do
			if known[1] == saved[place] then
				return known[1]
			end
		end
		return CATEGORIES[1][1]
	end

	local tabs = {}
	local x = 4
	for i, shown in ipairs(CATEGORIES) do
		tabs[i] = button(content, shown[2], x, 2, 80, function()
			MnemosyneDB.window.progress[place] = shown[1]
			sortBy = nil
			refresh()
		end)
		x = x + tabs[i]:GetWidth() + 4
	end

	local search = CreateFrame("EditBox", nil, content, "SearchBoxTemplate")
	search:SetSize(220, 20)
	search:SetPoint("TOPLEFT", 12, -30)
	search.Instructions:SetText(L.PANEL_SEARCH)
	ns.widgets.onSearch(search, function()
		refresh()
	end)
	local everyone = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	everyone:SetSize(24, 24)
	everyone:SetPoint("TOPLEFT", 244, -28)
	everyone:SetScript("OnClick", function()
		refresh()
	end)
	text(content, "GameFontHighlightSmall", 270, 34, 200):SetText(L.PROGRESS_EVERYONE)
	text(content, "GameFontNormalSmall", 7, 60, LABEL - 10):SetText(L.PANEL_COLUMN_CHARACTER)

	-- The column headers: a click sorts by the column, a second click by name.
	local headers = {}
	local function header(j)
		if not headers[j] then
			local frame = CreateFrame("Button", nil, content)
			frame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			frame.label = text(frame, "GameFontNormalSmall", 0, 3, 1)
			frame.label:SetWordWrap(false)
			frame:SetScript("OnClick", function(self)
				if not self.milestone.placeholder then
					sortBy = sortBy ~= self.milestone.id and self.milestone.id or nil
					refresh()
				end
			end)
			frame:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(milestoneName(self.milestone))
				if self.milestone.placeholder then
					GameTooltip:AddLine(L.PROGRESS_NOT_YET, 1, 1, 1)
				end
				GameTooltip:Show()
			end)
			frame:SetScript("OnLeave", hideTooltip)
			headers[j] = frame
		end
		return headers[j]
	end

	-- A gem mark's tooltip: the gem's, then who lacks it among the rows shown.
	local function showGem(gem)
		GameTooltip:SetOwner(gem, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(gem.item)
		local names = {}
		for i, row in ipairs(Grid.lacking(rows, gem.milestone, gem.index)) do
			names[i] = label(row)
		end
		if #names > 0 then
			GameTooltip:AddLine(L.PROGRESS_LACKED_BY:format(table.concat(names, ", ")), 1, 1, 1, true)
		end
		GameTooltip:Show()
	end

	local function newCell(row)
		local cell = CreateFrame("Frame", nil, row)
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", showCell)
		cell:SetScript("OnLeave", hideTooltip)
		cell.mark = cell:CreateTexture(nil, "ARTWORK")
		cell.mark:SetSize(14, 14)
		cell.mark:SetTexture(CHECK)
		cell.icon = cell:CreateTexture(nil, "ARTWORK")
		cell.icon:SetSize(16, 16)
		cell.text = text(cell, "GameFontHighlightSmall", 0, 4, 1)
		cell.text:SetWordWrap(false)
		cell.gems = {}
		for i = 1, 3 do
			local gem = CreateFrame("Frame", nil, cell)
			gem:SetSize(14, 14)
			gem:SetPoint("LEFT", (i - 1) * 15, 0)
			gem:EnableMouse(true)
			gem:SetScript("OnEnter", showGem)
			gem:SetScript("OnLeave", hideTooltip)
			gem.texture = gem:CreateTexture(nil, "ARTWORK")
			gem.texture:SetAllPoints()
			gem.index = i
			cell.gems[i] = gem
		end
		return cell
	end

	-- Draws a cell: ✓ and the item's icon; in progress, a short text and the
	-- icon of what it leads to, or Upper Blackrock Spire's three gems; else -.
	local function fillCell(cell, milestone, entry)
		cell.milestone, cell.item, cell.quest, cell.note, cell.status = milestone, nil, nil, nil, nil
		cell.mark:Hide()
		cell.icon:Hide()
		for _, gem in ipairs(cell.gems) do
			gem:Hide()
		end
		cell.text:SetTextColor(1, 1, 1)
		cell.text:SetPoint("TOPLEFT", 0, -4)
		cell.text:SetWidth(width - 2)
		cell:SetAlpha(entry and entry.source and 0.6 or 1)
		local shown = NONE
		if milestone.placeholder then
			cell.text:SetTextColor(GREY, GREY, GREY)
			cell.note = L.PROGRESS_NOT_YET
		elseif entry and entry.state == "done" then
			cell.item = entry.item or milestone.items[1]
			cell.mark:SetPoint("LEFT", 0, 0)
			cell.mark:Show()
			cell.icon:SetPoint("LEFT", 15, 0)
			cell.icon:SetTexture(itemIcon(cell.item))
			cell.icon:Show()
			shown = ""
		elseif entry and entry.state == "progress" then
			cell.quest, cell.item = entry.quest, entry.item
			if milestone.gems then
				local held = Grid.gems(entry)
				for i, gem in ipairs(cell.gems) do
					gem.item, gem.milestone = milestone.gems[i], milestone.id
					gem.texture:SetTexture(itemIcon(gem.item))
					gem.texture:SetDesaturated(not held[i])
					gem.texture:SetAlpha(held[i] and 1 or 0.35)
					gem:Show()
				end
				shown = among(entry.item, milestone.seals) and L.PROGRESS_SEAL or ""
				cell.text:SetPoint("TOPLEFT", 46, -4)
				cell.text:SetWidth(math.max(1, width - 48))
			else
				cell.item = cell.item or not cell.quest and milestone.items[1] or nil
				cell.icon:SetPoint("LEFT", 0, 0)
				cell.icon:SetTexture(itemIcon(entry.item or milestone.items[1]))
				cell.icon:Show()
				shown = L.PROGRESS_IN_PROGRESS
				cell.text:SetPoint("TOPLEFT", 18, -4)
				cell.text:SetWidth(math.max(1, width - 20))
			end
			cell.status = shown ~= "" and shown or L.PROGRESS_IN_PROGRESS
		elseif entry and entry.disputed then
			cell.note = L.PROGRESS_DISPUTED
		end
		if entry and entry.source then
			cell.note = L.PROGRESS_HEARD_FROM:format(entry.source)
			shown = shown ~= "" and L.SECOND_HAND:format(shown) or shown
		end
		cell.text:SetText(shown)
	end

	local list = ns.ProfessionsTab.scrolledList(
		content,
		0,
		TOP,
		viewWidth,
		{
			{ "label", 7, LABEL - 50 },
			{ "mark", LABEL - 42, 40 },
		},
		function() end,
		nil,
		function(row)
			row.cells = {}
			row.whisper = button(row, L.WINDOW_WHISPER, -(viewWidth - SCROLL - 2), 0, WHISPER - 4, function(self)
				ChatFrameUtil.SendTell(self:GetParent().character)
			end)
			row.whisper:SetHeight(ROW)
		end
	)

	local function fillRow(row, i)
		local shown = rows[i]
		row.character = shown.name
		row.label:SetText(label(shown))
		row.mark:SetText(shown.own and L.PANEL_YOURS or "")
		row.whisper:SetShown(not shown.own)
		for j, milestone in ipairs(columns) do
			row.cells[j] = row.cells[j] or newCell(row)
			local cell = row.cells[j]
			cell:SetSize(width, ROW)
			cell:SetPoint("TOPLEFT", LABEL + (j - 1) * width, 0)
			fillCell(cell, milestone, shown.cells[milestone.id])
			cell:Show()
		end
		for j = #columns + 1, #row.cells do
			row.cells[j]:Hide()
		end
	end

	function refresh()
		if not Client.playerName() then
			return -- before login: nothing to show yet
		end
		grid = grid
			or Grid.new(ns.progress:list(), MnemosyneDB.settings.showSecondHand, nickname, ns.characters:names())
		local shown = category()
		for i, tab in ipairs(tabs) do
			if CATEGORIES[i][1] == shown then
				tab:LockHighlight()
			else
				tab:UnlockHighlight()
			end
		end
		columns = Grid.columns(shown)
		width = math.min(MAX_CELL, math.floor((viewWidth - SCROLL - WHISPER - LABEL) / #columns))
		for j, milestone in ipairs(columns) do
			local frame = header(j)
			frame.milestone = milestone
			frame:SetSize(width - 2, 18)
			frame:SetPoint("TOPLEFT", LABEL + (j - 1) * width, -56)
			frame.label:SetWidth(width - 2)
			frame.label:SetText(milestoneName(milestone))
			local grey = milestone.placeholder and GREY
			frame.label:SetTextColor(grey or 1, grey or 0.82, grey or 0)
			if sortBy == milestone.id then
				frame:LockHighlight()
			else
				frame:UnlockHighlight()
			end
			frame:Show()
		end
		for j = #columns + 1, #headers do
			headers[j]:Hide()
		end
		rows = grid:rows(shown, search:GetText(), everyone:GetChecked(), sortBy)
		list:show(#rows, fillRow, L.PROGRESS_NONE)
	end
	-- From outside (Window.refresh, on showing), the progress, your own or the
	-- setting may have changed: the Grid is built again. A search, a sort or a
	-- sub-tab keeps it.
	local function rebuild()
		grid = nil
		refresh()
	end
	content.refresh = rebuild
	content:SetScript("OnShow", rebuild)
end

local ProgressTab = {}
ns.ProgressTab = ProgressTab
ProgressTab.newView = newView

newView(ns.Window.addTab("progress", L.PROGRESS), WIDTH, "window")
