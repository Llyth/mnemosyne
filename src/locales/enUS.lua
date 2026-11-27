-- enUS, the base locale: every player-facing string, written here first and
-- never inline in code. A translation is a later file that overrides the
-- strings it translates when GetLocale() matches; any string it lacks stays
-- enUS. '||' prints as one '|' (the client's escape character).
local _, ns = ...

ns.L = {
	REGISTERED = "This character is now registered as %s.",
	UNREGISTERED = "This character is no longer registered. Players who have Mnemosyne will forget its nickname.",
	NOT_REGISTERED = "This character is not registered.",
	NICKNAME_EMPTY = "Type the nickname after the command: /mnemosyne register <nickname>",
	NICKNAME_LONG = "A nickname has at most 32 characters.",
	NICKNAME_ESCAPE = "A nickname cannot contain ||.",
	NICKNAME_CONTROL = "A nickname cannot contain control characters.",
	NICKNAME_ENCODING = "This nickname has characters Mnemosyne cannot read.",
	HELP = "Commands:",
	HELP_REGISTER = "/mnemosyne register <nickname>: register the character you are playing",
	HELP_UNREGISTER = "/mnemosyne unregister: withdraw its registration; players who have Mnemosyne forget it",
	TOOLTIP_PLAYED_BY = "Played by %s",
	-- The sender's name in a chat line, then the nickname: "Hugh Jass (Tony)".
	CHAT_NAME = "%s (%s)",
	HEARD = "Last heard %s", -- an AGO_ string: "Last heard 5 minutes ago"
	-- |4singular:plural; picks the word for the number before it.
	AGO_NOW = "just now",
	AGO_MINUTES = "%d |4minute:minutes; ago",
	AGO_HOURS = "%d |4hour:hours; ago",
	AGO_DAYS = "%d |4day:days; ago",
	-- The registration prompt.
	PROMPT = "Who plays %s?\n\n"
		.. "Your nickname will be shared with every player who has Mnemosyne, through other players too.",
	PROMPT_FROM_PEERS = "Who plays %s?\n\n"
		.. "Other players who have Mnemosyne say it is played by %s. Register to confirm it.\n\n"
		.. "Your nickname will be shared with every player who has Mnemosyne, through other players too.",
	PROMPT_NICKNAME = "Your nickname",
	PROMPT_REGISTER = "Register",
	PROMPT_ANONYMOUS = "Keep anonymous",
	PROMPT_LATER = "Ask me later",
	KEPT_ANONYMOUS = "This character is anonymous. Players who have Mnemosyne will not link it to a nickname.",
	ASK_LATER = "Mnemosyne will ask again at your next login on this character.",
	-- Once per character, in the prompt or the chat frame: the game's names of
	-- the professions whose window was never opened, joined with ", ".
	OPEN_PROFESSIONS = "Open each profession's window once so Mnemosyne can share its recipes: %s.",
	-- The other commands.
	HELP_LOOKUP = "/mnemosyne lookup <text>: find characters by name or by nickname",
	HELP_STATUS = "/mnemosyne status: what this character's memory holds",
	HELP_DEBUG = "/mnemosyne debug: log every message sent and received in the chat frame, or stop; "
		.. "/mnemosyne debug copy: the log in a window to copy",
	HELP_HELP = "/mnemosyne help: this list",
	LOOKUP_EMPTY = "Type a name or a nickname after the command: /mnemosyne lookup <text>",
	LOOKUP_NONE = 'No character known for "%s".',
	LOOKUP_FOUND = "%s: played by %s",
	LOOKUP_MORE = "...and %d more. Type more of the name to narrow the search.",
	STATUS_IDENTITIES = "Identities this character knows: %d",
	STATUS_CHARACTERS = "Your characters: %d registered, %d anonymous",
	STATUS_REGISTERED = "This character: registered as %s",
	STATUS_ANONYMOUS = "This character: anonymous",
	STATUS_NOT_ASKED = "This character: not registered yet",
	STATUS_UNREGISTERED = "This character: unregistered",
	STATUS_CANNOT_SEND = "This account cannot send addon messages here (a trial account): Mnemosyne only listens.",
	DEBUG_ON = "Debug log on: every message sent and received shows here. /mnemosyne debug stops it.",
	DEBUG_OFF = "Debug log off.",
	HELP_ECHO = "/mnemosyne echo: a test peer that sends back what you send, to test alone, or stop",
	ECHO_ON = "Echo peer on: Echo Mnemosyne sends back what you whisper to it or broadcast. /mnemosyne echo stops it.",
	ECHO_OFF = "Echo peer off: Echo Mnemosyne is forgotten.",
	DEBUG_LOG_TITLE = "Mnemosyne debug log",
	DEBUG_LOG_TEXT = "The log of this session, other players' names included: copy it (Ctrl+C) to share it.",
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
	HELP_SYNC = "/mnemosyne sync: bring this character's memory up to date with the peers you can reach now",
	SYNC_STARTED = "Syncing with %d |4peer:peers;.",
	SYNC_NONE = "No peer to sync with now: none heard this session, or all synced recently (in the last hour "
		.. "for guildmates, the last 6 hours for anyone else).",
	HELP_SYNC_RESET = "/mnemosyne sync reset: forget when you last synced with each player, to sync again at once "
		.. "(they must reset too)",
	SYNC_RESET = "Sync cooldowns cleared on your side. The other player must also type /mnemosyne sync reset "
		.. "before you can sync again.",
	-- Forgetting.
	HELP_FORGET = "/mnemosyne forget <character>: on this character only, drop a character's nickname "
		.. "and refuse what others pass on about it",
	HELP_UNFORGET = "/mnemosyne unforget <character>: undo forget",
	FORGOTTEN = "%s is forgotten on this character. Only what it says itself counts now, "
		.. "until /mnemosyne unforget %s.",
	ALREADY_FORGOTTEN = "%s is already forgotten.",
	UNFORGOTTEN = "%s is no longer forgotten.",
	NOT_FORGOTTEN = "%s is not forgotten.",
	FORGOTTEN_LIST = "Forgotten on this character: %s",
	FORGET_FULL_NAME = "Type the character's full name, first and last: /mnemosyne forget <character>",
	FORGOTTEN_NONE = "No character is forgotten. Type a character's full name: /mnemosyne forget <character>",
	NEWER_VERSION = "A newer Mnemosyne exists: update it, or some messages from other players stay ignored.",
	-- The settings panel (Options, AddOns, Mnemosyne).
	HELP_PANEL = "/mnemosyne: open Mnemosyne's window",
	HELP_SETTINGS = "/mnemosyne settings: open the settings panel",
	PANEL_CHARACTER = "This character",
	PANEL_NICKNAME = "Nickname",
	PANEL_REGISTER = "Register",
	PANEL_CHANGE = "Change",
	PANEL_UNREGISTER = "Unregister",
	PANEL_CANNOT_REGISTER = "This account cannot send addon messages here (a trial account), so it cannot register a "
		.. "character: Mnemosyne only listens.",
	PANEL_SWITCHES = "Options",
	PANEL_TOOLTIP = "Show on tooltips",
	PANEL_TOOLTIP_HELP = "Show who plays a character on its tooltip.",
	PANEL_CHAT = "Show in chat",
	PANEL_CHAT_HELP = "Show who plays a character after its name in chat, and on its name's tooltip.",
	PANEL_SECOND_HAND = "Show second-hand",
	PANEL_SECOND_HAND_HELP = "Show what other players passed on, in grey and marked with ~. "
		.. "Off, you see only what characters said about themselves.",
	PANEL_PASS_ON = "Pass on what I know",
	PANEL_PASS_ON_HELP = "Pass on every nickname you know when you sync with another player, and post to your "
		.. "guild the new ones a sync brings. "
		.. "Off, you share only your own registrations.",
	PANEL_SHARE_PROFESSIONS = "Share my professions",
	PANEL_SHARE_PROFESSIONS_HELP = "Share your registered characters' professions (skill levels and learned recipes) "
		.. "with the players who have Mnemosyne in your guild and among your friends. Off, they forget them.",
	PANEL_SHARE_PROGRESS = "Share my progress",
	PANEL_SHARE_PROGRESS_HELP = "Share your registered characters' progress (attunements, entrance keys and summoning "
		.. "items) with the players who have Mnemosyne in your guild and among your friends. Off, they forget it.",
	PANEL_EVERYONE = "Talk with everyone",
	PANEL_EVERYONE_HELP = "Off, Mnemosyne talks only with your friends (your friend list and your Battle.net "
		.. "friends) and your guild. On, also with your groups and with anyone you hover or target.",
	PANEL_ASK_STRANGERS = "Ask strangers",
	PANEL_ASK_STRANGERS_HELP = "Whisper an ask, invisible in chat, to a character you hover or target and do not "
		.. "know, at most once a day per character.",
	PANEL_OFFER_REPORT = "Offer a report after an error",
	PANEL_OFFER_REPORT_HELP = "When Mnemosyne hits one of its own errors, offer the debug report once a session.",
	PANEL_STATUS = "Status",
	PANEL_REPORT = "Report a bug",
	PANEL_IDENTITIES = "Identities",
	PANEL_SEARCH = "Search names and nicknames",
	PANEL_COLUMN_CHARACTER = "Character",
	PANEL_COLUMN_NICKNAME = "Nickname",
	PANEL_COLUMN_HEARD = "Heard",
	PANEL_COLUMN_AGO = "Last heard",
	PANEL_COLUMN_VERSION = "Version",
	PANEL_FORGET = "Forget",
	PANEL_UNDO = "Undo",
	PANEL_NONE = "No identity found.",
	PANEL_FIRST_HAND = "first-hand",
	PANEL_FIRST_HAND_FORGOTTEN = "first-hand, forgotten", -- heard from the character after you forgot it
	PANEL_FROM = "from %s", -- a second-hand identity's source
	PANEL_DISPUTED = "disputed",
	PANEL_FORGOTTEN = "forgotten",
	PANEL_YOURS = "yours", -- one of your own characters
	PANEL_ANONYMOUS = "anonymous", -- one of your own characters, kept anonymous
	STATUS_PEERS = "Peers heard this session: %d",
	STATUS_SYNCS = "This character synced in the last 6 hours with: %s",
	STATUS_SYNC = "%s (%s)", -- a peer and how long ago: "Anna Conda (5 minutes ago)"
	STATUS_NO_SYNC = "No sync on this character in the last 6 hours.",
	-- Mnemosyne's window, opened from the Escape menu and by /mnemosyne alone.
	WINDOW_WHISPER = "Whisper",
	-- A peer and how long ago: "This character's last sync: Anna Conda, 5 minutes ago."
	WINDOW_LAST_SYNC = "This character's last sync: %s, %s.",
	WINDOW_WAITING = "Waiting to sync: %d",
	-- The window's Professions tab: profession and recipe names come from the game.
	PROFESSIONS = "Professions",
	PROFESSIONS_PRIMARY = "Primary Professions",
	PROFESSIONS_SECONDARY = "Secondary Professions",
	PROFESSIONS_RECIPES = "Recipes",
	PROFESSIONS_CHARACTERS = "Characters",
	PROFESSIONS_KNOWN_BY = "Who knows %s",
	PROFESSIONS_RECIPE_COUNT = "%d |4recipe:recipes;",
	PROFESSIONS_CHARACTER_COUNT = "%d |4character:characters;",
	PROFESSIONS_SEARCH = "Search recipes, names and nicknames",
	PROFESSIONS_NO_RECIPE = "No recipe found.",
	PROFESSIONS_BACK = "Back",
	HELP_PROFESSIONS = "/mnemosyne professions: open the Professions tab",
}
