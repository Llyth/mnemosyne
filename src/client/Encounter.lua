-- Encounter: asks a stranger who plays it when the player hovers or targets
-- it. Part of the Client adapter (decision 0004), in its own file: Strangers
-- decides whom to ask and when, this file reads the game and Client sends.
local _, ns = ...

local Client = ns.Client
local isKnown = Client.isKnown

local settings, strangers

-- Asks the player's character behind a unit ("mouseover" or "target"), unless
-- the switch is off, in combat or lockdown (nothing would go out), or the
-- unit is no player, hides its surname (a first name alone is no full name to
-- whisper), is of the other faction (whispers do not reach it) or is out of
-- scope (Client.inScope).
local function meet(unit)
	if not settings.askStrangers or Client.isPaused() then
		return
	end
	local isPlayer = UnitIsPlayer(unit)
	if not isKnown(isPlayer) or not isPlayer then
		return
	end
	local _, surname = UnitName(unit)
	if not isKnown(surname) or surname == "" then
		return
	end
	local faction = UnitFactionGroup(unit)
	if not isKnown(faction) or faction ~= UnitFactionGroup("player") then
		return
	end
	local name, player = GetUnitName(unit), Client.playerName()
	if isKnown(name) and player and Client.inScope(name) and strangers:ask(name, player) then
		Client.ask(name)
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
	if event == "UPDATE_MOUSEOVER_UNIT" then
		meet("mouseover")
	elseif event == "PLAYER_TARGET_CHANGED" then
		meet("target")
	else
		-- PLAYER_LOGIN: Client set MnemosyneDB up on ADDON_LOADED, before it.
		local db = MnemosyneDB
		settings = db.settings
		-- The server time, with GetTime's fractions: the 2 seconds between asks
		-- need more than whole seconds.
		local offset = GetServerTime() - GetTime()
		strangers = ns.Strangers.new(db.asked, function()
			return GetTime() + offset
		end, ns.memory)
		frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	end
end)
frame:RegisterEvent("PLAYER_LOGIN")
