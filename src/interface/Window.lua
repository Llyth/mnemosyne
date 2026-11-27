-- Window: Mnemosyne's own window (decision 0008), opened from its button in
-- the Escape menu and by /mnemosyne alone. Part of the Interface adapter
-- (decision 0004). It moves, remembers where it was left and its last tab
-- (MnemosyneDB.window), and Escape closes it (UISpecialFrames). Each tab is a
-- file of its own that calls Window.addTab: Identities.lua first.
local addonName, ns = ...

local commands = ns.commands

local Window = {}
ns.Window = Window

Window.WIDTH = 700 -- of a tab's content
local HEIGHT = 520

local frame = CreateFrame("Frame", "MnemosyneWindow", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(Window.WIDTH + 24, HEIGHT)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	self:SetUserPlaced(false) -- saved in MnemosyneDB, not in the client's layout cache
	local point, _, relativePoint, x, y = self:GetPoint()
	MnemosyneDB.window.position = { point, relativePoint, x, y }
end)
frame:Hide()
table.insert(UISpecialFrames, frame:GetName()) -- Escape closes it

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
title:SetPoint("TOP", 0, -5)
title:SetText(addonName)

local tabs = {} -- { key, button, content }, in the order added

-- Shows the tab of that key, the first one when no tab has it.
local function select(key)
	local selected = tabs[1]
	for _, tab in ipairs(tabs) do
		if tab.key == key then
			selected = tab
		end
	end
	for i, tab in ipairs(tabs) do
		tab.content:SetShown(tab == selected)
		if tab == selected then
			PanelTemplates_SetTab(frame, i)
		end
	end
	MnemosyneDB.window.tab = selected.key
end

-- Adds a tab after the others, its button under the window showing label.
-- Returns its content frame: it fills the window and shows while the tab is
-- selected. A content frame with a refresh function is redrawn by
-- Window.refresh while it shows.
function Window.addTab(key, label)
	local i = #tabs + 1
	local button = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
	button:SetID(i)
	button:SetText(label)
	if i == 1 then
		button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
	else
		button:SetPoint("LEFT", tabs[i - 1].button, "RIGHT", 3, 0)
	end
	button:SetScript("OnClick", function()
		select(key)
	end)
	local content = CreateFrame("Frame", nil, frame)
	content:SetPoint("TOPLEFT", 12, -30)
	content:SetPoint("BOTTOMRIGHT", -12, 10)
	content:Hide()
	tabs[i] = { key = key, button = button, content = content }
	PanelTemplates_SetNumTabs(frame, i)
	return content
end

-- Opens the window where it was left, on the tab of that key, else on the last
-- one shown.
function Window.open(key)
	local position = MnemosyneDB.window.position
	if position then
		frame:ClearAllPoints()
		frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
	end
	frame:Show()
	select(key or MnemosyneDB.window.tab)
end

local views = {} -- frames outside the window that Window.refresh redraws too: { key, content }

