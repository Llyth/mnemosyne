-- The locale tables: enUS is the base, frFR translates it
-- (docs/agents/wow-api.md). Each file runs as the client runs it, with the
-- addon name and the shared namespace as its `...`, under a given GetLocale().
local function loadLocales(locale, L, ...)
	local ns = { L = L }
	local client = setmetatable({
		GetLocale = function()
			return locale
		end,
	}, { __index = _G })
	for _, file in ipairs({ ... }) do
		local chunk = assert(loadfile("src/Locales/" .. file .. ".lua"))
		setfenv(chunk, client)("Mnemosyne", ns)
	end
	return ns.L
end

-- What string.format and the client read in a string, in order: format
-- specifiers, |4singular:plural; forms (the count of forms, not the words),
-- the '||' escape and line breaks. The same list means string.format takes
-- the same arguments.
local function specifiers(text)
	local found = {}
	local i = 1
	while i <= #text do
		local format = text:match("^%%[%-%+ #0]*%d*%.?%d*[%a%%]", i)
		local plural = text:match("^|4[^;]*;", i)
		if format then
			found[#found + 1] = format
			i = i + #format
		elseif plural then
			found[#found + 1] = "|4" .. select(2, plural:gsub(":", ""))
			i = i + #plural
		elseif text:sub(i, i + 1) == "||" then
			found[#found + 1] = "||"
			i = i + 2
		else
			if text:sub(i, i) == "\n" then
				found[#found + 1] = "\\n"
			end
			i = i + 1
		end
	end
	return table.concat(found, " ")
end

describe("the locales", function()
	local enUS = loadLocales("enUS", nil, "enUS")
	-- Only the frFR file, over an empty table: the strings it translates.
	local frFR = loadLocales("frFR", {}, "frFR")

	it("translates every enUS string to French", function()
		for key in pairs(enUS) do
			assert.is_not_nil(frFR[key], key .. " has no frFR translation")
		end
	end)

	it("translates only strings enUS has", function()
		for key in pairs(frFR) do
			assert.is_not_nil(enUS[key], key .. " is in frFR but not in enUS")
		end
	end)

	it("keeps every format specifier and plural form of enUS, in order", function()
		for key, text in pairs(frFR) do
			assert.equal(specifiers(enUS[key] or ""), specifiers(text), key)
		end
	end)

	it("replaces the enUS strings it translates in a French client", function()
		local L = loadLocales("frFR", nil, "enUS", "frFR")
		for key, text in pairs(frFR) do
			assert.equal(text, L[key], key)
		end
	end)

	it("falls back to enUS for a string frFR lacks", function()
		local L = loadLocales("frFR", { NOT_TRANSLATED = "Only in English" }, "frFR")
		assert.equal("Only in English", L.NOT_TRANSLATED)
	end)

	it("leaves enUS untouched in another locale", function()
		local L = loadLocales("deDE", nil, "enUS", "frFR")
		for key, text in pairs(enUS) do
			assert.equal(text, L[key], key)
		end
	end)
end)
