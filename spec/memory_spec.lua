local ns = require("spec.helpers.addon")("Protocol", "Memory")
local Memory, Protocol = ns.Memory, ns.Protocol

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
		local message = Protocol.read("1:N:901")
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
		hearFrom("Barb Dwyer", "Hugh Jass", "Tony", 900)
		assert.is_true(hearFrom("Mallory Knox", "Hugh Jass", "Mallory", 900))
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
			hearFrom("Barb Dwyer", "Anna Conda", "Ann", revision)
		end
		assert.is_true(memory.queueEnd - memory.queueStart < 2000)
	end)

	it("still drops the identity heard first once its drop queue is compacted", function()
		for revision = 1, 10000 do
			now = 1000 + revision
			hearFrom("Barb Dwyer", "Anna Conda", "Ann", revision)
		end
		fill() -- its last identity drops Anna Conda
		now = now + 1
		assert.is_true(hearFrom("Zed", "Ella Vator", "Ella", 900))
		assert.is_nil(memory:recall("Anna Conda"))
		assert.is_nil(memory:recall("Hugh Jass1"))
		assert.is_not_nil(memory:recall("Hugh Jass2"))
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

	describe("digest", function()
		local other

		before_each(function()
			other = Memory.new({}, clock)
			for _, m in ipairs({ memory, other }) do
				m:hear("Hugh Jass", { nickname = "Tony", revision = 900 })
				m:hear("Anna Conda", { revision = 901, source = "Barb Dwyer" })
			end
		end)

		local function names(identities)
			local list = {}
			for _, identity in ipairs(identities) do
				list[#list + 1] = identity.name
			end
			table.sort(list)
			return list
		end

		it("hashes a memory in a digest a peer can read", function()
			local digest = memory:digest()
			assert.equal(Protocol.DIGEST_LENGTH, #digest)
			local reader = Protocol.newReader(clock)
			local message
			for _, chunk in ipairs(Protocol.split(Protocol.write({ kind = "digest", digest = digest }))) do
				message = reader:read("Barb Dwyer", chunk)
			end
			assert.equal(digest, message.digest)
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
			assert.same({ "Barb Dwyer", "Élise Bérénice" }, names(memory:missing(other:digest())))
			assert.same({}, names(other:missing(memory:digest())))
		end)

		it("passes on what a peer holds at an older revision, without saying how it heard it", function()
			memory:hear("Hugh Jass", { nickname = "Antoine", revision = 1900 })
			local missing = memory:missing(other:digest())
			assert.same({ { name = "Hugh Jass", nickname = "Antoine", revision = 1900 } }, missing)
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
end)
