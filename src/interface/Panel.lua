-- Panel: the settings panel, one Mnemosyne page in the game's Options, AddOns,
-- also opened from the addon compartment (the minimap's addon drawer) and by
-- /mnemosyne alone. Part of the Interface adapter (decision 0004): it draws,
-- with the Settings panel's own templates, what the rest decides. The
-- registration buttons run the commands and the prompt's Keep anonymous, the
-- switches are the saved settings (Client's DEFAULTS), the Status is the status
-- command's, with a button for the report command, and Recognition:rows gives
-- the list of identities.
local addonName, ns = ...

local L = ns.L
local Client = ns.Client
local Interface = ns.Interface
local commands = ns.commands

local WIDTH = 600 -- of the page's content; the Settings canvas is about 650 wide
local INDENT = 37 -- a label's inset under a section header, as in the Settings list
local COLUMN = 220 -- where the controls start, as the Settings list's checkboxes do
local LINE = 26
local MAX_ROWS = 50 -- rows the list shows before it says how many more it found
local ROW = 22

-- The switches: the setting's key, its label and its tooltip.
local SWITCHES = {
	{ "tooltip", L.PANEL_TOOLTIP, L.PANEL_TOOLTIP_HELP },
	{ "chat", L.PANEL_CHAT, L.PANEL_CHAT_HELP },
	{ "showSecondHand", L.PANEL_SECOND_HAND, L.PANEL_SECOND_HAND_HELP },
	{ "passOn", L.PANEL_PASS_ON, L.PANEL_PASS_ON_HELP },
	{ "everyone", L.PANEL_EVERYONE, L.PANEL_EVERYONE_HELP },
	{ "askStrangers", L.PANEL_ASK_STRANGERS, L.PANEL_ASK_STRANGERS_HELP },
	{ "offerReport", L.PANEL_OFFER_REPORT, L.PANEL_OFFER_REPORT_HELP },
}

-- The list's columns: the row field each shows, its x and its width.
local COLUMNS = {
	{ "name", L.PANEL_COLUMN_CHARACTER, 7, 150 },
	{ "nickname", L.PANEL_COLUMN_NICKNAME, 160, 120 },
	{ "heard", L.PANEL_COLUMN_HEARD, 285, 140 },
	{ "ago", L.PANEL_COLUMN_AGO, 430, 95 },
}

local page = CreateFrame("Frame")
page:Hide()
local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(WIDTH, 1)
scroll:SetScrollChild(content)

local function header(parent, top, text)
	local frame = CreateFrame("Frame", nil, parent, "SettingsListSectionHeaderTemplate")
	frame:SetSize(WIDTH, 45)
	frame:SetPoint("TOPLEFT", 0, -top)
	frame.Title:SetText(text)
	return 45
end

local function text(parent, font, x, top, width)
	local label = parent:CreateFontString(nil, "OVERLAY", font)
	label:SetPoint("TOPLEFT", x, -top)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	return label
end

-- Widens a button to fit the longest of its labels, so no translation spills out
-- of it; it is left showing the last one.
local function fit(frame, ...)
	local width = frame:GetWidth()
	for i = 1, select("#", ...) do
		frame:SetText((select(i, ...)))
		width = math.max(width, frame:GetFontString():GetStringWidth() + 24)
	end
	frame:SetWidth(width)
end

-- A button at least width wide, wider if its label needs it. A negative x places
-- its right edge that far from the parent's left, so it grows to the left.
local function button(parent, label, x, top, width, onClick)
	local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	frame:SetSize(width, 22)
	fit(frame, label)
	if x < 0 then
		frame:SetPoint("TOPRIGHT", parent, "TOPLEFT", -x, -top)
	else
		frame:SetPoint("TOPLEFT", x, -top)
	end
	frame:SetScript("OnClick", onClick)
	return frame
end

local title = text(content, "GameFontHighlightHuge", 7, 0, WIDTH)
title:SetText(addonName)
-- The fixed part of the page is laid out top to bottom: y is where the next
-- piece goes.
local y = 24

-- This character: its registration, the nickname and the buttons, or why a
-- trial account cannot register.
local refresh, refreshList
y = y + header(content, y, L.PANEL_CHARACTER)
local registration = text(content, "GameFontHighlight", INDENT, y, WIDTH - INDENT)
y = y + LINE
local cannotRegister = text(content, "GameFontRed", INDENT, y, WIDTH - INDENT)
cannotRegister:SetText(L.PANEL_CANNOT_REGISTER)
local controls = CreateFrame("Frame", nil, content)
controls:SetPoint("TOPLEFT", 0, -y)
controls:SetSize(WIDTH, 2 * LINE)
text(controls, "GameFontNormal", INDENT, 4, COLUMN - INDENT):SetText(L.PANEL_NICKNAME)
local nickname = CreateFrame("EditBox", nil, controls, "InputBoxTemplate")
nickname:SetSize(180, 20)
nickname:SetPoint("TOPLEFT", COLUMN + 6, 0)
nickname:SetAutoFocus(false)
nickname:SetMaxLetters(ns.Protocol.MAX_NICKNAME_CHARACTERS)
local function register()
	-- Like the command: says in the chat frame why a nickname breaks the rules.
	if commands.register(nickname:GetText()) then
		nickname:ClearFocus()
	end
	refresh()
end
nickname:SetScript("OnEscapePressed", nickname.ClearFocus)
local registerButton = button(controls, L.PANEL_REGISTER, COLUMN, LINE, 110, register)
fit(registerButton, L.PANEL_CHANGE, L.PANEL_REGISTER) -- refresh switches it to Change
-- As in the prompt: nothing to register while the nickname is empty.
local function enableRegister()
	registerButton:SetEnabled(nickname:GetText():find("%S") ~= nil)
end
nickname:SetScript("OnTextChanged", enableRegister)
nickname:SetScript("OnEnterPressed", function()
	if registerButton:IsEnabled() then
		register()
	end
end)
local unregisterButton = button(controls, L.PANEL_UNREGISTER, COLUMN + 114, LINE, 110, function()
	commands.unregister()
	refresh()
end)
local anonymousButton = button(controls, L.PROMPT_ANONYMOUS, COLUMN + 228, LINE, 130, function()
	Interface.keepAnonymous()
	refresh()
end)
-- Each after the one before, however wide its translation made it.
unregisterButton:ClearAllPoints()
unregisterButton:SetPoint("LEFT", registerButton, "RIGHT", 4, 0)
anonymousButton:ClearAllPoints()
anonymousButton:SetPoint("LEFT", unregisterButton, "RIGHT", 4, 0)
y = y + 2 * LINE

-- The switches, each saved as it is clicked and read where it is used.
y = y + header(content, y, L.PANEL_SWITCHES)
local checkboxes = {}
for _, switch in ipairs(SWITCHES) do
	local key, label, help = switch[1], switch[2], switch[3]
	text(content, "GameFontNormal", INDENT, y + 7, COLUMN - INDENT):SetText(label)
	local checkbox = CreateFrame("CheckButton", nil, content, "SettingsCheckboxTemplate")
	checkbox:SetPoint("TOPLEFT", COLUMN, -y)
	checkbox:SetTooltipFunc(function()
		Settings.InitTooltip(label, help)
	end)
	checkbox:SetScript("OnClick", function()
		MnemosyneDB.settings[key] = checkbox:GetChecked()
		refresh() -- Show second-hand changes the status and the list
	end)
	checkboxes[key] = checkbox
	y = y + LINE
end

-- The status, whose lines may wrap: the list goes below them.
y = y + header(content, y, L.PANEL_STATUS)
-- On the header's line. commands.report is looked up on click (ReportWindow loads
-- after this file); its window is DIALOG strata, above the Settings panel's HIGH.
button(content, L.PANEL_REPORT, -WIDTH, y - 33, 130, function()
	commands.report()
end)
local status = text(content, "GameFontHighlight", INDENT, y, WIDTH - INDENT)
status:SetSpacing(4)

-- The list of identities, with its search box.
local list = CreateFrame("Frame", nil, content)
list:SetPoint("TOPLEFT", status, "BOTTOMLEFT", -INDENT, 0)
list:SetWidth(WIDTH)
header(list, 0, L.PANEL_IDENTITIES)
local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
search:SetSize(240, 20)
search:SetPoint("TOPLEFT", INDENT + 6, -45)
search.Instructions:SetText(L.PANEL_SEARCH)
search:HookScript("OnTextChanged", function()
	refreshList()
end)
for _, column in ipairs(COLUMNS) do
	text(list, "GameFontNormalSmall", column[3], 75, column[4]):SetText(column[2])
end
local LIST_TOP = 95 -- where the first row goes in the list
local more = text(list, "GameFontDisableSmall", 7, 0, WIDTH - 7)

local rows = {}
local function rowFrame(i)
	if not rows[i] then
		local row = CreateFrame("Frame", nil, list)
		row:SetSize(WIDTH, ROW)
		row:SetPoint("TOPLEFT", 0, -(LIST_TOP + (i - 1) * ROW))
		for _, column in ipairs(COLUMNS) do
			row[column[1]] = text(row, "GameFontHighlightSmall", column[3], 5, column[4])
			row[column[1]]:SetWordWrap(false)
		end
		row.button = button(row, "", -595, 0, 70, function(self)
			local name = self:GetParent().name:GetText()
			if self:GetParent().forgotten then
				commands.unforget(name)
			else
				commands.forget(name)
			end
			refresh()
		end)
		fit(row.button, L.PANEL_FORGET, L.PANEL_UNDO)
		rows[i] = row
	end
	return rows[i]
end

function refresh()
	if not Client.playerName() then
		return -- before login: nothing to show yet
	end
	local canSend = Client.canSend()
	registration:SetText(ns.registrationLine())
	controls:SetShown(canSend)
	cannotRegister:SetShown(not canSend)
	local name = Client.playerName()
	local state = ns.characters:state(name)
	if not nickname:HasFocus() then
		local offer = ns.characters:prompt(name, ns.memory:recall(name))
		local current = ns.characters:registration(name)
		nickname:SetText((current and current.nickname) or (offer and offer.nickname) or "")
	end
	enableRegister()
	registerButton:SetText(state == "registered" and L.PANEL_CHANGE or L.PANEL_REGISTER)
	unregisterButton:SetEnabled(state == "registered")
	anonymousButton:SetEnabled(state ~= "anonymous")

	for key, checkbox in pairs(checkboxes) do
		checkbox:SetChecked(MnemosyneDB.settings[key])
	end

	status:SetText(table.concat(ns.statusLines(), "\n"))
	refreshList()
end

-- The identities found for the search, apart from the rest: each key typed
-- redraws only the list.
function refreshList()
	if not Client.playerName() then
		return
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
		frame:Show()
	end
	for i = #found + 1, #rows do
		rows[i]:Hide()
	end
	more:SetPoint("TOPLEFT", 7, -(LIST_TOP + #found * ROW + 4))
	more:SetText(total > MAX_ROWS and L.LOOKUP_MORE:format(total - MAX_ROWS) or (total == 0 and L.PANEL_NONE or ""))
	local listHeight = LIST_TOP + #found * ROW + 30
	list:SetHeight(listHeight)
	content:SetHeight(y + status:GetStringHeight() + listHeight)
end

-- The Settings panel calls these on a canvas page: each time it shows it, and when
-- the player resets all settings to their defaults, which puts every switch
-- back on.
page.OnRefresh = refresh
function page.OnDefault()
	for key, value in pairs(Client.DEFAULTS) do
		MnemosyneDB.settings[key] = value
	end
	refresh()
end

local category = Settings.RegisterCanvasLayoutCategory(page, addonName)
Settings.RegisterAddOnCategory(category)

local function open()
	Settings.OpenToCategory(category:GetID())
end
commands[""] = open

-- The addon compartment calls it by name (AddonCompartmentFunc in the .toc).
function Mnemosyne_OnAddonCompartmentClick()
	open()
end
