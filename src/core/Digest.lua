-- Digest: the digest a sync compares (decision 0002), for identities (Memory)
-- and professions (Professions) alike. Each entry is a text hashed (hash), its
-- hash summed in the bucket of its character's name, modulo 2^32; the digest
-- writes each bucket's sum in 8 hexadecimal digits, Protocol.DIGEST_LENGTH in
-- all. Peers on every version must write the same digest for the same
-- entries, so none of this changes without a new protocol version. Pure
-- (decision 0004).
local _, ns = ...

local Digest = {}
Digest.__index = Digest
ns.Digest = Digest

Digest.BUCKETS = 128 -- of the digest, DIGITS each (BUCKETS * DIGITS = Protocol.DIGEST_LENGTH)

local DIGITS = 8 -- hexadecimal, a bucket of the digest
local HASH_MODULUS = 4294967296 -- 2^32: the hashes stay exact in a Lua number

-- A text's hash, a number below 2^32 (djb2).
function Digest.hash(text)
	local value = 5381
	for i = 1, #text do
		value = (value * 33 + text:byte(i)) % HASH_MODULUS
	end
	return value
end

-- The bucket a character's name falls in, from 1 to BUCKETS.
function Digest.bucket(name)
	return Digest.hash(name) % Digest.BUCKETS + 1
end

-- An empty digest: every bucket's sum zero.
function Digest.new()
	local sums = {}
	for bucket = 1, Digest.BUCKETS do
		sums[bucket] = 0
	end
	return setmetatable({ sums = sums }, Digest)
end

-- Adds a hashed text (from Digest.hash) in the bucket of a name.
function Digest:add(name, hashed)
	self:addIn(Digest.bucket(name), hashed)
end

-- Adds a hashed text in a bucket (Digest.bucket of its name, found once).
function Digest:addIn(bucket, hashed)
	self.sums[bucket] = (self.sums[bucket] + hashed) % HASH_MODULUS
end

-- Takes out a hashed text added before in the bucket of a name.
function Digest:remove(name, hashed)
	local bucket = Digest.bucket(name)
	self.sums[bucket] = (self.sums[bucket] - hashed) % HASH_MODULUS
end

-- The digest as it goes on the wire: DIGITS hexadecimal digits a bucket.
function Digest:write()
	local digits = {}
	for bucket, total in ipairs(self.sums) do
		-- Two halves: string.format's %x takes at most 32-bit signed integers on some builds.
		digits[bucket] = string.format("%04x%04x", math.floor(total / 65536), total % 65536)
	end
	return table.concat(digits)
end

-- The buckets two written digests differ in, in order.
function Digest.differing(mine, theirs)
	local found = {}
	for bucket = 1, Digest.BUCKETS do
		local first, last = (bucket - 1) * DIGITS + 1, bucket * DIGITS
		if mine:sub(first, last) ~= theirs:sub(first, last) then
			found[#found + 1] = bucket
		end
	end
	return found
end
