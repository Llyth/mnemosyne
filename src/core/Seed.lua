-- Seed: the account's memory as 1.4.x left it (MnemosyneDB.memory,
-- .professions, .forgotten and .asked), whose identities, professions and
-- forgotten characters each character copies once, without disputes and daily
-- counts (decision 0001). Pure: it takes the saved tables and the clock's time as
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
-- its name tells, read at login (Seed.login).
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
-- the account's characters (Self, before it learns this login's) do not own
-- the name under that GUID (Self:owns): they did not know it, knew another
-- GUID for it (that character was deleted or renamed since), or saw another
-- player's character take it. A character of 1.4.x that never registered nor
-- read its professions is not known either, and starts empty too. guid: nil
-- when the game did not give it.
function Seed.isNew(characters, name, guid)
	return not characters:owns(name, guid)
end

-- The login step that finishes the seed, once the character played is known
-- by its full name and GUID (nil when the game did not give it): a character
-- that copied the seed at this load (copied, Seed.load) but is new since the
-- update (isNew), or started empty at an earlier login (Self:startedEmpty:
-- its own saved table did not come back, a known Forever bug), drops it
-- (Memory:empty, Professions:empty), and the account remembers it started
-- empty; then this account's characters (Self) learn its GUID, which isNew
-- must not see first.
function Seed.login(characters, name, guid, copied, memory, professions)
	if copied and (characters:startedEmpty(name) or Seed.isNew(characters, name, guid)) then
		memory:empty()
		professions:empty()
		characters:startEmpty(name)
	end
	if guid then
		characters:see(name, guid)
	end
end
