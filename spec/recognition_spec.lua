local ns = require("spec.helpers.addon")("Memory", "Locales/enUS", "Recognition")
local Memory, Recognition = ns.Memory, ns.Recognition

describe("Recognition", function()
	local GUID = "Player-1-00000001"
	local now, memory, settings, recognition

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		memory = Memory.new({}, clock)
		settings = { chat = true }
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

		it("learns nothing from a line without a GUID or a name", function()
			recognition:learn("", "Hugh Jass")
			recognition:learn(GUID, "")
			assert.is_nil(recognition:recall("Hugh", ""))
			assert.is_nil(recognition:recall("Hugh", GUID))
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
		end)

		it("shows nothing when chat recognition is off", function()
			settings.chat = false
			assert.is_nil(recognition:chatTooltip("player:Hugh Jass:42:SAY:"))
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
end)
