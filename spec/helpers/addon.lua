-- Loads the addon's pure files the way the client does: each file gets the
-- addon name and a namespace table shared by all of them as its `...`.
--
--   local ns = require("spec.helpers.addon")("Protocol", "Self")
return function(...)
	local ns = {}
	for _, module in ipairs({ ... }) do
		local chunk = assert(loadfile("src/" .. module .. ".lua"))
		chunk("Mnemosyne", ns)
	end
	return ns
end
