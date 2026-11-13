-- Chat recognition, part of the Interface adapter (decision 0004): a known
-- character's nickname after its name in chat lines, a tooltip on its name,
-- and the session's GUID map learned from chat lines and group members.
-- Recognition decides what to show; this file only wires it to the hooks
-- other addons respect (the sender name filter and the chat frames' hyperlink
-- callbacks) and redraws nothing; the Communities window, which offers no
-- hook, gets its stored lines rewritten the way it rewrites an edited message
-- (below). A secret value (chat lockdown) counts as unknown: the line shows
-- the plain name.
local _, ns = ...

local isKnown = ns.Client.isKnown
local Interface = ns.Interface

-- The chat lines that show a nickname: say, yell, whispers, group, guild,
-- instance, custom channels and Communities channels. Every other line (emotes,
-- system messages, Battle.net) keeps its name as it is.
local SHOWN = {
	CHAT_MSG_SAY = true,
	CHAT_MSG_YELL = true,
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_WHISPER_INFORM = true,
	CHAT_MSG_PARTY = true,
	CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true,
	CHAT_MSG_RAID_LEADER = true,
	CHAT_MSG_RAID_WARNING = true,
	CHAT_MSG_GUILD = true,
	CHAT_MSG_OFFICER = true,
	CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true,
	CHAT_MSG_CHANNEL = true,
	CHAT_MSG_COMMUNITIES_CHANNEL = true,
}

-- Called by the chat frame for every line it shows, only when the name it
-- passes is readable; returns the new name, or nil to leave it as it is.
ChatFrameUtil.AddSenderNameFilter(function(event, decorated, _, sender, ...)
	if not ns.recognition or not SHOWN[event] or not isKnown(sender) then
		return nil
	end
	local guid = select(10, ...)
	return ns.recognition:chatName(decorated, sender, isKnown(guid) and guid ~= "" and guid or nil)
end)

-- Raid units count the player (raid1 to raidN); party units do not (party1
-- to party4).
local function learnGroup()
	local prefix, count = "party", GetNumSubgroupMembers()
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	for i = 1, count do
		local unit = prefix .. i
		local guid = UnitGUID(unit)
		local name, surname = UnitNameUnmodified(unit)
		if isKnown(guid) and isKnown(name) and isKnown(surname) and surname ~= "" then
			ns.recognition:learn(guid, NameUtil.GetFullNameWithoutRealm(name, surname))
		end
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	if not ns.recognition then
		return
	end
	if event == "GROUP_ROSTER_UPDATE" then
		learnGroup()
		return
	end
	local sender, guid = select(2, ...), select(12, ...)
	if isKnown(sender) and isKnown(guid) then
		ns.recognition:learn(guid, sender)
	end
end)
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
-- The chat lines whose sender and GUID surely belong to the same character
-- teach the GUID map. A whisper you send names its recipient, and a
-- Communities line can come from a Battle.net account: neither teaches it.
for event in pairs(SHOWN) do
	if event ~= "CHAT_MSG_WHISPER_INFORM" and event ~= "CHAT_MSG_COMMUNITIES_CHANNEL" then
		frame:RegisterEvent(event)
	end
end

-- The tooltip on a character's name in a chat line: who plays it, and when it
-- was last heard. When another handler already shows a tooltip for the link,
-- the lines join it; otherwise Mnemosyne shows its own, and hides it when the
-- pointer leaves the link if it is still its own.
local tooltipOwner

EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkEnter", function(_, chatFrame, link)
	if not ns.recognition or not isKnown(link) then
		return
	end
	local lines = ns.recognition:chatTooltip(link)
	if not lines then
		return
	end
	if not (GameTooltip:IsShown() and GameTooltip:IsOwned(chatFrame)) then
		GameTooltip:SetOwner(chatFrame, "ANCHOR_CURSOR")
		GameTooltip:SetText(lines.name)
		tooltipOwner = chatFrame
	end
	Interface.addPlayedBy(GameTooltip, lines.nickname)
	GameTooltip:AddLine(lines.heard, 0.6, 0.6, 0.6)
	GameTooltip:Show()
end, ns)

EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkLeave", function()
	if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
		GameTooltip:Hide()
	end
	tooltipOwner = nil
end, ns)

-- The Communities window formats its own lines and calls no name filter
-- (docs/agents/wow-api.md). After it adds or reformats a line, the line's
-- stored text is rewritten through its message frame's TransformMessages, the
-- way the window itself updates an edited message. Lines added together (a
-- page of history holds up to 100) are rewritten in one pass on the next frame.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Communities", function()
	local chat = CommunitiesFrame.Chat

	local function nicknamed(line, ...)
		if ns.recognition and isKnown(line) then
			line = ns.recognition:communitiesLine(line) or line
		end
		return line, ...
	end

	-- The message IDs of the lines added since the last pass; the 7th value of
	-- a stored line is its message ID.
	local added = {}
	local function showAdded()
		local ids = added
		added = {}
		chat.MessageFrame:TransformMessages(function(...)
			local id = select(7, ...)
			return isKnown(id) and ids[id]
		end, nicknamed)
	end

	hooksecurefunc(chat, "AddMessage", function(_, _, _, message)
		local id = message.messageId
		if not isKnown(id) then
			return
		end
		if not next(added) then
			C_Timer.After(0, showAdded)
		end
		added[id] = true
	end)
	-- A line reformatted before its pass gets its nickname here: the pass
	-- skips it, or the nickname would show twice.
	hooksecurefunc(chat, "RefreshMessages", function(_, predicate)
		chat.MessageFrame:TransformMessages(predicate, function(...)
			local id = select(7, ...)
			if isKnown(id) then
				added[id] = nil
			end
			return nicknamed(...)
		end)
	end)
end)
