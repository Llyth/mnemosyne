-- Seed: the account's memory as 1.4.x left it (MnemosyneDB.memory,
-- .professions, .forgotten and .asked), which each character copies once
-- (decision 0001). Pure: it takes the saved tables and the clock's time as
-- arguments (decision 0004).
local _, ns = ...

local Seed = {}
ns.Seed = Seed

Seed.KEPT_FOR = 30 * 24 * 60 * 60 -- seconds the seed is kept after it was first seen

-- Keeps the seed, and starts a character from it at its first login.
-- account: the account's saved table (MnemosyneDB). The seed is never written
-- again, so a downgrade finds it as it was; when it was first seen is stamped
-- once (seededAt), and 30 days later it is dropped, as is whatever an older
-- version writes there afterwards.
-- character: the character's saved table (MnemosyneCharacterDB). At its first
-- login since the update (no schema yet), it gets a copy of the seed's
-- memory, professions and forgotten characters (Memory.copy,
-- Professions.copy: without disputes and daily counts); then its schema.
-- A character created since the update must start empty instead, which only
-- its name tells, read at login (isNew).
-- now: the server time, in seconds. schema: the saved tables' schema.
-- Returns true when it copied the seed.
function Seed.load(account, character, now, schema)
	if account.memory then
		account.seededAt = account.seededAt or now
	end
	if account.seededAt and now - account.seededAt >= Seed.KEPT_FOR then
		account.memory, account.professions, account.forgotten, account.asked = nil, nil, nil, nil
	end
	local copied = character.schema == nil and account.memory ~= nil
	if copied then
		character.memory = ns.Memory.copy(account.memory)
		character.professions = ns.Professions.copy(account.professions or {})
		character.forgotten = {}
		for name, forgotten in pairs(account.forgotten or {}) do
			character.forgotten[name] = forgotten
		end
	end
	character.schema = character.schema or schema
	return copied
end

-- Whether the character played, by its full name and its GUID, is new since
-- the update, so it starts empty rather than from the seed (decision 0001):
-- the account's characters (MnemosyneDB.characters, Self's saved table) did
-- not know it before this login, or knew another GUID for its name (that
-- character was deleted or renamed since). A character of 1.4.x that never
-- registered nor read its professions is not known either, and starts empty
-- too. guid: nil when the game did not give it.
function Seed.isNew(account, name, guid)
	local known = account.characters and account.characters[name]
	return known == nil or (guid ~= nil and known.guid ~= nil and known.guid ~= guid)
end
