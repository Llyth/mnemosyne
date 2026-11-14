-- The locale tables: enUS is the base, every other language WoW Forever ships
-- translates it (docs/agents/wow-api.md). Each file runs as the client runs it, with the
-- addon name and the shared namespace as its `...`, under a given GetLocale().
local function loadLocales(locale, L, ...)
	local ns = { L = L }
	local client = setmetatable({
		GetLocale = function()
			return locale
		end,
	}, { __index = _G })
	for _, file in ipairs({ ... }) do
		local chunk = assert(loadfile("src/locales/" .. file .. ".lua"))
		setfenv(chunk, client)("Mnemosyne", ns)
	end
	return ns.L
end

-- The translations: every locale WoW Forever 1.60.1 ships but enUS (itIT has
-- no translation of its own: the client is in English).
local TRANSLATIONS = { "frFR", "deDE", "esES", "esMX", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

-- How many forms a |4...; plural has in a locale, as Blizzard writes them:
-- Russian has three; Korean and Chinese write no plural (nil: left out).
local PLURAL_FORMS = { ruRU = 3, koKR = false, zhCN = false, zhTW = false }

-- What string.format and the client read in a string, in order: format
-- specifiers, |4singular:plural; forms (the count of forms, not the words),
-- the '||' escape and line breaks. The same list means string.format takes
-- the same arguments. forms, when given, is the count of forms each plural
-- should have in the locale (false: plurals are left out).
local function specifiers(text, forms)
	local found = {}
	local i = 1
	while i <= #text do
		local format = text:match("^%%[%-%+ #0]*%d*%.?%d*[%a%%]", i)
		local plural = text:match("^|4[^;]*;", i)
		if format then
			found[#found + 1] = format
			i = i + #format
		elseif plural then
			if forms ~= false then
				found[#found + 1] = "|4" .. (forms or select(2, plural:gsub(":", "")) + 1)
			end
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

	for _, locale in ipairs(TRANSLATIONS) do
		describe(locale, function()
			-- Only this locale's file, over an empty table: the strings it translates.
			local translated = loadLocales(locale, {}, locale)

			it("translates every enUS string", function()
				for key in pairs(enUS) do
					assert.is_not_nil(translated[key], key .. " has no " .. locale .. " translation")
				end
			end)

			it("translates only strings enUS has", function()
				for key in pairs(translated) do
					assert.is_not_nil(enUS[key], key .. " is in " .. locale .. " but not in enUS")
				end
			end)

			it("keeps every format specifier of enUS, in order, and its plurals as the locale writes them", function()
				local forms = PLURAL_FORMS[locale]
				for key, text in pairs(translated) do
					assert.equal(specifiers(enUS[key] or "", forms), specifiers(text, forms and nil), key)
				end
			end)

			it("replaces the enUS strings it translates in its own client", function()
				local L = loadLocales(locale, nil, "enUS", locale)
				for key, text in pairs(translated) do
					assert.equal(text, L[key], key)
				end
			end)

			it("falls back to enUS for a string it lacks", function()
				local L = loadLocales(locale, { NOT_TRANSLATED = "Only in English" }, locale)
				assert.equal("Only in English", L.NOT_TRANSLATED)
			end)

			it("is loaded by the .toc, after enUS", function()
				local toc = assert(io.open("Mnemosyne.toc")):read("*a")
				local base = toc:find("src\\locales\\enUS.lua", 1, true)
				local at = toc:find("src\\locales\\" .. locale .. ".lua", 1, true)
				assert.is_truthy(base and at and at > base, locale .. " is not in the .toc after enUS")
			end)
		end)
	end

	it("leaves enUS untouched in a client with no translation (itIT)", function()
		local L = loadLocales("itIT", nil, "enUS", unpack(TRANSLATIONS))
		for key, text in pairs(enUS) do
			assert.equal(text, L[key], key)
		end
	end)
end)
