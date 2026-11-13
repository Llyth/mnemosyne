-- ReportWindow: /mnemosyne report, and the offer to report after one of
-- Mnemosyne's own Lua errors. Part of the Interface adapter (decision 0004):
-- Report builds the text and the link; this file gathers the facts from the
-- game, catches the errors and shows the window. Nothing leaves the game by
-- itself: the player copies the link or the text (docs/agents/wow-api.md).
local addonName, ns = ...

local L = ns.L
local Report = ns.Report

local OFFER = "MNEMOSYNE_REPORT_ERROR"

local window, linkBox, textBox

-- The facts of the report, read from the game now.
local function facts()
	local db = MnemosyneDB
	local _, build, _, interface = GetBuildInfo()
	local settings = { debug = db.debug }
	for key, value in pairs(db.settings) do
		settings[key] = value
	end
	return {
		version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?",
		build = build,
		interface = interface,
		locale = GetLocale(),
		now = GetServerTime(),
		settings = settings,
		counts = {
			identities = ns.memory:count(),
			registered = ns.characters:count("registered"),
			anonymous = ns.characters:count("anonymous"),
		},
	}
end

-- An edit box that only shows its text, selected for Ctrl+C when it has the
-- focus: typing in it puts the text back.
local function copyBox(box)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(self.copy)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEscapePressed", function()
		window:Hide()
	end)
end

local function setCopy(box, text)
	box.copy = text
	box:SetText(text)
	box:SetCursorPosition(0)
end

local function create()
	window = CreateFrame("Frame", "MnemosyneReportWindow", UIParent, "BasicFrameTemplateWithInset")
	window:SetSize(560, 420)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	table.insert(UISpecialFrames, window:GetName()) -- Escape closes it

	local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)
	title:SetText(L.REPORT_TITLE)

	local linkLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	linkLabel:SetPoint("TOPLEFT", 16, -36)
	linkLabel:SetPoint("RIGHT", -16, 0)
	linkLabel:SetJustifyH("LEFT")
	linkLabel:SetText(L.REPORT_LINK)

	linkBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
	linkBox:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -8)
	linkBox:SetPoint("RIGHT", -16, 0)
	linkBox:SetHeight(20)
	copyBox(linkBox)

	local textLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	textLabel:SetPoint("TOPLEFT", linkBox, "BOTTOMLEFT", -6, -16)
	textLabel:SetPoint("RIGHT", -16, 0)
	textLabel:SetJustifyH("LEFT")
	textLabel:SetText(L.REPORT_TEXT)

	local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	textBox = CreateFrame("EditBox", nil, scroll)
	textBox:SetMultiLine(true)
	textBox:SetFontObject("ChatFontNormal")
	textBox:SetWidth(500)
	scroll:SetScrollChild(textBox)
	copyBox(textBox)
end

-- Shows the window with the link and the full text, the link selected.
local function show()
	if not window then
		create()
	end
	local db = MnemosyneDB
	local reportFacts = facts()
	local text = Report.text(reportFacts, db.events, db.errors, db.salt)
	setCopy(linkBox, Report.link(text, reportFacts.version))
	setCopy(textBox, text)
	window:Show()
	linkBox:SetFocus()
end

ns.commands.report = show

StaticPopupDialogs[OFFER] = {
	text = L.REPORT_OFFER,
	button1 = L.REPORT_SHOW,
	button2 = L.REPORT_NOT_NOW,
	button3 = L.REPORT_NEVER,
	selectCallbackByIndex = true,
	timeout = 0,
	hideOnEscape = 1,
	OnButton1 = show,
	OnButton2 = function() end,
	OnButton3 = function()
		MnemosyneDB.settings.offerReport = false
	end,
}

-- The offer opens once a session, after combat, unless the player said
-- "Don't ask again".
local offered = false
local frame = CreateFrame("Frame")

local function offer()
	if offered or not MnemosyneDB.settings.offerReport then
		return
	end
	if InCombatLockdown() then
		frame:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	offered = true
	StaticPopup_Show(OFFER)
end

frame:SetScript("OnEvent", function()
	frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
	offer()
end)

-- Keeps one of Mnemosyne's own errors for the report and offers the report,
-- then hands every error on to the handler that was there before.
local previous = geterrorhandler()
local function catch(message)
	local db = MnemosyneDB
	if type(message) == "string" and db and db.errors and Report.isOwnError(message, addonName) then
		Report.keep(db.errors, { at = GetServerTime(), message = message }, Report.MAX_ERRORS)
		C_Timer.After(0, offer)
	end
end
seterrorhandler(function(message, ...)
	pcall(catch, message) -- an error here must not hide the one being handled
	return previous(message, ...)
end)
