-- ReportWindow: /mnemosyne report, and the offer to report after one of
-- Mnemosyne's own Lua errors. Part of the Interface adapter (decision 0004):
-- Report builds the text and the link; this file gathers the facts from the
-- game, catches the errors and shows the window. Nothing leaves the game by
-- itself: the player copies the link or the text (docs/agents/wow-api.md).
local addonName, ns = ...

local L = ns.L
local Report = ns.Report

local OFFER = "MNEMOSYNE_REPORT_ERROR"

local window, title, linkLabel, linkBox, textLabel, textBox

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

	title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", 0, -5)

	linkLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	linkLabel:SetPoint("TOPLEFT", 16, -36)
	linkLabel:SetPoint("RIGHT", -16, 0)
	linkLabel:SetJustifyH("LEFT")
	linkLabel:SetText(L.REPORT_LINK)

	linkBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
	linkBox:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -8)
	linkBox:SetPoint("RIGHT", -16, 0)
	linkBox:SetHeight(20)
	copyBox(linkBox)

	textLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	textLabel:SetPoint("TOPLEFT", linkBox, "BOTTOMLEFT", -6, -16)
	textLabel:SetPoint("RIGHT", -16, 0)
	textLabel:SetJustifyH("LEFT")

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
	local text = Report.text(reportFacts, db.events, db.errors)
	title:SetText(L.REPORT_TITLE)
	linkLabel:Show()
	linkBox:Show()
	textLabel:SetText(L.REPORT_TEXT)
	setCopy(linkBox, Report.link(text, reportFacts.version))
	setCopy(textBox, text)
	window:Show()
	linkBox:SetFocus()
end

ns.commands.report = show

-- The same window with the session's debug log to copy (/mnemosyne debug
-- copy): the lines as printed, other players' names and nicknames included.
function ns.showDebugLog()
	if not window then
		create()
	end
	title:SetText(L.DEBUG_LOG_TITLE)
	linkLabel:Hide()
	linkBox:Hide()
	textLabel:SetText(L.DEBUG_LOG_TEXT)
	setCopy(textBox, ns.Debug.text())
	window:Show()
	textBox:SetFocus()
end

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
	-- Guarded: an error here would be caught and offer again, every frame.
	local settings = MnemosyneDB.settings
	if offered or not (settings and settings.offerReport) then
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

-- Keeps one of Mnemosyne's own errors for the report and offers the report.
local function catch(message)
	local db = MnemosyneDB
	if type(message) == "string" and db and db.errors then
		if Report.keepError(db.errors, message, GetServerTime(), addonName) then
			C_Timer.After(0, offer)
		end
	end
end

-- Without an error-catching addon: every error goes through catch, then on to
-- the handler that was there before.
local previous = geterrorhandler()
seterrorhandler(function(message, ...)
	pcall(catch, message) -- an error here must not hide the one being handled
	return previous(message, ...)
end)

-- With !BugGrabber (standalone, or embedded in another addon and loaded before
-- or after Mnemosyne): it replaces seterrorhandler with a no-op and does not
-- chain, but announces each error it grabs, which BugSack still shows.
EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, errorID)
	pcall(function()
		catch(BugGrabber:GetErrorByID(errorID).message)
	end)
end, {})
