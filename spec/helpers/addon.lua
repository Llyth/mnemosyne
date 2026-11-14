-- Loads the addon's pure files (src/core/) the way the client does: each file
-- gets the addon name and a namespace table shared by all of them as its `...`.
-- A name with a folder is read from src/ instead.
--
--   local ns = require("spec.helpers.addon")("Protocol", "Self", "locales/enUS")
return function(...)
	local ns = {}
	for _, module in ipairs({ ... }) do
		local path = module:find("/", 1, true) and module or "core/" .. module
		local chunk = assert(loadfile("src/" .. path .. ".lua"))
		chunk("Mnemosyne", ns)
	end
	return ns
end
