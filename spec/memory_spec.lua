local ns = require("spec.helpers.addon")("Protocol", "Digest", "Memory", "Self")
local Memory, Protocol, Self = ns.Memory, ns.Protocol, ns.Self

describe("Memory", function()
	local now, saved, memory

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		memory = Memory.new(saved, clock)
	end)

	it("recalls nothing about a character it never heard", function()
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("recalls an identity heard first-hand, with when it was heard", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.same({ nickname = "Tony", revision = 900, firstHand = true, heard = 1000 }, memory:recall("Hugh Jass"))
	end)

	it("keeps each character's identity apart", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
		assert.is_nil(memory:recall("Hugh"))
	end)

	it("lets a later revision change the nickname", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		now = 2000
		memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
		assert.same(
			{ nickname = "Antoine", revision = 1900, firstHand = true, heard = 2000 },
			memory:recall("Hugh Jass")
		)
	end)

	it("keeps the later revision when an earlier one arrives late", function()
		memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.equal("Antoine", memory:recall("Hugh Jass").nickname)
	end)

	it("forgets a character's identity when the character unregisters", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 901 })
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("forgets a character's identity when the character answers that it is anonymous", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		local message = Protocol.read("2:N:901")
		memory:hear("Hugh Jass", { nickname = message.nickname, revision = message.revision })
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("ignores an unregistering older than the identity it holds", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 800 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("learns the identity again when the character registers after unregistering", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Hugh Jass", { revision = 901 })
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 902 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("keeps what it heard in its saved table", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		local reloaded = Memory.new(saved, clock)
		assert.equal("Tony", reloaded:recall("Hugh Jass").nickname)
	end)

	it("knows a character it heard of, registered or not", function()
		assert.is_false(memory:knows("Hugh Jass"))
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:hear("Anna Conda", { revision = 900 })
		assert.is_true(memory:knows("Hugh Jass"))
		assert.is_true(memory:knows("Anna Conda"))
	end)

	it("does not count a character it heard of only second-hand as known, so it still asks it", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
		assert.is_false(memory:knows("Hugh Jass"))
	end)

	it("hands out copies, so a caller cannot change what it remembers", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:recall("Hugh Jass").nickname = "Mallory"
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	describe("search", function()
		before_each(function()
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			memory:hear("Anna Conda", { nickname = "Tony", revision = 900 })
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 900 })
			memory:hear("Barb Dwyer", { nickname = "Æsa Øyvind", revision = 900 })
		end)

		local function names(results)
			local list = {}
			for _, identity in ipairs(results) do
				list[#list + 1] = identity.name
			end
			return list
		end

		it("finds every character of a nickname, sorted by name", function()
			assert.same({ "Anna Conda", "Hugh Jass" }, names(memory:search("Tony")))
		end)

		it("finds a character by its name or part of it", function()
			assert.same({ "Hugh Jass" }, names(memory:search("jass")))
			assert.same({ "Anna Conda" }, names(memory:search("anna c")))
		end)

		it("ignores case", function()
			assert.same({ "Anna Conda", "Hugh Jass" }, names(memory:search("tONY")))
			assert.same({ "Élise Bérénice" }, names(memory:search("ÉLISE")))
		end)

		it("ignores accents, in the text and in the identities", function()
			assert.same({ "Élise Bérénice" }, names(memory:search("elise berenice")))
			assert.same({ "Élise Bérénice" }, names(memory:search("zoe")))
			assert.same({ "Élise Bérénice" }, names(memory:search("Zoë")))
			assert.same({ "Barb Dwyer" }, names(memory:search("aesa oyvind")))
		end)

		it("gives each identity found with its name", function()
			assert.same(
				{ { name = "Hugh Jass", nickname = "Tony", revision = 900, firstHand = true, heard = 1000 } },
				memory:search("Hugh")
			)
		end)

		it("finds nothing for a text no identity holds", function()
			assert.same({}, memory:search("Mallory"))
		end)

		it("reads the text as plain text, not as a pattern", function()
			assert.same({}, memory:search("."))
			assert.same({}, memory:search("%a"))
			assert.same({}, memory:search("["))
		end)

		it("does not find a character that unregistered", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.same({ "Anna Conda" }, names(memory:search("Tony")))
		end)

		it("counts the identities it holds", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.equal(3, memory:count())
		end)

		it("counts only first-hand identities when asked", function()
			memory:hear("Paige Turner", { nickname = "Paige", revision = 900, source = "Anna Conda" })
			assert.equal(5, memory:count())
			assert.equal(4, memory:count(true))
		end)
	end)
end)

describe("Memory, second-hand", function()
	local DAY = 24 * 60 * 60
	local now, saved, memory

	local function clock()
		return now
	end

	before_each(function()
		now = 1000
		saved = {}
		memory = Memory.new(saved, clock)
	end)

	local function hearFrom(source, name, nickname, revision)
		return memory:hear(name, { nickname = nickname, revision = revision, source = source })
	end

	it("recalls an identity heard second-hand, with its source", function()
		assert.is_true(hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900))
		assert.same(
			{ nickname = "Tony", revision = 900, firstHand = false, source = "Barb Dwyer", heard = 1000 },
			memory:recall("Hugh Jass")
		)
	end)

	it("lets a first-hand identity replace a second-hand one, whatever its revision", function()
		hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 99999999999999)
		assert.is_true(memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 }))
		assert.same({ nickname = "Tony", revision = 900, firstHand = true, heard = 1000 }, memory:recall("Hugh Jass"))
	end)

	it("never lets a second-hand copy replace a first-hand identity", function()
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.is_false(hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 99999999999999))
		assert.is_false(hearFrom("Mallory Knox", "Hugh Jass", nil, 99999999999999))
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("refuses a second-hand revision from more than a day ahead, which no later change could beat", function()
		assert.is_false(hearFrom("Mallory Knox", "Hugh Jass", "Mallory", now + 24 * 60 * 60 + 1))
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.is_true(hearFrom("Barb Dwyer", "Hugh Jass", "Tony", now + 24 * 60 * 60))
	end)

	it("lets the later revision win among second-hand copies", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		now = 2000
		assert.is_true(hearFrom("Anna Conda", "Hugh Jass", "Antoine", 1900))
		assert.same(
			{ nickname = "Antoine", revision = 1900, firstHand = false, source = "Anna Conda", heard = 2000 },
			memory:recall("Hugh Jass")
		)
		assert.is_false(hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900))
		assert.equal("Antoine", memory:recall("Hugh Jass").nickname)
	end)

	it("changes nothing when a second-hand copy repeats what it holds", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		now = 2000
		assert.is_false(hearFrom("Anna Conda", "Hugh Jass", "Tony", 900))
		assert.same(
			{ nickname = "Tony", revision = 900, firstHand = false, source = "Barb Dwyer", heard = 1000 },
			memory:recall("Hugh Jass")
		)
	end)

	it("forgets a second-hand identity when the character's unregistering arrives second-hand", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		assert.is_true(hearFrom("Anna Conda", "Hugh Jass", nil, 901))
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.is_false(hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900))
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("hides an identity that peers dispute: the same revision with different nicknames", function()
		assert.same({ true }, { hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900) })
		assert.same({ true, "disputed" }, { hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 900) })
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.same({}, memory:search("Hugh"))
		assert.equal(0, memory:count())
	end)

	it("disputes a nickname and a removal at the same revision", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		hearFrom("Mallory Knox", "Hugh Jass", nil, 900)
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("holds a character as withdrawn while its identity is a removal, disputed or not", function()
		assert.is_false(memory:isWithdrawn("Hugh Jass"))
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.is_false(memory:isWithdrawn("Hugh Jass"))
		memory:hear("Hugh Jass", { revision = 950 })
		assert.is_true(memory:isWithdrawn("Hugh Jass"))
		hearFrom("Barb Dwyer", "Anna Conda", nil, 900)
		hearFrom("Mallory Knox", "Anna Conda", "Ann", 900)
		assert.is_true(memory:isWithdrawn("Anna Conda"))
	end)

	it("holds a character as withdrawn when a removal disputes its nickname, whichever came first", function()
		hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 900)
		hearFrom("Barb Dwyer", "Hugh Jass", nil, 900)
		assert.is_true(memory:isWithdrawn("Hugh Jass"))
		hearFrom("Mallory Knox", "Anna Conda", "Mallory", 900)
		hearFrom("Bo Nanza", "Anna Conda", "Bo", 900)
		hearFrom("Barb Dwyer", "Anna Conda", nil, 900)
		assert.is_true(memory:isWithdrawn("Anna Conda"))
	end)

	it("settles a dispute when the character speaks first-hand", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 900)
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("settles a dispute with a later revision", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 900)
		hearFrom("Anna Conda", "Hugh Jass", "Antoine", 901)
		assert.equal("Antoine", memory:recall("Hugh Jass").nickname)
	end)

	it("accepts at most 1,000 new second-hand identities from one peer a day", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			assert.is_true(hearFrom("Mallory Knox", "Hugh Jass" .. i, "Tony", 900))
		end
		assert.is_false(hearFrom("Mallory Knox", "Anna Conda", "Ann", 900))
		assert.is_nil(memory:recall("Anna Conda"))
		assert.is_true(hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900))
		now = now + DAY
		assert.is_true(hearFrom("Mallory Knox", "Barb Dwyer", "Barb", 900))
	end)

	it("counts every change from one peer toward its 1,000 a day: later revisions and disputes too", function()
		local half = Memory.MAX_CHANGES_PER_PEER / 2
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			hearFrom("Barb Dwyer", "Hugh Jass" .. i, "Tony", 900)
		end
		for i = 1, half do
			assert.is_true(hearFrom("Mallory Knox", "Hugh Jass" .. i, "Mallory", 901))
			assert.is_true(hearFrom("Mallory Knox", "Hugh Jass" .. (half + i), "Mallory", 900))
		end
		assert.is_false(hearFrom("Mallory Knox", "Hugh Jass1", "Mal", 902))
		assert.equal("Mallory", memory:recall("Hugh Jass1").nickname)
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		assert.is_false(hearFrom("Mallory Knox", "Anna Conda", "Mallory", 901))
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
		now = now + DAY
		assert.is_true(hearFrom("Mallory Knox", "Hugh Jass1", "Mal", 902))
	end)

	it("takes up to 5,000 more changes a day from one peer, vouched as heard first-hand in the last day", function()
		local function vouched(name, revision)
			return memory:hear(
				name,
				{ nickname = "Tony", revision = revision, source = "Mallory Knox", vouched = true }
			)
		end
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			assert.is_true(hearFrom("Mallory Knox", "Hugh Jass" .. i, "Tony", 900))
		end
		for i = 1, Memory.MAX_VOUCHED_PER_PEER do
			assert.is_true(vouched("Anna Conda" .. i, now - 10))
		end
		assert.is_false(vouched("Barb Dwyer", now - 10))
		-- A vouched change older than a day counts as any other.
		now = now + DAY
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			assert.is_true(vouched("Cole Slaw" .. i, now - DAY - 1))
		end
		assert.is_true(vouched("Ella Vator", now - 10))
		assert.is_false(vouched("Barb Dwyer", now - DAY - 1))
	end)

	it("counts a vouched change dated ahead of the clock as any other: no real change is", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			memory:hear(
				"Hugh Jass" .. i,
				{ nickname = "Tony", revision = now + 60, source = "Mallory Knox", vouched = true }
			)
		end
		assert.is_false(
			memory:hear(
				"Anna Conda",
				{ nickname = "Ann", revision = now + 60, source = "Mallory Knox", vouched = true }
			)
		)
		assert.is_true(
			memory:hear(
				"Anna Conda",
				{ nickname = "Ann", revision = now - 10, source = "Mallory Knox", vouched = true }
			)
		)
	end)

	it("counts removals from one peer toward its 1,000 a day", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			assert.is_true(hearFrom("Mallory Knox", "Hugh Jass" .. i, nil, 900))
		end
		assert.is_false(hearFrom("Mallory Knox", "Anna Conda", "Ann", 900))
	end)

	it("does not count a copy it refuses toward the peer's 1,000 a day", function()
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		for _ = 1, Memory.MAX_CHANGES_PER_PEER do
			hearFrom("Mallory Knox", "Hugh Jass", "Tony", 900)
		end
		assert.is_true(hearFrom("Mallory Knox", "Anna Conda", "Ann", 900))
	end)

	it("lets go at load the counts of a peer's changes older than a day", function()
		hearFrom("Mallory Knox", "Hugh Jass", "Tony", 900)
		now = now + DAY
		hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900)
		Memory.new(saved, clock)
		assert.is_nil(saved.newFrom["Mallory Knox"])
		assert.is_not_nil(saved.newFrom["Barb Dwyer"])
	end)

	it("keeps counting a peer's changes after a reload", function()
		for i = 1, Memory.MAX_CHANGES_PER_PEER do
			hearFrom("Mallory Knox", "Hugh Jass" .. i, "Tony", 900)
		end
		memory = Memory.new(saved, clock)
		assert.is_false(hearFrom("Mallory Knox", "Anna Conda", "Ann", 900))
	end)

	it("keeps at most 20,000 second-hand identities, dropping the oldest heard first", function()
		local peer = 0
		for i = 1, Memory.MAX_SECOND_HAND do
			if i % Memory.MAX_CHANGES_PER_PEER == 1 then
				peer = peer + 1
			end
			now = 1000 + i
			hearFrom("Peer" .. peer, "Hugh Jass" .. i, "Tony", 900)
		end
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		assert.equal(Memory.MAX_SECOND_HAND + 1, memory:count())
		now = now + 1
		assert.is_true(hearFrom("Barb Dwyer", "Barb Dwyer", "Barb", 900))
		assert.equal(Memory.MAX_SECOND_HAND + 1, memory:count())
		assert.is_nil(memory:recall("Hugh Jass1"))
		assert.equal("Tony", memory:recall("Hugh Jass2").nickname)
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
		memory = Memory.new(saved, clock)
		now = now + 1
		hearFrom("Barb Dwyer", "Élise Bérénice", "Zoé", 900)
		assert.is_nil(memory:recall("Hugh Jass2"))
		assert.equal(Memory.MAX_SECOND_HAND + 1, memory:count())
	end)

	-- Fills the memory with as many second-hand identities as it keeps, one a second.
	local function fill()
		for i = 1, Memory.MAX_SECOND_HAND do
			now = 1000 + i
			hearFrom("Peer" .. math.ceil(i / Memory.MAX_CHANGES_PER_PEER), "Hugh Jass" .. i, "Tony", 900)
		end
	end

	it("drops an identity heard again only after the ones heard since", function()
		fill()
		now = now + 1
		assert.is_true(hearFrom("Barb Dwyer", "Hugh Jass1", "Antoine", 901))
		assert.is_true(hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900))
		assert.equal("Antoine", memory:recall("Hugh Jass1").nickname)
		assert.is_nil(memory:recall("Hugh Jass2"))
	end)

	it("keeps recalling first-hand a character heard second-hand first, when the memory is full", function()
		hearFrom("Barb Dwyer", "Anna Conda", "Annie", 900)
		memory:hear("Anna Conda", { nickname = "Ann", revision = 901 })
		fill()
		now = now + 1
		assert.is_true(hearFrom("Barb Dwyer", "Barb Dwyer", "Barb", 900))
		assert.is_true(memory:recall("Anna Conda").firstHand)
		assert.equal(Memory.MAX_SECOND_HAND + 1, memory:count())
	end)

	it("keeps its drop queue small however often an identity changes", function()
		for revision = 1, 10000 do
			now = 1000 + revision
			-- Each from one of many peers, as a peer brings at most 1,000 changes a day.
			local peer = "Barb Dwyer" .. math.ceil(revision / Memory.MAX_CHANGES_PER_PEER)
			assert.is_true(hearFrom(peer, "Anna Conda", "Ann", revision))
		end
		assert.is_true(memory.queueEnd - memory.queueStart < 2000)
	end)

	it("still drops the identity heard first once its drop queue is compacted", function()
		for revision = 1, 10000 do
			now = 1000 + revision
			-- Each from one of many peers, as a peer brings at most 1,000 changes a day.
			local peer = "Barb Dwyer" .. math.ceil(revision / Memory.MAX_CHANGES_PER_PEER)
			assert.is_true(hearFrom(peer, "Anna Conda", "Ann", revision))
		end
		fill() -- its last identity drops Anna Conda
		now = now + 1
		assert.is_true(hearFrom("Zed", "Ella Vator", "Ella", 900))
		assert.is_nil(memory:recall("Anna Conda"))
		assert.is_nil(memory:recall("Hugh Jass1"))
		assert.is_not_nil(memory:recall("Hugh Jass2"))
	end)

	it("keeps dropping the oldest heard first after compacting its drop queue", function()
		hearFrom("Barb Dwyer", "Cole Slaw", "Cole", 900)
		hearFrom("Barb Dwyer", "Ella Vator", "Ella", 900)
		-- Enough changes to compact the queue, each peer bringing at most 1,000 a day.
		for revision = 1, 2 * Memory.MAX_CHANGES_PER_PEER do
			now = 1000 + revision
			local peer = "Mallory Knox" .. math.ceil(revision / Memory.MAX_CHANGES_PER_PEER)
			assert.is_true(hearFrom(peer, "Anna Conda", "Ann", revision))
		end
		for i = 4, Memory.MAX_SECOND_HAND do
			now = now + 1
			hearFrom("Peer" .. math.ceil(i / Memory.MAX_CHANGES_PER_PEER), "Hugh Jass" .. i, "Tony", 900)
		end
		now = now + 1
		assert.is_true(hearFrom("Zed", "Ida Know", "Ida", 900))
		assert.is_nil(memory:recall("Cole Slaw"))
		assert.equal("Ella", memory:recall("Ella Vator").nickname)
		assert.is_true(hearFrom("Zed", "Bo Nanza", "Bo", 900))
		assert.is_nil(memory:recall("Ella Vator"))
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
		assert.is_true(hearFrom("Zed", "Barb Dwyer", "Barb", 900))
		assert.is_nil(memory:recall("Anna Conda"))
		assert.equal("Tony", memory:recall("Hugh Jass4").nickname)
	end)

	it("keeps its digest the same as one hashed anew, whatever it hears", function()
		fill()
		math.randomseed(42)
		for _ = 1, 2000 do
			now = now + 1
			local name = "Hugh Jass" .. math.random(Memory.MAX_SECOND_HAND + 100)
			local nickname = ({ "Tony", "Antoine" })[math.random(3)] -- nil a third of the time: a removal
			local revision = 900 + math.random(3)
			if math.random(4) == 1 then
				memory:hear(name, { nickname = nickname, revision = revision })
			else
				hearFrom("Peer" .. math.random(100), name, nickname, revision)
			end
		end
		assert.equal(Memory.new(saved, clock):digest(), memory:digest())
	end)

	it("passes on the same as one loaded anew, whatever it hears, drops or forgets", function()
		fill()
		math.randomseed(7)
		for _ = 1, 2000 do
			now = now + 1
			local name = "Hugh Jass" .. math.random(Memory.MAX_SECOND_HAND + 100)
			local nickname = ({ "Tony", "Antoine" })[math.random(2)] -- two at one revision: a dispute
			local roll = math.random(20)
			if roll == 1 then
				memory:forget(name)
			elseif roll == 2 then
				memory:see(name, "Player-1-" .. math.random(2)) -- a second GUID makes it stale
			elseif roll <= 7 then
				memory:hear(name, { nickname = nickname, revision = 900 + math.random(3) })
			else
				hearFrom("Peer" .. math.random(100), name, nickname, 900 + math.random(3))
			end
		end
		local empty = Memory.new({}, clock):digest()
		local loaded, held = Memory.new(saved, clock):missing(empty), memory:missing(empty)
		table.sort(loaded)
		table.sort(held)
		assert.same(loaded, held)
	end)

	describe("digest", function()
		local other

		before_each(function()
			other = Memory.new({}, clock)
			for _, m in ipairs({ memory, other }) do
				m:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
				m:hear("Anna Conda", { revision = 901, source = "Barb Dwyer" })
			end
		end)

		local function sorted(missing)
			table.sort(missing)
			return missing
		end

		it("hashes a memory in a digest a peer can read", function()
			local digest = memory:digest()
			assert.equal(Protocol.DIGEST_LENGTH, #digest)
			local reader = Protocol.newReader(clock)
			local message
			for _, chunk in ipairs(Protocol.newWriter():split(Protocol.write({ kind = "digest", digest = digest }))) do
				message = reader:read("Barb Dwyer", chunk)
			end
			assert.equal(digest, message.digest)
		end)

		it("gives the digest peers on 1.4.0 give for the same identities", function()
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 902 })
			local buckets = { [9] = "e05f9036", [42] = "f2c045ad", [99] = "5743bd59" }
			local expected = {}
			for bucket = 1, Protocol.DIGEST_LENGTH / 8 do
				expected[bucket] = buckets[bucket] or "00000000"
			end
			assert.equal(table.concat(expected), memory:digest())
		end)

		it("gives the same digest for the same identities, whoever heard them how", function()
			other = Memory.new({}, clock)
			other:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
			other:hear("Anna Conda", { revision = 901 })
			assert.equal(memory:digest(), other:digest())
			assert.same({}, memory:missing(other:digest()))
		end)

		it("passes on what a peer's digest lacks: identities and removals", function()
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 902 })
			memory:hear("Barb Dwyer", { revision = 903 })
			assert.same({ "Barb Dwyer", "Élise Bérénice" }, sorted(memory:missing(other:digest())))
			assert.same({}, sorted(other:missing(memory:digest())))
		end)

		it("passes on what a peer holds at an older revision, without saying how it heard it", function()
			memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
			assert.same({ "Hugh Jass" }, memory:missing(other:digest()))
			assert.same({ name = "Hugh Jass", nickname = "Antoine", revision = 1900 }, memory:passOn("Hugh Jass"))
		end)

		it("leaves a disputed identity out of its digest", function()
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 902, source = "Barb Dwyer" })
			memory:hear("Élise Bérénice", { nickname = "Mallory", revision = 902, source = "Mallory Knox" })
			assert.equal(other:digest(), memory:digest())
		end)

		it("never passes on a disputed identity", function()
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 902, source = "Barb Dwyer" })
			memory:hear("Élise Bérénice", { nickname = "Mallory", revision = 902, source = "Mallory Knox" })
			assert.same({}, memory:missing(other:digest()))
		end)
	end)

	describe("forgetting", function()
		local forgotten

		before_each(function()
			forgotten = {}
			memory = Memory.new(saved, clock, forgotten)
		end)

		it("drops a forgotten character's identity, from its digest too", function()
			local empty = memory:digest()
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
			assert.is_true(memory:forget("Hugh Jass"))
			assert.is_nil(memory:recall("Hugh Jass"))
			assert.equal(empty, memory:digest())
			assert.same({}, memory:missing(Memory.new({}, clock):digest()))
		end)

		it("refuses second-hand copies of a forgotten character", function()
			memory:forget("Hugh Jass")
			assert.is_false(memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" }))
			assert.is_nil(memory:recall("Hugh Jass"))
		end)

		it("still hears a forgotten character first-hand", function()
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			memory:forget("Hugh Jass")
			assert.is_true(memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 }))
			assert.equal("Tony", memory:recall("Hugh Jass").nickname)
			assert.is_false(memory:hear("Hugh Jass", { nickname = "Mallory", revision = 950, source = "Mallory Knox" }))
		end)

		it("learns second-hand again once the character is unforgotten", function()
			memory:forget("Hugh Jass")
			assert.is_true(memory:unforget("Hugh Jass"))
			assert.is_false(memory:unforget("Hugh Jass"))
			assert.is_true(memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" }))
			assert.equal("Tony", memory:recall("Hugh Jass").nickname)
		end)

		it("finds the full name a player typed, ignoring case and accents", function()
			memory:hear("Élise Bérénice", { revision = 902, source = "Barb Dwyer" })
			memory:forget("Hugh Jass")
			assert.equal("Élise Bérénice", memory:fullName("elise berenice"))
			assert.equal("Hugh Jass", memory:fullName("HUGH JASS"))
			assert.is_nil(memory:fullName("Hugh"))
		end)

		it("keeps finding full names as identities come and go after a first look", function()
			assert.is_nil(memory:fullName("elise berenice"))
			memory:hear("Élise Bérénice", { revision = 902, source = "Barb Dwyer" })
			memory:hear("Elise Berenice", { revision = 902, source = "Barb Dwyer" })
			assert.is_not_nil(memory:fullName("elise berenice"))
			memory:forget("Élise Bérénice")
			memory:unforget("Élise Bérénice")
			assert.equal("Elise Berenice", memory:fullName("ELISE BERENICE"))
			memory:forget("Elise Berenice")
			memory:unforget("Elise Berenice")
			assert.is_nil(memory:fullName("elise berenice"))
		end)

		it("forgets a character typed in another case or without its accents", function()
			assert.is_true(memory:forget("elise berenice"))
			assert.is_false(memory:forget("Élise Bérénice"))
			assert.is_true(memory:isForgotten("Élise Bérénice"))
			assert.is_false(
				memory:hear("Élise Bérénice", { nickname = "Lili", revision = 900, source = "Barb Dwyer" })
			)
			assert.is_true(memory:unforget("ÉLISE BÉRÉNICE"))
			assert.same({}, memory:forgotten())
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
			memory:forget("hugh jass")
			assert.is_nil(memory:recall("Hugh Jass"))
			assert.same({ "Hugh Jass" }, memory:forgotten())
		end)

		it("lists the forgotten characters by name, kept in the saved table", function()
			assert.is_true(memory:forget("Hugh Jass"))
			assert.is_false(memory:forget("Hugh Jass"))
			memory:forget("Anna Conda")
			assert.same({ "Anna Conda", "Hugh Jass" }, Memory.new({}, clock, forgotten):forgotten())
		end)
	end)

	describe("listing for the window", function()
		local forgotten

		before_each(function()
			forgotten = {}
			memory = Memory.new(saved, clock, forgotten)
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			now = 2000
			memory:hear("Anna Conda", { nickname = "Ann", revision = 900, source = "Barb Dwyer" })
		end)

		local function names(results)
			local list = {}
			for _, entry in ipairs(results) do
				list[#list + 1] = entry.name
			end
			return list
		end

		it("lists first-hand and second-hand identities with how they were heard", function()
			assert.same({
				{ name = "Anna Conda", nickname = "Ann", firstHand = false, source = "Barb Dwyer", heard = 2000 },
				{ name = "Hugh Jass", nickname = "Tony", firstHand = true, heard = 1000 },
			}, memory:list(""))
		end)

		it("lists a disputed identity, marked disputed", function()
			memory:hear("Anna Conda", { nickname = "Mallory", revision = 900, source = "Cole Slaw" })
			assert.is_nil(memory:recall("Anna Conda"))
			assert.is_true(memory:list("Anna")[1].disputed)
		end)

		it("leaves out a character that unregistered", function()
			memory:hear("Hugh Jass", { revision = 901 })
			assert.same({ "Anna Conda" }, names(memory:list("")))
		end)

		it("leaves out a stale identity, hidden as recall hides it", function()
			memory:see("Hugh Jass", "Player-1-00000001")
			memory:see("Hugh Jass", "Player-1-00000002")
			assert.same({ "Anna Conda" }, names(memory:list("")))
		end)

		it("lists the forgotten characters, marked forgotten", function()
			memory:forget("Hugh Jass")
			memory:forget("Cole Slaw")
			assert.same({
				{ name = "Anna Conda", nickname = "Ann", firstHand = false, source = "Barb Dwyer", heard = 2000 },
				{ name = "Cole Slaw", forgotten = true },
				{ name = "Hugh Jass", forgotten = true },
			}, memory:list(""))
		end)

		it("lists a forgotten character heard first-hand again once, with its nickname", function()
			memory:forget("Hugh Jass")
			memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
			assert.same(
				{ { name = "Hugh Jass", nickname = "Tony", firstHand = true, heard = 2000, forgotten = true } },
				memory:list("Hugh")
			)
		end)

		it("finds by name or nickname, ignoring case and accents", function()
			memory:hear("Élise Bérénice", { nickname = "Zoé", revision = 900 })
			memory:forget("Cole Slaw")
			assert.same({ "Élise Bérénice" }, names(memory:list("ZOE")))
			assert.same({ "Anna Conda" }, names(memory:list("ann")))
			assert.same({ "Cole Slaw" }, names(memory:list("cole")))
			assert.same({}, names(memory:list("%a")))
		end)

		it("sorts by nickname, ignoring case and accents, then by name, forgotten characters last", function()
			memory:hear("Zed Zulu", { nickname = "Émile", revision = 900 })
			memory:hear("Cole Slaw", { nickname = "bea", revision = 900 })
			memory:hear("Yan Yak", { nickname = "Tony", revision = 900 })
			memory:forget("Barb Dwyer")
			local expected = { "Anna Conda", "Cole Slaw", "Zed Zulu", "Hugh Jass", "Yan Yak", "Barb Dwyer" }
			assert.same(expected, names(memory:list("")))
			assert.same(expected, names(memory:list("", 10)))
		end)

		it("gives at most the rows asked for, the first by nickname, and how many it found", function()
			memory:hear("Cole Slaw", { nickname = "Coco", revision = 900 })
			memory:forget("Barb Dwyer")
			local found, total = memory:list("", 2)
			assert.same({ "Anna Conda", "Cole Slaw" }, names(found))
			assert.equal(4, total)
			found, total = memory:list("", 0)
			assert.same({}, found)
			assert.equal(4, total)
		end)

		it("lists only the rows kept, and counts only those", function()
			memory:hear("Cole Slaw", { nickname = "Coco", revision = 900 })
			memory:forget("Barb Dwyer")
			local found, total = memory:list("", 1, function(name, known, isForgotten)
				return isForgotten or (known.source == nil and name ~= "Cole Slaw")
			end)
			assert.same({ "Hugh Jass" }, names(found))
			assert.equal(2, total)
		end)
	end)
end)

