-- Seed: the account's memory as 1.4.x left it (MnemosyneDB.memory,
-- .professions, .forgotten and .asked), which each character copies once
-- (decision 0001). Pure: it takes the saved tables and the clock's time as
-- arguments (decision 0004).
local _, ns = ...

local Seed = {}
ns.Seed = Seed

Seed.KEPT_FOR = 30 * 24 * 60 * 60 -- seconds the seed is kept after it was first seen

-- Keeps the seed and gives a character its copy, at each login.
-- account: the account's saved table (MnemosyneDB). The seed is never written
-- again, so a downgrade finds it as it was; when it was first seen is stamped
-- once (seededAt), and 30 days later it is dropped, as is whatever an older
-- version writes there afterwards.
-- character: the character's saved table (MnemosyneCharacterDB). At its first
-- login since the update (no schema yet), it gets a copy of the seed's
-- memory, professions and forgotten characters (Memory.copy,
-- Professions.copy: without disputes and daily counts); then its schema.
-- now: the server time, in seconds. schema: the saved tables' schema.
function Seed.load(account, character, now, schema)
	if account.memory then
		account.seededAt = account.seededAt or now
	end
	if account.seededAt and now - account.seededAt >= Seed.KEPT_FOR then
		account.memory, account.professions, account.forgotten, account.asked = nil, nil, nil, nil
	end
	if character.schema == nil and account.memory then
		character.memory = ns.Memory.copy(account.memory)
		character.professions = ns.Professions.copy(account.professions or {})
		character.forgotten = {}
		for name, forgotten in pairs(account.forgotten or {}) do
			character.forgotten[name] = forgotten
		end
	end
	character.schema = character.schema or schema
end
