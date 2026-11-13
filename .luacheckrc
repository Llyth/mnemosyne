-- Lua 5.1, the language of the WoW client. List each WoW global the addon
-- uses: an unknown global is then a typo or an API missing on Forever
-- (docs/agents/wow-api.md), not a silent nil.
std = "lua51"
max_line_length = 120
exclude_files = { ".lua/", ".release/", ".venv/", ".claude/" }

-- Written by the addon: its saved variables and slash command globals.
globals = {
	"MnemosyneDB",
	"SLASH_MNEMOSYNE1",
	"SlashCmdList",
}

-- Read from the client. Add each one with the code that first uses it.
read_globals = {
	"C_ChatInfo",
	"C_Timer",
	"ChatFrameUtil",
	"CreateFrame",
	"Enum",
	"EventRegistry",
	"GameTooltip",
	"GetNumGroupMembers",
	"GetNumSubgroupMembers",
	"GetServerTime",
	"GetTime",
	"GetUnitName",
	"InCombatLockdown",
	"IsInGroup",
	"IsInGuild",
	"IsInInstance",
	"IsInRaid",
	"IsTrialAccount",
	"IsVeteranTrialAccount",
	"LE_PARTY_CATEGORY_HOME",
	"LE_PARTY_CATEGORY_INSTANCE",
	"NameUtil",
	"TooltipDataProcessor",
	"UnitGUID",
	"UnitIsPlayer",
	"UnitNameUnmodified",
	"issecretvalue",
}

files["spec/"] = { std = "+busted" }