describe("Memory, stale", function()
	local OLD, NEW = "Player-1-00000001", "Player-1-00000002"
	local now, memory

	local function clock()
		return now
	end

	local function hearFrom(source, name, nickname, revision, guid)
		return memory:hear(name, { nickname = nickname, revision = revision, source = source, guid = guid })
	end

	-- What the memory passes on to a peer that holds nothing.
	local function passedOn()
		local passed = {}
		for i, name in ipairs(memory:missing(Memory.new({}, clock):digest())) do
			passed[i] = memory:passOn(name)
		end
		return passed
	end

	before_each(function()
		now = 1000
		memory = Memory.new({}, clock)
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
	end)

	it("keeps the GUID it sees a character with, and passes it on", function()
		memory:see("Hugh Jass", OLD)
		assert.same({ { name = "Hugh Jass", nickname = "Tony", revision = 900, guid = OLD } }, passedOn())
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("learns nothing from the GUID of a character it does not know", function()
		memory:see("Anna Conda", OLD)
		assert.is_nil(memory:passOn("Anna Conda"))
	end)

	it("keeps showing a character seen again with the same GUID", function()
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", OLD)
		assert.equal("Tony", memory:recall("Hugh Jass").nickname)
	end)

	it("hides a stale identity everywhere: its full name shows up with another GUID", function()
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", NEW)
		assert.is_nil(memory:recall("Hugh Jass"))
		assert.same({}, memory:search("Tony"))
		assert.equal(0, memory:count())
	end)

	it("still holds a stale removal as withdrawn", function()
		memory:hear("Hugh Jass", { revision = 950 })
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", NEW)
		assert.is_true(memory:isWithdrawn("Hugh Jass"))
	end)

	it("does not count a stale identity as known, so it asks the new character", function()
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", NEW)
		assert.is_false(memory:knows("Hugh Jass"))
	end)

	it("never passes on a stale identity, but keeps it in its digest so peers holding it still match", function()
		local other = Memory.new({}, clock)
		other:hear("Hugh Jass", { nickname = "Tony", revision = 900, source = "Barb Dwyer" })
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", NEW)
		assert.equal(other:digest(), memory:digest())
		assert.same({}, passedOn())
	end)

	it("lets the new character's first-hand message replace a stale identity, whatever its revision", function()
		memory:see("Hugh Jass", OLD)
		memory:see("Hugh Jass", NEW)
		now = 2000
		assert.is_true(memory:hear("Hugh Jass", { nickname = "Bob", revision = 800 }))
		assert.same({ nickname = "Bob", revision = 800, firstHand = true, heard = 2000 }, memory:recall("Hugh Jass"))
		memory:see("Hugh Jass", NEW)
		assert.equal("Bob", memory:recall("Hugh Jass").nickname)
		assert.equal(NEW, passedOn()[1].guid)
	end)

	it("never lets a second-hand copy replace a stale identity", function()
		hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900)
		memory:see("Anna Conda", OLD)
		memory:see("Anna Conda", NEW)
		assert.is_false(hearFrom("Cole Slaw", "Anna Conda", "Ann", 1900, NEW))
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("keeps the GUID while the character repeats its registration first-hand", function()
		memory:see("Hugh Jass", OLD)
		memory:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
		memory:see("Hugh Jass", NEW)
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("keeps the GUID through a new registration, so a name taken since goes stale when seen", function()
		memory:see("Hugh Jass", OLD)
		memory:hear("Hugh Jass", { nickname = "Bob", revision = 1900 })
		memory:see("Hugh Jass", NEW)
		assert.is_nil(memory:recall("Hugh Jass"))
	end)

	it("keeps the GUID it holds when a peer passes on a later revision, so a forged GUID cannot stop a hide", function()
		hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900)
		memory:see("Anna Conda", OLD)
		hearFrom("Cole Slaw", "Anna Conda", "Annie", 1900)
		hearFrom("Mallory Knox", "Anna Conda", "Annie", 1901, NEW)
		memory:see("Anna Conda", NEW)
		assert.is_nil(memory:recall("Anna Conda"))
	end)

	it("learns the GUID passed on with a second-hand identity, and passes it on", function()
		hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900, OLD)
		assert.equal(OLD, memory:passOn("Anna Conda").guid)
	end)

	it("lets a GUID passed on only hide an identity, never change it", function()
		hearFrom("Mallory Knox", "Anna Conda", "Ann", 900, NEW)
		memory:see("Anna Conda", OLD)
		assert.is_nil(memory:recall("Anna Conda"))
		memory:see("Hugh Jass", OLD)
		assert.is_false(hearFrom("Mallory Knox", "Hugh Jass", "Tony", 900, NEW))
		hearFrom("Barb Dwyer", "Cole Slaw", "Cole", 900, OLD)
		assert.is_false(hearFrom("Mallory Knox", "Cole Slaw", "Cole", 900, NEW))
		memory:see("Cole Slaw", OLD)
		assert.equal("Cole", memory:recall("Cole Slaw").nickname)
	end)

	it("shows again an identity a forged GUID hid once the character speaks first-hand", function()
		hearFrom("Mallory Knox", "Anna Conda", "Ann", 900, NEW)
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		memory:see("Anna Conda", OLD)
		assert.is_false(memory:knows("Anna Conda")) -- so it is asked
		memory:hear("Anna Conda", { nickname = "Ann", revision = 900 })
		memory:see("Anna Conda", OLD)
		assert.equal("Ann", memory:recall("Anna Conda").nickname)
	end)

	it("drops a stale second-hand identity in its turn, the oldest heard first", function()
		hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900)
		memory:see("Anna Conda", OLD)
		memory:see("Anna Conda", NEW)
		for i = 2, Memory.MAX_SECOND_HAND do
			now = now + 1
			hearFrom("Peer" .. math.ceil(i / Memory.MAX_CHANGES_PER_PEER), "Cole Slaw" .. i, "Cole", 900)
		end
		now = now + 1
		assert.is_true(hearFrom("Barb Dwyer", "Ella Vator", "Ella", 900))
		assert.equal("Cole", memory:recall("Cole Slaw2").nickname)
		assert.equal("Ella", memory:recall("Ella Vator").nickname)
		-- Gone, no longer stale: a second-hand copy is taken again.
		assert.is_true(hearFrom("Barb Dwyer", "Anna Conda", "Ann", 900))
	end)

	it("keeps its digest the same as one hashed anew while identities go stale", function()
		local saved = {}
		memory = Memory.new(saved, clock)
		math.randomseed(7)
		for _ = 1, 2000 do
			now = now + 1
			local name = "Hugh Jass" .. math.random(50)
			local roll = math.random(3)
			if roll == 1 then
				memory:see(name, "Player-1-" .. math.random(2))
			elseif roll == 2 then
				memory:hear(name, { nickname = "Tony", revision = 900 + math.random(3) })
			else
				hearFrom(
					"Peer" .. math.random(10),
					name,
					"Antoine",
					900 + math.random(3),
					"Player-1-" .. math.random(2)
				)
			end
		end
		assert.equal(Memory.new(saved, clock):digest(), memory:digest())
	end)
