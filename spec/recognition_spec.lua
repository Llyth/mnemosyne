local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Self", "locales/enUS", "Recognition")
local Memory, Self, Recognition = ns.Memory, ns.Self, ns.Recognition

describe("Recognition", function()
	local GUID = "Player-1-00000001"
	local now, memory, settings, recognition

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		memory = Memory.new({}, clock)
		settings = { chat = true, showSecondHand = true }
		recognition = Recognition.new(memory, settings, ns.L, clock)
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
	end)

	describe("in chat", function()
		it("shows a known character's nickname after its name", function()
			assert.equal("Hugh Jass (Tony)", recognition:chatName("Hugh Jass", "Hugh Jass"))
		end)

		it("keeps the color of the name it adds the nickname to", function()
			assert.equal("|cffc69b6dHugh Jass|r (Tony)", recognition:chatName("|cffc69b6dHugh Jass|r", "Hugh Jass"))
		end)

		it("leaves the name of a character it does not know as it is", function()
			assert.is_nil(recognition:chatName("Anna Conda", "Anna Conda"))
		end)

		it("leaves the name of a character that unregistered as it is", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.is_nil(recognition:chatName("Hugh Jass", "Hugh Jass"))
		end)

		it("leaves every name as it is when chat recognition is off", function()
			settings.chat = false
			assert.is_nil(recognition:chatName("Hugh Jass", "Hugh Jass"))
		end)

		it("shows a second-hand nickname in grey, marked with ~", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.equal("Anna Conda (|cff808080~Ann|r)", recognition:chatName("Anna Conda", "Anna Conda"))
		end)

		it("recognizes a sender by the full name the line's GUID was learned with", function()
			recognition:learn(GUID, "Hugh Jass")
			assert.equal("Hugh (Tony)", recognition:chatName("Hugh", "Hugh", GUID))
		end)
	end)

	describe("by GUID", function()
		it("recalls a character by its full name", function()
			assert.equal("Tony", recognition:recall("Hugh Jass", GUID).nickname)
		end)

		it("finds the full name of a character that hides its surname through the GUID of its chat lines", function()
			recognition:learn(GUID, "Hugh Jass")
			assert.equal("Tony", recognition:recall("Hugh", GUID).nickname)
		end)

		it("never takes a first name alone for a full name", function()
			assert.is_nil(recognition:recall("Hugh", GUID))
			assert.is_nil(recognition:recall("Hugh"))
		end)

		it("trusts a full name shown over the GUID map", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
			recognition:learn(GUID, "Anna Conda")
			assert.equal("Tony", recognition:recall("Hugh Jass", GUID).nickname)
		end)

		it("learns only the GUIDs of characters it knows", function()
			recognition:learn(GUID, "Anna Conda")
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
			assert.is_nil(recognition:recall("Anna", GUID))
		end)

		it("keeps each GUID's full name apart", function()
			memory:hear("Hugh Mungus", { nickname = "Bob", revision = 900 })
			recognition:learn(GUID, "Hugh Jass")
			recognition:learn("Player-1-00000002", "Hugh Mungus")
			assert.equal("Tony", recognition:recall("Hugh", GUID).nickname)
			assert.equal("Bob", recognition:recall("Hugh", "Player-1-00000002").nickname)
		end)

		it("shows each GUID it learns to the professions, so a reused name's go stale", function()
			local seen = {}
			local professions = {
				see = function(_, name, guid)
					seen[#seen + 1] = name .. " " .. guid
				end,
			}
			recognition = Recognition.new(memory, settings, ns.L, clock, nil, professions)
			recognition:learn(GUID, "Anna Conda")
			recognition:learn("", "Anna Conda")
			assert.same({ "Anna Conda " .. GUID }, seen)
		end)

		it("learns nothing from a line without a GUID or a name", function()
			recognition:learn("", "Hugh Jass")
			recognition:learn(GUID, "")
			assert.is_nil(recognition:recall("Hugh", ""))
			assert.is_nil(recognition:recall("Hugh", GUID))
		end)

		it("hides a character whose full name shows up with another GUID, in chat and on a tooltip", function()
			recognition:learn(GUID, "Hugh Jass")
			recognition:learn("Player-1-00000002", "Hugh Jass")
			assert.is_nil(recognition:recall("Hugh Jass", "Player-1-00000002"))
			assert.is_nil(recognition:chatName("Hugh Jass", "Hugh Jass", "Player-1-00000002"))
			assert.same({}, recognition:search("Tony"))
		end)

		it("forgets what it learned when the session ends", function()
			recognition:learn(GUID, "Hugh Jass")
			local nextSession = Recognition.new(memory, settings, ns.L, clock)
			assert.is_nil(nextSession:recall("Hugh", GUID))
		end)
	end)

	describe("on a name in chat", function()
		it("shows who plays the character a chat line links to, and when it was last heard", function()
			assert.same(
				{ name = "Hugh Jass", nickname = "Tony", heard = "Last heard just now" },
				recognition:chatTooltip("player:Hugh Jass:42:SAY:")
			)
			assert.equal("Hugh Jass", recognition:chatTooltip("player:Hugh Jass").name)
		end)

		it("shows who plays the character a Communities chat line links to", function()
			assert.equal("Hugh Jass", recognition:chatTooltip("playerCommunity:Hugh Jass:7:1:1700000000:3").name)
		end)

		it("shows nothing for a link that is not a character's", function()
			assert.is_nil(recognition:chatTooltip("item:19019::::::::60"))
			assert.is_nil(recognition:chatTooltip("BNplayer:Hugh Jass:12:0:WHISPER:Tony"))
			assert.is_nil(recognition:chatTooltip("player::42:SAY:"))
		end)

		it("shows nothing for a character it does not know", function()
			assert.is_nil(recognition:chatTooltip("player:Anna Conda:42:SAY:"))
			assert.is_nil(recognition:communitiesLine("[|HplayerCommunity:Anna Conda:7:1:1:2|hAnna Conda|h]: hi"))
		end)

		it("shows who passed on a second-hand identity", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.same(
				{ name = "Anna Conda", nickname = "Ann", heard = "Last heard just now", source = "Barb Dwyer" },
				recognition:chatTooltip("player:Anna Conda:42:SAY:")
			)
		end)

		it("shows nothing when chat recognition is off", function()
			settings.chat = false
			assert.is_nil(recognition:chatTooltip("player:Hugh Jass:42:SAY:"))
		end)
	end)

	describe("on a tooltip", function()
		it("shows who plays a character heard first-hand in Mnemosyne's color", function()
			assert.same({ { "Played by Tony", 0.62, 0.55, 0.95 } }, recognition:playedBy(memory:recall("Hugh Jass")))
		end)

		it("shows a second-hand nickname in grey, marked with ~, and who passed it on", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.same({
				{ "Played by ~Ann", 0.5, 0.5, 0.5 },
				{ "Heard from Barb Dwyer", 0.5, 0.5, 0.5 },
			}, recognition:playedBy(memory:recall("Anna Conda")))
		end)
	end)

	describe("names a nickname", function()
		it("as it is when heard first-hand", function()
			assert.equal("Tony", recognition:nickname(memory:recall("Hugh Jass")))
		end)

		it("marked with ~ when heard second-hand", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.equal("~Ann", recognition:nickname(memory:recall("Anna Conda")))
		end)
	end)

	describe("in a lookup", function()
		it("names who plays a character heard first-hand", function()
			assert.equal("Hugh Jass: played by Tony", recognition:lookupLine(recognition:search("Hugh")[1]))
		end)

		it("marks a second-hand nickname with ~ and says who passed it on", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.equal(
				"Anna Conda: played by ~Ann, heard from Barb Dwyer",
				recognition:lookupLine(recognition:search("Anna")[1])
			)
		end)
	end)

	describe("in the Communities window", function()
		local function line(name, shown, text)
			return ("[|HplayerCommunity:%s:7:1:1700000000:2|h%s|h]: %s"):format(name, shown, text)
		end

		it("shows a known character's nickname after its name", function()
			assert.equal(
				line("Hugh Jass", "Hugh Jass (Tony)", "hi"),
				recognition:communitiesLine(line("Hugh Jass", "Hugh Jass", "hi"))
			)
		end)

		it("keeps the color and the timestamp of the line", function()
			local colored = "12:30 " .. line("Hugh Jass", "|cffc69b6dHugh Jass|r", "hi")
			assert.equal(
				"12:30 " .. line("Hugh Jass", "|cffc69b6dHugh Jass|r (Tony)", "hi"),
				recognition:communitiesLine(colored)
			)
		end)

		it("adds the nickname to the sender only, not to a character linked in the message", function()
			local said = line("Hugh Jass", "Hugh Jass", line("Hugh Jass", "Hugh Jass", "hi"))
			assert.equal(
				line("Hugh Jass", "Hugh Jass (Tony)", line("Hugh Jass", "Hugh Jass", "hi")),
				recognition:communitiesLine(said)
			)
		end)

		it("leaves the line of a character it does not know as it is", function()
			assert.is_nil(recognition:communitiesLine(line("Anna Conda", "Anna Conda", "hi")))
		end)

		it("shows a second-hand nickname in grey, marked with ~", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			assert.equal(
				line("Anna Conda", "Anna Conda (|cff808080~Ann|r)", "hi"),
				recognition:communitiesLine(line("Anna Conda", "Anna Conda", "hi"))
			)
		end)

		it("leaves a Battle.net friend's line as it is", function()
			assert.is_nil(recognition:communitiesLine("[|HBNplayerCommunity:Hugh Jass:1:7:1:1:2|hHugh Jass|h]: hi"))
		end)

		it("leaves a Battle.net friend's line as it is when it links a character", function()
			local said = "[|HBNplayerCommunity:Anna Conda:1:7:1:1:2|hAnna Conda|h]: "
				.. line("Hugh Jass", "Hugh Jass", "hi")
			assert.is_nil(recognition:communitiesLine(said))
		end)

		it("leaves a line without a character's link as it is", function()
			assert.is_nil(recognition:communitiesLine("Message of the day: raid at nine"))
		end)

		it("leaves every line as it is when chat recognition is off", function()
			settings.chat = false
			assert.is_nil(recognition:communitiesLine(line("Hugh Jass", "Hugh Jass", "hi")))
		end)
	end)

	describe("says when an identity was last heard", function()
		local function heardAgo(seconds)
			now = 1000 + seconds
			return recognition:chatTooltip("player:Hugh Jass").heard
		end

		it("just now within the minute", function()
			assert.equal("Last heard just now", heardAgo(59))
		end)

		it("in minutes within the hour", function()
			assert.equal("Last heard 1 |4minute:minutes; ago", heardAgo(60))
			assert.equal("Last heard 59 |4minute:minutes; ago", heardAgo(3599))
		end)

		it("in hours within the day", function()
			assert.equal("Last heard 1 |4hour:hours; ago", heardAgo(3600))
			assert.equal("Last heard 23 |4hour:hours; ago", heardAgo(86399))
		end)

		it("in days past a day", function()
			assert.equal("Last heard 1 |4day:days; ago", heardAgo(86400))
			assert.equal("Last heard 40 |4day:days; ago", heardAgo(40 * 86400))
		end)

		it("just now when the server clock went back", function()
			assert.equal("Last heard just now", heardAgo(-30))
		end)
	end)

	describe("with Show second-hand off", function()
		before_each(function()
			settings.showSecondHand = false
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
		end)

		it("hides second-hand identities everywhere", function()
			assert.is_nil(recognition:recall("Anna Conda"))
			assert.is_nil(recognition:chatName("Anna Conda", "Anna Conda"))
			assert.is_nil(recognition:chatTooltip("player:Anna Conda:42:SAY:"))
		end)

		it("leaves second-hand identities out of a lookup", function()
			local found = recognition:search("")
			assert.equal(1, #found)
			assert.equal("Hugh Jass", found[1].name)
			settings.showSecondHand = true
			assert.equal(2, #recognition:search(""))
		end)

		it("leaves second-hand identities out of the count", function()
			assert.equal(1, recognition:count())
			settings.showSecondHand = true
			assert.equal(2, recognition:count())
		end)

		it("still shows first-hand identities", function()
			assert.equal("Hugh Jass (Tony)", recognition:chatName("Hugh Jass", "Hugh Jass"))
		end)
	end)

	describe("on a character's tooltip", function()
		it("shows a known character's identity", function()
			settings.tooltip = true
			assert.equal("Tony", recognition:tooltip("Hugh Jass").nickname)
		end)

		it("shows nothing when tooltip recognition is off", function()
			settings.tooltip = false
			assert.is_nil(recognition:tooltip("Hugh Jass"))
		end)
	end)

	it("says how long ago a time was", function()
		now = 1000 + 2 * 3600
		assert.equal("2 |4hour:hours; ago", recognition:ago(1000))
	end)

	describe("in the window's list", function()
		before_each(function()
			memory = Memory.new({}, clock, {})
			recognition = Recognition.new(memory, settings, ns.L, clock)
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			now = 1000 + 2 * 3600
		end)

		it("gives each identity's nickname, how it was heard and when, sorted by nickname", function()
			assert.same({
				{ name = "Anna Conda", nickname = "Ann", heard = "from Barb Dwyer", ago = "2 |4hour:hours; ago" },
				{ name = "Hugh Jass", nickname = "Tony", heard = "first-hand", ago = "2 |4hour:hours; ago" },
			}, (recognition:rows("", 50)))
		end)

		it("marks a disputed identity", function()
			memory:hear("Anna Conda", { nickname = "Mallory", revision = 900, source = "Cole Slaw" })
			assert.equal("disputed", recognition:rows("Anna", 50)[1].nickname)
		end)

		it("marks a forgotten character heard first-hand again as forgotten", function()
			memory:forget("Hugh Jass")
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 950 })
			local row = recognition:rows("Hugh", 50)[1]
			assert.same({ "Tony", "first-hand, forgotten", true }, { row.nickname, row.heard, row.forgotten })
		end)

		it("gives a forgotten character to undo", function()
			memory:forget("Hugh Jass")
			assert.same(
				{ { name = "Hugh Jass", nickname = "forgotten", heard = "", ago = "", forgotten = true } },
				(recognition:rows("Hugh", 50))
			)
		end)

		it("leaves second-hand identities out while Show second-hand is off, not forgotten characters", function()
			settings.showSecondHand = false
			memory:forget("Cole Slaw")
			local rows = recognition:rows("", 50)
			assert.same({ "Hugh Jass", "Cole Slaw" }, { rows[1].name, rows[2].name })
			assert.equal(2, #rows)
		end)

		it("gives at most the rows asked for, and how many it found", function()
			local rows, total = recognition:rows("", 1)
			assert.same({ "Anna Conda" }, { rows[1].name, rows[2] and rows[2].name })
			assert.equal(2, total)
		end)

		it("gives the player's own characters first, by nickname, registered or anonymous, once each", function()
			local characters = Self.new({}, clock)
			characters:register("Zed Zulu", "Llyth")
			characters:keepAnonymous("Yan Yak")
			characters:register("Hugh Jass", "Tony") -- also in the memory, from a peer
			recognition = Recognition.new(memory, settings, ns.L, clock, characters)
			assert.same({
				{ name = "Zed Zulu", nickname = "Llyth", heard = "yours", ago = "", own = true },
				{ name = "Hugh Jass", nickname = "Tony", heard = "yours", ago = "", own = true },
				{ name = "Yan Yak", nickname = "anonymous", heard = "yours", ago = "", own = true },
				{ name = "Anna Conda", nickname = "Ann", heard = "from Barb Dwyer", ago = "2 |4hour:hours; ago" },
			}, (recognition:rows("", 50)))
			assert.same({ "Zed Zulu" }, { recognition:rows("llyth", 50)[1].name, recognition:rows("llyth", 50)[2] })
		end)
	end)

	describe("in the window's sync status", function()
		it("says the last sync, with whom and when, and how many peers wait", function()
			now = 1000 + 5 * 60
			assert.equal(
				"Last sync: Anna Conda, 5 |4minute:minutes; ago. Waiting to sync: 2",
				recognition:syncStatus({ { peer = "Anna Conda", at = 1000 }, { peer = "Cole Slaw", at = 900 } }, 2)
			)
		end)

		it("says when no sync happened in the last 6 hours", function()
			assert.equal("No sync in the last 6 hours. Waiting to sync: 0", recognition:syncStatus({}, 0))
		end)
	end)

	describe("for the player's own characters", function()
		local characters

		before_each(function()
			characters = Self.new({}, clock)
			-- The memory tells this account's characters apart too (Self:owns).
			memory = Memory.new({}, clock, {}, characters)
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			recognition = Recognition.new(memory, settings, ns.L, clock, characters)
		end)

		it("shows a registered one's nickname in chat, as first-hand", function()
			characters:register("Zed Zulu", "Llyth")
			assert.equal("Zed Zulu (Llyth)", recognition:chatName("Zed Zulu", "Zed Zulu"))
		end)

		it("shows its own registration over what peers say", function()
			memory:hear("Hugh Jass", { nickname = "Mallory", revision = 1, source = "Cole Slaw" })
			characters:register("Hugh Jass", "Tony2")
			assert.equal("Tony2", recognition:recall("Hugh Jass").nickname)
		end)

		it("gives the tooltip on a registered one's name in chat, from when it registered", function()
			characters:register("Zed Zulu", "Llyth")
			now = now + 2 * 3600
			local tooltip = recognition:chatTooltip("player:Zed Zulu:42:SAY:")
			assert.same({ "Llyth", ns.L.HEARD:format("2 |4hour:hours; ago") }, { tooltip.nickname, tooltip.heard })
		end)

		describe("whose name another player's character took", function()
			local OTHER = "Player-1-00000002"

			before_each(function()
				characters:register("Zed Zulu", "Llyth")
				characters:see("Zed Zulu", GUID)
			end)

			it("shows the other character's first-hand nickname, not its registration", function()
				memory:hear("Zed Zulu", { nickname = "Bob", revision = 2000 })
				recognition:learn(OTHER, "Zed Zulu")
				settings.tooltip = true
				assert.equal("Zed Zulu (Bob)", recognition:chatName("Zed Zulu", "Zed Zulu"))
				assert.equal("Zed Zulu (Bob)", recognition:chatName("Zed Zulu", "Zed Zulu", OTHER))
				assert.equal("Bob", recognition:tooltip("Zed Zulu", OTHER).nickname)
			end)

			it("lists, finds and counts the other character's first-hand identity once seen with its GUID", function()
				memory:hear("Zed Zulu", { nickname = "Bob", revision = 2000 })
				recognition:learn(OTHER, "Zed Zulu")
				assert.same(
					{ "Zed Zulu", "Bob" },
					{ recognition:search("Bob")[1].name, recognition:search("Bob")[1].nickname }
				)
				assert.equal(2, recognition:count())
				local rows, total = recognition:rows("Bob", 50)
				assert.same({ "Zed Zulu", "Bob", nil }, { rows[1].name, rows[1].nickname, rows[1].own })
				assert.equal(1, total)
			end)

			it(
				"shows the other character's first-hand nickname once it speaks, whatever GUID a peer passed on for yours",
				function()
					memory:hear("Zed Zulu", { nickname = "Llyth", revision = 900, source = "Cole Slaw", guid = GUID })
					memory:hear("Zed Zulu", { nickname = "Bob", revision = 2000 })
					recognition:learn(OTHER, "Zed Zulu")
					assert.equal("Zed Zulu (Bob)", recognition:chatName("Zed Zulu", "Zed Zulu", OTHER))
					assert.equal("Bob", recognition:chatTooltip("player:Zed Zulu:1:GUILD:").nickname)
				end
			)

			it(
				"shows the other character's first-hand nickname once it speaks, after yours spoke with its GUID",
				function()
					memory:hear("Zed Zulu", { nickname = "Llyth", revision = 900, source = "Cole Slaw" })
					recognition:learn(GUID, "Zed Zulu") -- your character, in chat before its name was taken
					memory:hear("Zed Zulu", { nickname = "Bob", revision = 2000 })
					recognition:learn(OTHER, "Zed Zulu")
					assert.equal("Zed Zulu (Bob)", recognition:chatName("Zed Zulu", "Zed Zulu", OTHER))
					assert.equal("Bob", recognition:chatTooltip("player:Zed Zulu:1:GUILD:").nickname)
				end
			)

			it("shows nothing of its registration on the other character, a stranger", function()
				assert.is_nil(recognition:recall("Zed Zulu", OTHER))
			end)

			it("still shows its registration where the GUID is its own or unknown", function()
				memory:hear("Zed Zulu", { nickname = "Bob", revision = 2000 }) -- no GUID seen yet
				assert.equal("Llyth", recognition:recall("Zed Zulu").nickname)
				assert.equal("Llyth", recognition:recall("Zed Zulu", GUID).nickname)
				characters:register("Yan Yak", "Llyth") -- saved before GUIDs were: none
				assert.equal("Llyth", recognition:recall("Yan Yak", OTHER).nickname)
			end)
		end)

		it("shows nothing for one kept anonymous or unregistered", function()
			characters:keepAnonymous("Hugh Jass")
			assert.is_nil(recognition:recall("Hugh Jass"))
		end)

		describe("in the status", function()
			it("says a registered character's nickname", function()
				characters:register("Zed Zulu", "Llyth")
				assert.equal("This character: registered as Llyth", recognition:registrationLine("Zed Zulu"))
			end)

			it("says a character kept anonymous is anonymous", function()
				characters:keepAnonymous("Zed Zulu")
				assert.equal("This character: anonymous", recognition:registrationLine("Zed Zulu"))
			end)

			it("says a character that unregistered is unregistered, not that it was never asked", function()
				characters:register("Zed Zulu", "Llyth")
				characters:unregister("Zed Zulu")
				assert.equal("This character: unregistered", recognition:registrationLine("Zed Zulu"))
			end)

			it("says a character never asked is not registered yet", function()
				assert.equal("This character: not registered yet", recognition:registrationLine("Zed Zulu"))
			end)

			it("counts the identities shown, your characters and the peers heard", function()
				characters:register("Zed Zulu", "Llyth")
				characters:register("Yan Yak", "Llyth")
				characters:keepAnonymous("Xia Xu")
				memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
				settings.showSecondHand = false
				local lines = recognition:statusLines({}, 3)
				assert.same({
					"Identities known: 1",
					"Your characters: 2 registered, 1 anonymous",
					"Peers heard this session: 3",
				}, { lines[1], lines[2], lines[3] })
			end)

			it("lists each sync of the last 6 hours with how long ago it was", function()
				now = 1000 + 2 * 3600
				local lines = recognition:statusLines(
					{ { peer = "Anna Conda", at = 1000 + 3600 }, { peer = "Cole Slaw", at = 1000 } },
					0
				)
				assert.equal(
					"Synced in the last 6 hours: Anna Conda (1 |4hour:hours; ago), Cole Slaw (2 |4hour:hours; ago)",
					lines[4]
				)
			end)

			it("says when no sync happened in the last 6 hours", function()
				assert.equal("No sync in the last 6 hours.", recognition:statusLines({}, 0)[4])
			end)
		end)

		it("never shows what peers say about one as someone else's character", function()
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
			memory:hear("Cole Slaw", { nickname = "Bobby", revision = 900, source = "Barb Dwyer" })
			memory:hear("Zed Zulu", { nickname = "Zed", revision = 900, source = "Barb Dwyer" })
			characters:register("Anna Conda", "Llyth")
			characters:keepAnonymous("Cole Slaw")
			characters:register("Zed Zulu", "Zed")
			characters:unregister("Zed Zulu")
			assert.same({ "Hugh Jass" }, { recognition:search("")[1].name, recognition:search("")[2] })
			assert.equal(1, recognition:count())
			local rows, total = recognition:rows("", 50)
			assert.same({ "Anna Conda", "Cole Slaw", "Hugh Jass" }, { rows[1].name, rows[2].name, rows[3].name })
			assert.same({ true, true }, { rows[1].own, rows[2].own })
			assert.equal(3, total)
			assert.same({}, (recognition:rows("Bobby", 50)))
		end)
	end)
end)
