-- CommunitiesTab: an Identities tab and a Professions tab in the Guild &
-- Communities window, under its guild tabs (after Preferred Play Settings),
-- showing the same views as Mnemosyne's window's tabs. Part of the Interface
-- adapter (decision 0004).
--
-- The window's own tabs each set a display mode, a list of its subframes to
-- show (COMMUNITIES_FRAME_DISPLAY_MODES). Adding a mode would write into
-- Blizzard's table and taint the window, so these tabs are none: while one is
-- selected it hides the subframes the current mode shows (but the list of
-- communities and the buttons under it) and shows its view in their place;
-- the other of ours swaps the view only. Selecting one of the window's tabs
-- gives them back: a new mode shows its own, and the same mode, which the
-- window would not set again, gets back the ones hidden.
local _, ns = ...

local L = ns.L

local WIDTH = 628 -- right of the list of communities, in the window's 814

-- Our tabs, top to bottom: the view each builds, its icon (the micro menu's
-- buttons') and its tooltip.
local OURS = {
	{ newView = ns.Identities.newView, icon = "UI-HUD-MicroMenu-GuildCommunities-Up", tooltip = L.PANEL_IDENTITIES },
	{ newView = ns.ProfessionsTab.newView, icon = "UI-HUD-MicroMenu-Professions-Up", tooltip = L.PROFESSIONS },
}

-- The window's tabs, by the display mode they select.
local TABS = {
	CHAT = "ChatTab",
	ROSTER = "RosterTab",
	GUILD_APPLICANT_LIST = "RosterTab",
	COMMUNITY_APPLICANT_LIST = "RosterTab",
	GUILD_BENEFITS = "GuildBenefitsTab",
	GUILD_INFO = "GuildInfoTab",
	GUILD_PREFERRED_PLAY_SETTINGS = "GuildPreferredPlaySettingsTab",
}
local KEPT = { CommunitiesList = true, CommunitiesControlFrame = true }

EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function()
	local communities = CommunitiesFrame

	for _, ours in ipairs(OURS) do
		local view = CreateFrame("Frame", nil, communities)
		-- Right of the list of communities, under the header row (dropdowns), as
		-- Guild Info's panel; the inset spans the whole window.
		view:SetPoint("TOPLEFT", communities.CommunitiesList, "TOPRIGHT", 11, -38)
		view:SetPoint("BOTTOMRIGHT", CommunitiesFrameInset, "BOTTOMRIGHT", -4, 4)
		view:Hide()
		ours.newView(view, WIDTH)
		ns.Window.addView(view)
		ours.view = view

		local tab = CreateFrame("CheckButton", nil, communities, "RightSideTabTemplate")
		tab:SetFrameLevel(510) -- as the window's own tabs
		tab.Icon:SetAtlas(ours.icon)
		tab.tooltip = ours.tooltip
		tab:Hide()
		ours.tab = tab
	end

	local selected -- the one of OURS that shows, or nil
	local hidden -- the subframes hidden for it, and the mode they belong to
	local hiddenMode

	-- The window's tab key for the mode it shows, or nil.
	local function modeTab()
		local mode = communities:GetDisplayMode()
		for key, frames in pairs(COMMUNITIES_FRAME_DISPLAY_MODES) do
			if frames == mode then
				return TABS[key] and communities[TABS[key]]
			end
		end
	end

	local function checkTabs()
		local current = modeTab()
		for _, key in pairs(TABS) do
			communities[key]:SetChecked(not selected and communities[key] == current)
		end
		for _, ours in ipairs(OURS) do
			ours.tab:SetChecked(ours == selected)
		end
	end

	-- Shows one of OURS: in place of the mode's subframes, or of the other's view.
	local function select(ours)
		if selected == ours then
			return
		end
		if selected then
			selected.view:Hide()
		else
			hidden, hiddenMode = {}, communities:GetDisplayMode()
			for _, key in ipairs(hiddenMode or {}) do
				local subframe = communities[key]
				if not KEPT[key] and subframe and subframe:IsShown() then
					subframe:Hide()
					hidden[#hidden + 1] = subframe
				end
			end
		end
		selected = ours
		ours.view:Show()
		checkTabs()
	end

	-- Gives back the subframes hidden, unless the window has since set a mode:
	-- it has then shown that mode's own.
	local function leave()
		if not selected then
			return
		end
		selected.view:Hide()
		selected = nil
		if hidden and communities:GetDisplayMode() == hiddenMode then
			for _, subframe in ipairs(hidden) do
				subframe:Show()
			end
		end
		hidden, hiddenMode = nil, nil
		checkTabs()
	end

	for _, ours in ipairs(OURS) do
		ours.tab:SetScript("OnClick", function(self)
			RightSideTabMixin.OnClick(self)
			select(ours)
		end)
	end
	for _, key in pairs(TABS) do
		communities[key]:HookScript("OnClick", leave)
	end
	communities:RegisterCallback(CommunitiesFrameMixin.Event.DisplayModeChanged, leave, OURS)
	communities:HookScript("OnHide", leave)

	-- Shown with the guild tabs, under the last one shown, each under the one before.
	hooksecurefunc(communities, "UpdateCommunitiesTabs", function()
		local above = communities.GuildPreferredPlaySettingsTab:IsShown() and communities.GuildPreferredPlaySettingsTab
			or communities.GuildInfoTab
		local guild = communities.GuildInfoTab:IsShown()
		for _, ours in ipairs(OURS) do
			ours.tab:ClearAllPoints()
			ours.tab:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -20)
			ours.tab:SetShown(guild)
			above = ours.tab
		end
		if guild then
			checkTabs()
		else
			leave()
		end
	end)
end)
