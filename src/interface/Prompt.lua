-- Prompt: the registration prompt, a native Blizzard dialog asking who plays
-- the character, with Register, Keep anonymous and Ask me later. Part of the
-- Interface adapter (decision 0004): Self decides whether to prompt and what
-- to pre-fill; this file decides when it may open. It never opens in combat,
-- during a loading screen or in an instance, waits a few seconds after the
-- character enters the world, never shows when this account cannot send addon
-- messages (a trial account), and opens at most once per session.
local _, ns = ...

local L = ns.L
local Client = ns.Client
local Protocol = ns.Protocol

local DIALOG = "MNEMOSYNE_REGISTER"
local DELAY = 5 -- seconds after entering the world, or after combat, before the prompt opens

local asked = false -- the prompt opened this session, or has nothing to ask
local loading = false
local waiting = false -- a try is scheduled

StaticPopupDialogs[DIALOG] = {
	text = L.PROMPT,
	button1 = L.PROMPT_REGISTER,
	button2 = L.PROMPT_ANONYMOUS,
	button3 = L.PROMPT_LATER,
	hasEditBox = 1,
	maxLetters = Protocol.MAX_NICKNAME_CHARACTERS,
	editBoxInstructions = L.PROMPT_NICKNAME,
	selectCallbackByIndex = true,
	timeout = 0,
	hideOnEscape = 1,
	OnShow = function(dialog, offer)
		dialog:GetEditBox():SetText(offer.nickname or "")
		dialog:GetButton1():SetEnabled(offer.nickname ~= nil)
	end,
	EditBoxOnTextChanged = StaticPopup_StandardNonEmptyTextHandler,
	EditBoxOnEnterPressed = function(editBox)
		local register = editBox:GetParent():GetButton1()
		if register:IsEnabled() then
			register:Click()
		end
	end,
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
	-- Register: keeps the dialog open when the nickname breaks the rules (the
	-- command says why in the chat frame).
	OnButton1 = function(dialog)
		return not ns.commands.register(dialog:GetEditBox():GetText(), true)
	end,
	OnButton2 = function()
		ns.Interface.keepAnonymous()
	end,
	-- Ask me later, like Escape: nothing changes, so the next login asks again.
	OnButton3 = function()
		ns.say(L.ASK_LATER)
	end,
}

local function try()
	waiting = false
	local name = Client.playerName()
	if asked or not name or loading or InCombatLockdown() or IsInInstance() then
		return -- leaving combat, a loading screen or an instance tries again
	end
	local offer = ns.characters:prompt(name, ns.memory:recall(name))
	if not offer then
		asked = true
		return
	end
	local dialogInfo = StaticPopupDialogs[DIALOG]
	dialogInfo.text = offer.fromPeers and L.PROMPT_FROM_PEERS or L.PROMPT
	if StaticPopup_Show(DIALOG, name, offer.nickname, offer) then
		asked = true
	end
end

local function tryLater()
	if not asked and not waiting and Client.canSend() then
		waiting = true
		C_Timer.After(DELAY, try)
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
	if event == "LOADING_SCREEN_ENABLED" then
		loading = true
		return
	elseif event == "LOADING_SCREEN_DISABLED" then
		loading = false
	end
	tryLater()
end)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LOADING_SCREEN_ENABLED")
frame:RegisterEvent("LOADING_SCREEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
