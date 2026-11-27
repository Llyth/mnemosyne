local ns = require("spec.helpers.addon")("Protocol", "Digest")
local Digest, Protocol = ns.Digest, ns.Protocol

describe("Digest", function()
	-- A digest written with these buckets set, the others zero.
	local function written(buckets)
		local expected = {}
		for bucket = 1, Digest.BUCKETS do
			expected[bucket] = buckets[bucket] or "00000000"
		end
		return table.concat(expected)
	end

	it("writes 8 hexadecimal digits a bucket, as long as a peer reads", function()
		local digest = Digest.new():write()
		assert.equal(Protocol.DIGEST_LENGTH, #digest)
		assert.equal(string.rep("0", Protocol.DIGEST_LENGTH), digest)
	end)

	it("writes a hashed text in its name's bucket as peers on 1.4.0 do", function()
		local digest = Digest.new()
		digest:add("Hugh Jass", Digest.hash("Hugh Jass\n900\nTony"))
		assert.equal(99, Digest.bucket("Hugh Jass"))
		assert.equal(written({ [99] = "5743bd59" }), digest:write())
	end)

	it("sums the hashes in a bucket past 2^32 without losing a digit", function()
		local digest = Digest.new()
		digest:add("Hugh Jass", 4294967295)
		digest:add("Hugh Jass", 4294967295)
		assert.equal(written({ [99] = "fffffffe" }), digest:write())
	end)

	it("takes out a hashed text it added, whatever was added since", function()
		local digest = Digest.new()
		digest:add("Hugh Jass", Digest.hash("a"))
		digest:add("Hugh Jass", Digest.hash("b"))
		digest:remove("Hugh Jass", Digest.hash("a"))
		local only = Digest.new()
		only:add("Hugh Jass", Digest.hash("b"))
		assert.equal(only:write(), digest:write())
	end)

	it("finds exactly the bucket two digests differ in", function()
		for _, bucket in ipairs({ 1, 42, Digest.BUCKETS }) do
			local theirs = written({ [bucket] = "0000002a" })
			assert.same({ bucket }, Digest.differing(Digest.new():write(), theirs))
		end
	end)

	it("finds no bucket between two digests of the same hashes", function()
		local mine, theirs = Digest.new(), Digest.new()
		for _, digest in ipairs({ mine, theirs }) do
			digest:add("Hugh Jass", Digest.hash("Tony"))
			digest:add("Anna Conda", Digest.hash("Ann"))
		end
		assert.same({}, Digest.differing(mine:write(), theirs:write()))
	end)
end)
