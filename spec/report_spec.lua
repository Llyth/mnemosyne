local ns = require("spec.helpers.addon")("Report")
local Report = ns.Report

-- The report text a link carries, decoded back.
local function reportIn(link)
	local encoded = assert(link:match("[?&]report=([^&]*)"))
	return (encoded:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

describe("Report", function()
	local facts

	before_each(function()
		facts = {
			version = "v0.2.0",
			build = "70938",
			interface = 16001,
			locale = "frFR",
			now = 5000,
			settings = { chat = true, debug = false },
			counts = { identities = 12, registered = 1, anonymous = 0 },
		}
	end)

	describe("keep", function()
		it("keeps the last entries up to the limit, oldest dropped first", function()
			local events = {}
			for i = 1, 205 do
				Report.keep(events, { at = i }, 200)
			end
			assert.equal(200, #events)
			assert.equal(6, events[1].at)
			assert.equal(205, events[200].at)
		end)
	end)

	describe("text", function()
		it("holds the version, the client build, the locale, the settings and the counts", function()
			local text = Report.text(facts, {}, {}, "salt")
			assert.truthy(text:find("v0.2.0", 1, true))
			assert.truthy(text:find("70938", 1, true))
			assert.truthy(text:find("16001", 1, true))
			assert.truthy(text:find("frFR", 1, true))
			assert.truthy(text:find("chat=true", 1, true))
			assert.truthy(text:find("identities=12", 1, true))
		end)

		it("lists the caught errors and the events, newest first", function()
			local errors = {
				{ at = 4000, message = "Client.lua:12: older error" },
				{ at = 4500, message = "Chat.lua:3: newer error" },
			}
			local events = {
				{ at = 4900, what = "sent", detail = "GUILD ask Success" },
				{ at = 4990, what = "dropped", peer = "Hugh Jass", detail = "malformed" },
			}
			local text = Report.text(facts, events, errors, "salt")
			assert.truthy(text:find("newer error", 1, true) < text:find("older error", 1, true))
			assert.truthy(text:find("malformed", 1, true) < text:find("GUILD ask Success", 1, true))
		end)

		it("shows no other player's name or nickname", function()
			local events = {
				{ at = 4900, what = "received", peer = "Hugh Jass", detail = "GUILD announcement" },
				{ at = 4950, what = "sent", peer = "Anna Conda", detail = "WHISPER answer Success" },
				{ at = 4990, what = "dropped", peer = "Barb Dwyer", detail = "older" },
			}
			local text = Report.text(facts, events, {}, "salt")
			for _, name in ipairs({ "Hugh", "Jass", "Anna", "Conda", "Barb", "Dwyer", "Tony" }) do
				assert.falsy(text:find(name, 1, true), name .. " appears in the report")
			end
		end)

		it("shows a character's name as the same short hash in every event", function()
			local events = {
				{ at = 4900, what = "received", peer = "Hugh Jass", detail = "GUILD ask" },
				{ at = 4950, what = "sent", peer = "Hugh Jass", detail = "WHISPER answer Success" },
			}
			local hash = Report.hash("Hugh Jass", "salt")
			assert.equal(6, #hash)
			local text = Report.text(facts, events, {}, "salt")
			local _, count = text:gsub(hash, "")
			assert.equal(2, count)
		end)
	end)

	describe("hash", function()
		it("gives other names other hashes", function()
			assert.are_not.equal(Report.hash("Hugh Jass", "salt"), Report.hash("Anna Conda", "salt"))
		end)

		it("gives the same name another hash under another salt", function()
			assert.are_not.equal(Report.hash("Hugh Jass", "salt"), Report.hash("Hugh Jass", "pepper"))
		end)
	end)

	describe("link", function()
		it("opens the bug report form pre-filled with the report and the version", function()
			local text = Report.text(facts, {}, {}, "salt")
			local link = Report.link(text, "v0.2.0")
			assert.truthy(link:find("^https://github%.com/Llyth/mnemosyne/issues/new%?template=bug_report%.yml&"))
			assert.truthy(link:find("&version=v0.2.0&", 1, true))
			assert.equal(text, reportIn(link))
		end)

		it("stays under the size limit with 200 events, keeping the newest", function()
			local events = {}
			for i = 1, 200 do
				events[i] = {
					at = 4000 + i,
					what = "received",
					peer = "Hugh Jass",
					detail = ("GUILD announcement %03d"):format(i),
				}
			end
			local text = Report.text(facts, events, {}, "salt")
			local link = Report.link(text, "v0.2.0")
			assert.truthy(#link <= Report.MAX_LINK_BYTES)
			local carried = reportIn(link)
			assert.truthy(carried:find("announcement 200", 1, true))
			assert.falsy(carried:find("announcement 001", 1, true))
		end)

		it("encodes what a URL cannot carry as is", function()
			local link = Report.link("a&b=c #d\n", "v0.2.0")
			assert.equal("a&b=c #d\n", reportIn(link))
			assert.falsy(link:find(" ", 1, true))
		end)
	end)

	describe("isOwnError", function()
		it("recognizes an error in Mnemosyne's files", function()
			assert.is_true(Report.isOwnError("Interface/AddOns/Mnemosyne/src/Client.lua:12: oops", "Mnemosyne"))
			assert.is_true(
				Report.isOwnError([[Interface\AddOns\Mnemosyne-main\src\Chat.lua:3: oops]], "Mnemosyne-main")
			)
		end)

		it("leaves another addon's error alone", function()
			assert.is_false(Report.isOwnError("Interface/AddOns/MnemosyneExtra/x.lua:1: oops", "Mnemosyne"))
			assert.is_false(Report.isOwnError("Interface/AddOns/Other/x.lua:1: oops", "Mnemosyne"))
		end)
	end)
end)
