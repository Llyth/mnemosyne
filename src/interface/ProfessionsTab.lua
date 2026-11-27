-- ProfessionsTab: the window's Professions tab (decision 0008). Part of the
-- Interface adapter (decision 0004): it draws what Catalog gives, looking up
-- profession and recipe names in the game when shown. Its first page lists the
-- professions; a profession's page lists its recipes and its characters, and
-- a recipe hovered shows its tooltip, clicked shows who knows it, and
-- shift-clicked is linked in chat.
local _, ns = ...

local L = ns.L
local Client = ns.Client
local Catalog = ns.Catalog
local commands = ns.commands
local text = ns.widgets.text

local WIDTH = ns.Window.WIDTH
local ROW = 20

-- One of your professions' name and icon from GetProfessionInfo, or nil.
local function ownProfession(skillLine)
	local indexes = { GetProfessions() } -- holes where a slot is empty
	for i = 1, 5 do
		if indexes[i] then
			local name, icon, _, _, _, _, line = GetProfessionInfo(indexes[i])
			if line == skillLine then
				return name, icon
			end
		end
	end
end

-- The game's names, looked up when shown (decision 0008): one of yours as
-- GetProfessionInfo names it, the name your Professions window shows.
local lookups = {
	profession = function(skillLine)
		local name = ownProfession(skillLine)
		if name and name ~= "" then
			return name
		end
		name = C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)
		if name and name ~= "" then
			return name
		end
		local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
		return info and info.professionName ~= "" and info.professionName or nil
	end,
	recipe = C_Spell.GetSpellName,
	nickname = function(name)
		local identity = ns.recognition:recall(name)
		return identity and ns.recognition:nickname(identity)
	end,
}

-- The game's professions' icons, by skill line: the game gives an icon only
-- for a profession the character has (GetProfessionInfo), not for another's.
local PROFESSION_ICONS = {
	[171] = "Interface\\Icons\\Trade_Alchemy",
	[164] = "Interface\\Icons\\Trade_BlackSmithing",
	[333] = "Interface\\Icons\\Trade_Engraving",
	[202] = "Interface\\Icons\\Trade_Engineering",
	[182] = "Interface\\Icons\\Trade_Herbalism",
	[165] = "Interface\\Icons\\Trade_LeatherWorking",
	[186] = "Interface\\Icons\\Trade_Mining",
	[393] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
	[197] = "Interface\\Icons\\Trade_Tailoring",
	[185] = "Interface\\Icons\\INV_Misc_Food_15",
	[129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
	[356] = "Interface\\Icons\\Trade_Fishing",
}
local UNKNOWN_ICON = 134400 -- the question mark

-- A profession's icon: the game's for one of yours, else the table's.
local function professionIcon(skillLine)
	local _, icon = ownProfession(skillLine)
	return icon or PROFESSION_ICONS[skillLine] or UNKNOWN_ICON
end

-- Recipes' crafted items (false for none) and icons, by recipe ID, looked up
-- once a session: a redraw shows every recipe row.
local items, icons = {}, {}

-- The item a recipe crafts, or nil (an enchant, or a recipe the game does not
-- know: the ID came from a peer).
local function craftedItem(recipeID)
	if items[recipeID] == nil then
		local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
		local item = ok and schematic and schematic.outputItemID
		items[recipeID] = item and item ~= 0 and item or false
	end
	return items[recipeID] or nil
end

-- A recipe's icon: its item's, else its spell's, as the Professions window shows.
local function recipeIcon(recipeID)
	if not icons[recipeID] then
		local item = craftedItem(recipeID)
		icons[recipeID] = item and C_Item.GetItemIconByID(item) or C_Spell.GetSpellTexture(recipeID) or UNKNOWN_ICON
	end
	return icons[recipeID]
end

-- A recipe row's tooltip: its item's, else the recipe link's, right of the row.
local function showRecipe(row)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local item = craftedItem(row.recipe)
	local link = not item and C_TradeSkillUI.GetRecipeLink(row.recipe)
	if item then
		GameTooltip:SetItemByID(item)
	elseif link then
		GameTooltip:SetHyperlink(link)
	else
		GameTooltip:SetText(row.name:GetText())
	end
	GameTooltip:Show()
end

local function hideTooltip()
	GameTooltip:Hide()
end

-- A scrolled list of clickable rows, at x, width wide, under top. Each row has
-- the font strings of columns ({ key, x, width }) and an icon at x 7, empty
-- until set; onClick(row) on a click, onEnter(row) on hover if given. Only the
-- rows that fit are created, and filled again as the list scrolls: peers' data
-- can make a list of thousands, and a frame is never freed.
local function scrolledList(parent, x, top, width, columns, onClick, onEnter)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", x, -top)
	scroll:SetPoint("BOTTOMLEFT", x, 0)
	scroll:SetWidth(width - 28)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(width - 28, 1)
	scroll:SetScrollChild(list)
	list.empty = text(list, "GameFontDisableSmall", 7, 4, width - 35)
	list.rows = {}
	local count, fill = 0, nil -- what show was last given

	local function newRow()
		local row = CreateFrame("Button", nil, list)
		row:SetSize(width - 28, ROW)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		for _, column in ipairs(columns) do
			row[column[1]] = text(row, "GameFontHighlightSmall", column[2], 4, column[3])
			row[column[1]]:SetWordWrap(false)
		end
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(16, 16)
		row.icon:SetPoint("LEFT", 7, 0)
		row:SetScript("OnClick", onClick)
		if onEnter then
			row:SetScript("OnEnter", onEnter)
			row:SetScript("OnLeave", hideTooltip)
		end
		return row
	end

	-- Fills the rows in view at the current scroll (within the list's new
	-- height, should it have shrunk), placed where the i-th row of the list
	-- goes, and hides the others.
	local function draw()
		local height = scroll:GetHeight()
		local offset = math.min(scroll:GetVerticalScroll(), math.max(0, list:GetHeight() - height))
		local first = math.floor(offset / ROW) + 1
		local last = math.min(count, first + math.ceil(height / ROW))
		local drawn = 0
		for i = first, last do
			drawn = drawn + 1
			local row = list.rows[drawn] or newRow()
			list.rows[drawn] = row
			row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW))
			row:UnlockHighlight()
			row:SetAlpha(1)
			fill(row, i)
			row:Show()
			-- The row under the mouse now shows another line: its tooltip follows.
			if onEnter and GameTooltip:IsOwned(row) then
				onEnter(row)
			end
		end
		for i = drawn + 1, #list.rows do
			list.rows[i]:Hide()
		end
	end
	scroll:HookScript("OnVerticalScroll", draw)
	scroll:HookScript("OnSizeChanged", draw)

	-- Shows count rows, filling each with fill(row, i) as it comes into view;
	-- empty when none.
	function list:show(newCount, newFill, empty)
		count, fill = newCount, newFill
		self.empty:SetText(count == 0 and empty or "")
		self:SetHeight(count * ROW + 20)
		draw()
	end
	return list
