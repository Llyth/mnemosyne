-- The .toc, the manifest the client and the packager read
-- (docs/decisions/0006-forever-only-with-a-plain-toc.md).
local function readToc()
	local file = assert(io.open("Mnemosyne.toc", "r"))
	local fields, files = {}, {}
	for line in file:lines() do
		local key, value = line:match("^## ([%w%-]+): *(.-)%s*$")
		if key then
			fields[key] = value
		elseif line:match("^[^#%s]") then
			files[#files + 1] = line:gsub("%s+$", "")
		end
	end
	file:close()
	return fields, files
end

describe("the .toc", function()
	local fields, files = readToc()

	it("targets WoW Forever", function()
		assert.equal("16001", fields.Interface)
	end)

	it("leaves the version to the packager", function()
		assert.equal("@project-version@", fields.Version)
	end)

	it("saves one account-wide table and one per character", function()
		assert.equal("MnemosyneDB", fields.SavedVariables)
		assert.equal("MnemosyneCharacterDB", fields.SavedVariablesPerCharacter)
	end)

	it("lists only files that exist", function()
		for _, path in ipairs(files) do
			local file = io.open((path:gsub("\\", "/")), "r")
			assert.is_not_nil(file, path .. " is listed in the .toc but missing")
			file:close()
		end
	end)
end)
