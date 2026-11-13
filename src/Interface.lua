-- Interface: the adapter that faces the player (decision 0004): the slash
-- commands and the tooltip line. Every string it shows comes from the locale
-- table (src/Locales/).
local _, ns = ...

local L = ns.L
local Client = ns.Client

local function say(text)
	print("|cff9d8df1Mnemosyne|r: " .. text)
end

local NICKNAME_PROBLEM = {
	empty = L.NICKNAME_EMPTY,
	long = L.NICKNAME_LONG,
	escape = L.NICKNAME_ESCAPE,
	control = L.NICKNAME_CONTROL,
	encoding = L.NICKNAME_ENCODING,
}

local commands = {}

function commands.register(nickname)
	local ok, reason = ns.characters:register(Client.playerName(), nickname)
	if not ok then
		say(NICKNAME_PROBLEM[reason])
		return
	end
	say(L.REGISTERED:format(nickname))
	Client.announce(true)
end

function commands.unregister()
	if not ns.characters:unregister(Client.playerName()) then
		say(L.NOT_REGISTERED)
		return
	end
	say(L.UNREGISTERED)
	Client.announce(false)
end

function commands.help()
	say(L.HELP)
	say(L.HELP_REGISTER)
	say(L.HELP_UNREGISTER)
end

SLASH_MNEMOSYNE1 = "/mnemosyne"
SlashCmdList.MNEMOSYNE = function(input)
	local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	local run = commands[command:lower()]
	if not run or not Client.playerName() then
		run = commands.help
	end
	run(rest)
end

-- The nickname of a known character on its tooltip; nothing for an unknown
-- one, or when the game hides the unit or its name (a secret value). A
-- tooltip that shows only a first name finds the full name through the GUID.
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
	if not ns.recognition or not tooltip.GetUnit then
		return
	end
	local isKnown = Client.isKnown
	local _, unit = tooltip:GetUnit()
	if not isKnown(unit) then
		return
	end
	local isPlayer = UnitIsPlayer(unit)
	if not isKnown(isPlayer) or not isPlayer then
		return
	end
	local name = GetUnitName(unit)
	if not isKnown(name) then
		return
	end
	local guid = UnitGUID(unit)
	local identity = ns.recognition:recall(name, isKnown(guid) and guid or nil)
	if identity then
		tooltip:AddLine(L.TOOLTIP_PLAYED_BY:format(identity.nickname), 0.62, 0.55, 0.95)
	end
end)
