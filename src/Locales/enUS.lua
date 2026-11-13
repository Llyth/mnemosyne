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
	-- The sender's name in a chat line, then the nickname: "Hugh Jass (Tony)".
	CHAT_NAME = "%s (%s)",
	-- |4singular:plural; picks the word for the number before it.
	HEARD_NOW = "Last heard just now",
	HEARD_MINUTES = "Last heard %d |4minute:minutes; ago",
	HEARD_HOURS = "Last heard %d |4hour:hours; ago",
	HEARD_DAYS = "Last heard %d |4day:days; ago",
	-- The registration prompt.
	PROMPT = "Who plays %s?\n\nYour nickname will be shared with every Mnemosyne user, through other players too.",
	PROMPT_FROM_PEERS = "Who plays %s?\n\nOther Mnemosyne users say it is played by %s. Register to confirm it.\n\n"
		.. "Your nickname will be shared with every Mnemosyne user, through other players too.",
	PROMPT_NICKNAME = "Your nickname",
	PROMPT_REGISTER = "Register",
	PROMPT_ANONYMOUS = "Keep anonymous",
	PROMPT_LATER = "Ask me later",
	KEPT_ANONYMOUS = "This character is anonymous. Mnemosyne users will not link it to a nickname.",
	ASK_LATER = "Mnemosyne will ask again at your next login on this character.",
	-- The other commands.
	HELP_LOOKUP = "/mnemosyne lookup <text>: find characters by name or by nickname",
	HELP_STATUS = "/mnemosyne status: what your memory holds",
	HELP_DEBUG = "/mnemosyne debug: log every message sent and received in the chat frame, or stop",
	HELP_HELP = "/mnemosyne help: this list",
	LOOKUP_EMPTY = "Type a name or a nickname after the command: /mnemosyne lookup <text>",
	LOOKUP_NONE = 'No character known for "%s".',
	LOOKUP_FOUND = "%s: played by %s",
	LOOKUP_MORE = "...and %d more. Type more of the name to narrow the search.",
	STATUS_IDENTITIES = "Identities known: %d",
	STATUS_CHARACTERS = "Your characters: %d registered, %d anonymous",
	STATUS_REGISTERED = "This character: registered as %s",
	STATUS_ANONYMOUS = "This character: anonymous",
	STATUS_NOT_ASKED = "This character: not registered",
	STATUS_CANNOT_SEND = "This account cannot send addon messages here (a trial account): Mnemosyne only listens.",
	DEBUG_ON = "Debug log on: every message sent and received shows here. /mnemosyne debug stops it.",
	DEBUG_OFF = "Debug log off.",
	DEBUG_SENT = "sent on %s: %s",
	DEBUG_NOT_SENT = "not sent on %s (%s): %s",
	DEBUG_RECEIVED = "received from %s on %s: %s",
	DEBUG_DROPPED = "dropped from %s (%s): %s",
	-- The debug report.
	HELP_REPORT = "/mnemosyne report: a debug report to paste in a bug report",
	REPORT_TITLE = "Mnemosyne debug report",
	REPORT_LINK = "Copy this link (Ctrl+C) and open it in your browser: it opens a bug report already filled in.",
	REPORT_TEXT = "If the link does not open, copy the whole report (Ctrl+C) and paste it in the bug report:",
	REPORT_OFFER = "Mnemosyne hit an error. Would you report it? The report hides other players' names.",
	REPORT_SHOW = "Show the report",
	REPORT_NOT_NOW = "Not now",
	REPORT_NEVER = "Don't ask again",
	-- Second-hand identities and syncs.
	SECOND_HAND = "~%s", -- a nickname heard second-hand: "~Tony"
	HEARD_FROM = "Heard from %s",
	LOOKUP_FOUND_SECOND_HAND = "%s: played by %s, heard from %s", -- the nickname marked as SECOND_HAND
	HELP_SYNC = "/mnemosyne sync: bring your memory up to date with the peers you can reach now",
	SYNC_STARTED = "Syncing with %d |4peer:peers;.",
	SYNC_NONE = "No peer to sync with now: none heard this session, or all synced in the last 6 hours.",
	NEWER_VERSION = "A newer Mnemosyne exists: update it, or some messages from other players stay ignored.",
}