end

-- Fills a row of the characters list from a Catalog row.
local function fillPerson(row, character)
	row.name:SetText(character.name)
	row.nickname:SetText(character.nickname or "")
	local skill = ("%d/%d"):format(character.level, character.maxLevel)
	row.skill:SetText(character.source and L.SECOND_HAND:format(skill) or skill)
	row.heard:SetText(
		character.own and L.PANEL_YOURS or character.source and L.PANEL_FROM:format(character.source) or ""
	)
	row.own = character.own
	row:SetAlpha(character.online and 1 or 0.6)
end

-- Builds the professions' view in content, viewWidth wide: Mnemosyne's window's
-- Professions tab, and the Guild & Communities window's (CommunitiesTab.lua).
-- Each view keeps its own page and selection.
local function newView(content, viewWidth)
	local refresh
	local RECIPES_WIDTH = math.floor(290 * viewWidth / WIDTH) -- the recipes list, left of the characters list
	local catalog, professions -- the Catalog and its professions, kept until the data changes
	local skillLine, recipe -- the profession and recipe selected, nil for none

	-- The first page: the professions as tiles, primary then secondary, laid out
	-- to fill the tab.
	local overview = CreateFrame("Frame", nil, content)
	overview:SetAllPoints()
	local GAP, HEADING = 6, 22
	local TILE_HEIGHT = 90 -- the icon, name and counts, about 82, and a margin
	local headings =
		{ text(overview, "GameFontNormal", 7, 4, viewWidth), text(overview, "GameFontNormal", 7, 4, viewWidth) }
	local tiles = {}

	-- The i-th tile: a profession's icon, name, recipe and character counts.
	local function tile(i)
		if not tiles[i] then
			local button = CreateFrame("Button", nil, overview)
			local background = button:CreateTexture(nil, "BACKGROUND")
			background:SetAllPoints()
			background:SetColorTexture(1, 1, 1, 0.06)
			button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			button.icon = button:CreateTexture(nil, "ARTWORK")
			button.icon:SetSize(36, 36)
			button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			button.name:SetPoint("TOP", button.icon, "BOTTOM", 0, -6)
			button.name:SetWordWrap(false)
			button.recipes = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.recipes:SetPoint("TOP", button.name, "BOTTOM", 0, -4)
			button.characters = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			button.characters:SetPoint("TOP", button.recipes, "BOTTOM", 0, -2)
			button:SetScript("OnClick", function(self)
				skillLine, recipe = self.skillLine, nil
				refresh()
			end)
			tiles[i] = button
		end
		return tiles[i]
	end

	-- Lays the professions out as tiles filling the overview: the column count
	-- giving the biggest tiles, at most twice as wide as high, among those tall
	-- enough for their content when one is. The gathering
	-- professions start their own row, under the Primary heading too.
	local HEADING_OF = { 1, 1, 2 } -- crafting, gathering, secondary
	local function layOut(found)
		local sections = { {}, {}, {} }
		for _, profession in ipairs(found) do
			table.insert(sections[profession.secondary and 3 or profession.gathering and 2 or 1], profession)
		end
		local width, height = overview:GetSize()
		local primary = #sections[1] + #sections[2] > 0
		local headed = (primary and 1 or 0) + (#sections[3] > 0 and 1 or 0)
		local free = height - headed * HEADING
		local function rows(columns)
			local count = 0
			for _, section in ipairs(sections) do
				count = count + math.ceil(#section / columns)
			end
			return count
		end
		-- Tiles tall enough for their content first, then the biggest.
		local columns, best, fits = 1, 0, false
		for count = 1, math.max(#sections[1], #sections[2], #sections[3]) do
			local size = math.min(width / count, 2 * free / rows(count))
			local tall = free / rows(count) - GAP >= TILE_HEIGHT
			if (tall and not fits) or (tall == fits and size > best) then
				columns, best, fits = count, size, tall
			end
		end
		local tileWidth, tileHeight = width / columns - GAP, free / rows(columns) - GAP
		local y, shown = 0, 0
		headings[1]:SetShown(primary)
		headings[2]:SetShown(#sections[3] > 0)
		local placed = {}
		for i, section in ipairs(sections) do
			local h = HEADING_OF[i]
			if #section > 0 and not placed[h] then
				placed[h] = true
				headings[h]:SetText(h == 1 and L.PROFESSIONS_PRIMARY or L.PROFESSIONS_SECONDARY)
				headings[h]:SetPoint("TOPLEFT", 7, -(y + 4))
				y = y + HEADING
			end
			if #section > 0 then
				for j, profession in ipairs(section) do
					shown = shown + 1
					local button = tile(shown)
					button.skillLine = profession.skillLine
					button:SetSize(tileWidth, tileHeight)
					button:SetPoint(
						"TOPLEFT",
						((j - 1) % columns) * (tileWidth + GAP),
						-(y + math.floor((j - 1) / columns) * (tileHeight + GAP))
					)
					-- The icon, name and counts (about 82 high) centred in the tile.
					button.icon:SetPoint("TOP", 0, -math.max(4, (tileHeight - 82) / 2))
					button.icon:SetTexture(professionIcon(profession.skillLine))
					button.name:SetWidth(tileWidth - 8)
					button.name:SetText(profession.name)
					button.recipes:SetText(L.PROFESSIONS_RECIPE_COUNT:format(profession.recipes))
					button.characters:SetText(L.PROFESSIONS_CHARACTER_COUNT:format(profession.characters))
					button:Show()
				end
				y = y + math.ceil(#section / columns) * (tileHeight + GAP)
			end
		end
		for i = shown + 1, #tiles do
			tiles[i]:Hide()
		end
	end

	-- A profession's page.
	local page = CreateFrame("Frame", nil, content)
	page:SetAllPoints()
	ns.widgets.button(page, L.PROFESSIONS_BACK, 4, 2, 70, function()
		skillLine, recipe = nil, nil
		refresh()
	end)
	local titleIcon = page:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(20, 20)
	titleIcon:SetPoint("TOPLEFT", 90, -3)
	local title = text(page, "GameFontNormalLarge", 114, 6, viewWidth - 424)
	local search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
	search:SetSize(260, 20)
	search:SetPoint("TOPRIGHT", -8, -4)
	search.Instructions:SetText(L.PROFESSIONS_SEARCH)
	search:HookScript("OnTextChanged", function()
		refresh()
	end)
	text(page, "GameFontNormalSmall", 7, 36, RECIPES_WIDTH - 14):SetText(L.PROFESSIONS_RECIPES)
	local recipes = scrolledList(page, 0, 52, RECIPES_WIDTH, {
		{ "name", 27, RECIPES_WIDTH - 100 },
		{ "count", RECIPES_WIDTH - 68, 40 },
	}, function(row)
		-- With a modifier, Blizzard's own handling of a clicked link: in chat.
		local link = IsModifiedClick() and C_TradeSkillUI.GetRecipeLink(row.recipe)
		local inner = link and link:match("|H(.-)|h")
		if inner then
			SetItemRef(inner, link, "LeftButton")
			return
		end
		recipe = recipe ~= row.recipe and row.recipe or nil
		refresh()
	end, showRecipe)
	local headingIcon = page:CreateTexture(nil, "ARTWORK")
	headingIcon:SetSize(14, 14)
	headingIcon:SetPoint("TOPLEFT", RECIPES_WIDTH + 7, -35)
	local heading = text(page, "GameFontNormalSmall", RECIPES_WIDTH + 7, 36, viewWidth - RECIPES_WIDTH - 32)
	local PEOPLE_WIDTH = viewWidth - RECIPES_WIDTH
	local scale = viewWidth / WIDTH -- the columns shrink in a narrower view
	local people = scrolledList(page, RECIPES_WIDTH, 52, PEOPLE_WIDTH, {
		{ "name", 7, math.floor(125 * scale) },
		{ "nickname", math.floor(135 * scale), math.floor(85 * scale) },
		{ "skill", math.floor(223 * scale), 60 },
		{ "heard", math.floor(285 * scale), math.floor(95 * scale) },
	}, function(row)
		if not row.own then
			ChatFrameUtil.SendTell(row.name:GetText())
		end
	end)

	function refresh()
		if not Client.playerName() then
			return -- before login: nothing to show yet
		end
		if not catalog then
			local SKILL_LINES = ns.Professions.SKILL_LINES
			catalog = Catalog.new(ns.professions:list(), MnemosyneDB.settings.showSecondHand, lookups, SKILL_LINES)
			professions = catalog:professions()
		end
		local shown
		for _, profession in ipairs(professions) do
			if profession.skillLine == skillLine then
				shown = profession
			end
		end
		overview:SetShown(not shown)
		page:SetShown(shown ~= nil)
		if not shown then
			skillLine, recipe = nil, nil
			layOut(professions)
			return
		end
		title:SetText(shown.name)
		titleIcon:SetTexture(professionIcon(skillLine))
		local wanted = search:GetText()
		local online = Client.onlineNames()
		local recipeList = catalog:recipes(skillLine, wanted)
		recipes:show(#recipeList, function(row, i)
			row.recipe = recipeList[i].recipe
			row.name:SetText(recipeList[i].name)
			row.icon:SetTexture(recipeIcon(row.recipe))
			row.count:SetText(recipeList[i].characters)
			if row.recipe == recipe then
				row:LockHighlight()
			end
		end, L.PROFESSIONS_NO_RECIPE)
		local characters
		headingIcon:SetTexture(recipe and recipeIcon(recipe) or nil)
		heading:SetPoint("TOPLEFT", RECIPES_WIDTH + (recipe and 25 or 7), -36)
		if recipe then
			heading:SetText(L.PROFESSIONS_KNOWN_BY:format(lookups.recipe(recipe) or recipe))
			characters = catalog:knowers(skillLine, recipe, online)
		else
			heading:SetText(L.PROFESSIONS_CHARACTERS)
			characters = catalog:characters(skillLine, wanted, online)
		end
		people:show(#characters, function(row, i)
			fillPerson(row, characters[i])
		end, "")
	end
	-- From outside (Window.refresh, on showing), the professions, your own or the
	-- setting may have changed: the Catalog is built again. A search, a click or
	-- Back keeps it.
	local function rebuild()
		catalog = nil
		refresh()
	end
	content.refresh = rebuild
	content:SetScript("OnShow", rebuild)
end

local ProfessionsTab = {}
ns.ProfessionsTab = ProfessionsTab
ProfessionsTab.newView = newView

newView(ns.Window.addTab("professions", L.PROFESSIONS), WIDTH)

commands.professions = function()
	ns.Window.open("professions")
end