-- Adds a frame with a refresh function, outside the window, that
-- Window.refresh redraws while it shows: the Guild & Communities window's
-- Identities, Professions and Progress tabs, under the key of the window's tab that
-- shows the same.
function Window.addView(content, key)
	views[#views + 1] = { key = key, content = content }
end

-- Redraws the tab that shows, and the views that show, after a change made
-- elsewhere: with a key ("professions"), only those of that key, the others
-- showing nothing the change touched; without, all (a setting, a forget).
function Window.refresh(key)
	for _, list in ipairs({ tabs, views }) do
		for _, shown in ipairs(list) do
			local content = shown.content
			if (not key or shown.key == key) and content:IsVisible() and content.refresh then
				content.refresh()
			end
		end
	end
end

commands[""] = function()
	Window.open()
end

-- The Escape menu's button, in the menu's list under Shop (or Options), as
-- EllesmereUI places its own: a frame of ours, a child of GameMenuFrame, placed
-- after each Layout of the menu, which moves Blizzard's buttons below it down
-- and grows the menu. Never GameMenuFrame:AddButton or a hook on InitButtons:
-- they would build it in Blizzard's pool and run its click tainted; moving
-- buttons only changes where they draw (decision 0008).
if GameMenuFrame then
	local menuButton = CreateFrame("Button", nil, GameMenuFrame, "MainMenuFrameButtonTemplate")
	menuButton:SetSize(200, 35)
	menuButton:SetText(addonName)
	menuButton:Hide()
	menuButton:SetScript("OnClick", function()
		HideUIPanel(GameMenuFrame)
		Window.open()
	end)
	-- EllesmereUIBlizzardSkin reskins the menu's pooled buttons only: style ours
	-- the way EllesmereUI styles its own custom menu buttons, so it matches.
	local eui = _G.EllesmereUI
	if
		eui
		and C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin")
		and not (_G.EllesmereUIDB and _G.EllesmereUIDB.reskinGameMenu == false)
	then
		for _, region in ipairs({ menuButton:GetRegions() }) do
			if region:IsObjectType("Texture") then
				region:SetAlpha(0)
			end
		end
		for _, key in ipairs({ "Left", "Middle", "Right" }) do
			local texture = menuButton[key]
			if texture then
				texture:SetAlpha(0)
				hooksecurefunc(texture, "SetAlpha", function(self, alpha)
					if alpha > 0 then
						self:SetAlpha(0)
					end
				end)
			end
		end
		local inset = CreateFrame("Frame", nil, menuButton)
		inset:SetPoint("TOPLEFT", 2, -2)
		inset:SetPoint("BOTTOMRIGHT", -2, 2)
		inset:SetFrameLevel(menuButton:GetFrameLevel())
		local background = inset:CreateTexture(nil, "BACKGROUND", nil, -6)
		background:SetAllPoints()
		local color = _G.EllesmereUIDB and _G.EllesmereUIDB.popupMenuButtonBackgroundColor
			or { r = 0.1, g = 0.1, b = 0.1, a = 0.8 }
		background:SetColorTexture(color.r, color.g, color.b, color.a or 0.8)
		if eui._applyBlizzardConfiguredBorder then
			eui._applyBlizzardConfiguredBorder(inset, "popupMenuButton", 1)
		end
		local highlight = menuButton:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints(inset)
		highlight:SetColorTexture(1, 1, 1, 0.1)
		local text = menuButton:GetFontString()
		local font = eui.GetFontPath and eui.GetFontPath("blizzardSkin")
		if text and font then
			local _, size, flags = text:GetFont()
			text:SetFont(font, (size or 14) - 2, flags or "")
			text:SetTextColor(1, 1, 1)
		end
	end
	local grownTo -- the menu's height as this hook last set it
	hooksecurefunc(GameMenuFrame, "Layout", function()
		if InCombatLockdown() then
			menuButton:Hide()
			return
		end
		local anchor
		for pooled in GameMenuFrame.buttonPool:EnumerateActive() do
			local label = pooled:GetText()
			if label == BLIZZARD_STORE then
				anchor = pooled
				break
			elseif label == GAMEMENU_OPTIONS then
				anchor = pooled
			end
		end
		if not anchor then
			menuButton:Hide()
			return
		end
		local width, height = anchor:GetSize()
		menuButton:SetSize(width, height)
		-- Below EllesmereUI's buttons when it shows them: it loads first, so its
		-- Layout hook has already placed them and pushed the rest down by its own.
		local above, gap = anchor, -12
		for _, name in ipairs({ "EllesmereUI_UnlockMenuButton", "EllesmereUI_GameMenuButton" }) do
			local other = _G[name]
			if other and other:IsShown() then
				above, gap = other, -4
				break
			end
		end
		menuButton:ClearAllPoints()
		menuButton:SetPoint("TOP", above, "BOTTOM", 0, gap)
		menuButton:Show()
		local added = height + 5
		for pooled in GameMenuFrame.buttonPool:EnumerateActive() do
			if pooled.layoutIndex and anchor.layoutIndex and pooled.layoutIndex > anchor.layoutIndex then
				local point, relativeTo, relativePoint, x, y = pooled:GetPoint(1)
				if point then
					pooled:ClearAllPoints()
					pooled:SetPoint(point, relativeTo, relativePoint, x, (y or 0) - added)
				end
			end
		end
		-- Layout may or may not set the height again, and EllesmereUI sets its own:
		-- a height still at what this hook set last time is grown already.
		local current = GameMenuFrame:GetHeight()
		if grownTo and math.abs(current - grownTo) < 0.5 then
			current = grownTo - added
		end
		grownTo = current + added
		GameMenuFrame:SetHeight(grownTo)
	end)
end