end)

describe("Memory, this account's characters", function()
	local MINE, FORMER = "Player-1-00000001", "Player-1-00000002"
	local now, characters, memory

	local function clock()
		return now
	end

	local function hearFrom(source, name, nickname, revision, guid)
		return memory:hear(name, { nickname = nickname, revision = revision, source = source, guid = guid })
	end

	before_each(function()
		now = 1000
		characters = Self.new({}, clock, {})
		characters:register("Zed Zulu", "Llyth")
		characters:see("Zed Zulu", MINE)
		memory = Memory.new({}, clock, {}, characters)
	end)

	it("takes later revisions of one of them seen with its GUID, whatever GUID a peer passed on", function()
		hearFrom("Ann Bee", "Zed Zulu", "Llyth", 900, FORMER)
		memory:see("Zed Zulu", MINE) -- it speaks in chat
		assert.is_true(hearFrom("Ann Bee", "Zed Zulu", "Tony", 950))
		assert.same({ nickname = "Tony", guid = MINE }, {
			nickname = memory:passOn("Zed Zulu").nickname,
			guid = memory:passOn("Zed Zulu").guid,
		})
	end)

	it(
		"takes later revisions of one of them again once seen with its GUID, a copy gone stale before included",
		function()
			hearFrom("Ann Bee", "Zed Zulu", "Bob", 800) -- another player's character, before the name was yours
			memory:see("Zed Zulu", FORMER)
			memory:see("Zed Zulu", "Player-1-00000003")
			memory:see("Zed Zulu", MINE)
			assert.is_true(hearFrom("Ann Bee", "Zed Zulu", "Llyth", 950))
			assert.equal("Llyth", memory:recall("Zed Zulu").nickname)
		end
	)
end)
