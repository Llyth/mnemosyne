-- enUS, the base locale: every player-facing string, written here first and
-- never inline in code. A translation is a later file that overrides the
-- strings it translates when GetLocale() matches; any string it lacks stays
-- enUS. '||' prints as one '|' (the client's escape character).
local _, ns = ...

ns.L = {
	REGISTERED = "This character is now registered as %s.",
	UNREGISTERED = "This character is no longer registered. Mnemosyne users will forget its nickname.",
	NOT_REGISTERED = "This character is not registered.",
	NICKNAME_EMPTY = "Type the nickname after the command: /mnemosyne register <nickname>",
	NICKNAME_LONG = "A nickname has at most 32 characters.",
	NICKNAME_ESCAPE = "A nickname cannot contain ||.",
	NICKNAME_CONTROL = "A nickname cannot contain control characters.",
	NICKNAME_ENCODING = "This nickname has characters Mnemosyne cannot read.",
	HELP = "Commands:",
	HELP_REGISTER = "/mnemosyne register <nickname>: register the character you are playing",
	HELP_UNREGISTER = "/mnemosyne unregister: withdraw its registration; Mnemosyne users forget it",
	TOOLTIP_PLAYED_BY = "Played by %s",
}
