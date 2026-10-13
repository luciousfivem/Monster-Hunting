--!strict
-- Reference vectors were produced by an INDEPENDENT BigInt implementation of
-- xoshiro128** + splitmix32 (not by this module), so a match means the Luau
-- double-based arithmetic is bit-exact.
return function(t: any, load: (string) -> any)
	local Rng = load("Utils/Rng")

	local function draw(rng: any, count: number): { number }
		local out: { number } = {}
		for _ = 1, count do
			table.insert(out, rng.nextU32())
		end
		return out
	end

	t.test("matches the independent reference for several seeds", function()
		t.eq(draw(Rng.new(0), 6), { 1789933344, 44971166, 2521387044, 3848737593, 1138324114, 749234105 })
		t.eq(draw(Rng.new(1), 6), { 393288148, 2174103013, 3814759091, 2092745082, 1865176206, 2179171167 })
		t.eq(draw(Rng.new(12345), 6), { 1093274547, 203003357, 3741353573, 3803725158, 4178738660, 810247443 })
		t.eq(draw(Rng.new(4294967295), 6), { 4104197751, 1825856343, 1152209388, 2427537429, 3685145430, 609215610 })
		t.eq(draw(Rng.new(2024), 6), { 3175303598, 1589723956, 2895408000, 806842096, 298834046, 2174339303 })
	end)

	t.test("is deterministic for equal seeds and differs across seeds", function()
		t.eq(draw(Rng.new(99), 50), draw(Rng.new(99), 50))
		t.falsy(draw(Rng.new(99), 5)[1] == draw(Rng.new(100), 5)[1])
	end)

	t.test("normalizes odd seeds without throwing", function()
		t.eq(draw(Rng.new(12345.9), 3), draw(Rng.new(12345), 3), "fractional seeds are floored")
		t.eq(draw(Rng.new(-1), 3), draw(Rng.new(4294967295), 3), "negative seeds wrap into uint32")
		t.eq(draw(Rng.new(0 / 0), 3), draw(Rng.new(0), 3), "NaN seed falls back to 0")
		t.eq(draw(Rng.new(math.huge), 3), draw(Rng.new(0), 3), "inf seed falls back to 0")
	end)

	t.test("getState / fromState resume the exact stream", function()
		local rng = Rng.new(12345)
		rng.nextU32()
		rng.nextU32()
		rng.nextU32()
		t.eq(rng.getState(), { 400148391, 2083272115, 3930455591, 831972921 }, "state after 3 draws matches reference")
		local resumed = Rng.fromState(rng.seed, rng.getState())
		t.eq(draw(resumed, 10), draw(rng, 10))
	end)

	t.test("fromState rejects invalid state", function()
		t.throws(function()
			Rng.fromState(1, { 1, 2, 3 })
		end, "4 words")
		t.throws(function()
			Rng.fromState(1, { 0, 0, 0, 0 })
		end, "all-zero")
		t.throws(function()
			Rng.fromState(1, { 1, 2, 3, 4294967296 })
		end, "uint32")
		t.throws(function()
			Rng.fromState(1, { 1, 2, 3, 0.5 })
		end, "uint32")
	end)

	t.test("nextInt matches the reference rejection sampler", function()
		local rng = Rng.new(777)
		local out: { number } = {}
		for _ = 1, 10 do
			table.insert(out, rng.nextInt(1, 6))
		end
		t.eq(out, { 5, 2, 1, 2, 1, 6, 6, 4, 5, 1 })
	end)

	t.test("nextInt rejection sampling matches the reference on a range that rejects ~30% of draws", function()
		local rng = Rng.new(4242)
		local out: { number } = {}
		for _ = 1, 8 do
			table.insert(out, rng.nextInt(0, 2999999999))
		end
		t.eq(out, { 2119076785, 1976512311, 2960511671, 2437650885, 1069591412, 999549863, 2031961056, 2886428914 })
		-- The reference consumed 10 raw draws for these 8 results (2 rejections). If this module
		-- consumed a different number, the streams would now be misaligned.
		local reference = Rng.new(4242)
		for _ = 1, 10 do
			reference.nextU32()
		end
		t.eq(rng.nextU32(), reference.nextU32(), "stream position after 8 rejection-sampled results")
	end)

	t.test("nextInt stays in range, hits both ends, and a single-value range consumes no draw", function()
		local rng = Rng.new(5)
		local seen: { [number]: boolean } = {}
		for _ = 1, 2000 do
			local value = rng.nextInt(-3, 3)
			t.truthy(value >= -3 and value <= 3, "in range")
			t.eq(math.floor(value), value, "integer")
			seen[value] = true
		end
		for value = -3, 3 do
			t.truthy(seen[value], `value {value} was never drawn`)
		end
		local a = Rng.new(8)
		local b = Rng.new(8)
		t.eq(a.nextInt(4, 4), 4)
		t.eq(a.nextU32(), b.nextU32(), "nextInt(4,4) did not advance the stream")
	end)

	t.test("nextInt rejects invalid bounds", function()
		local rng = Rng.new(1)
		t.throws(function()
			rng.nextInt(5, 1)
		end, "min must be <= max")
		t.throws(function()
			rng.nextInt(1.5, 4)
		end, "integers")
		t.throws(function()
			rng.nextInt(0 / 0, 4)
		end, "integers")
		t.throws(function()
			rng.nextInt(0, 4294967296)
		end, "2^32")
	end)

	t.test("nextFloat is in [0,1) and chance() honors 0 and 100", function()
		local rng = Rng.new(31)
		for _ = 1, 1000 do
			local value = rng.nextFloat()
			t.truthy(value >= 0 and value < 1, "float in [0,1)")
		end
		for _ = 1, 200 do
			t.falsy(rng.chance(0), "0% never succeeds")
			t.truthy(rng.chance(100), "100% always succeeds")
		end
		local hits = 0
		for _ = 1, 10000 do
			if rng.chance(30) then
				hits += 1
			end
		end
		t.near(hits / 10000, 0.3, 0.02, "30% chance frequency")
	end)

	t.test("pickWeighted respects weights, skips non-positive weights, and handles empty pools", function()
		local rng = Rng.new(11)
		local entries = { { id = "a", w = 1 }, { id = "b", w = 3 }, { id = "never", w = 0 }, { id = "neg", w = -5 } }
		local counts: { [string]: number } = { a = 0, b = 0, never = 0, neg = 0 }
		for _ = 1, 8000 do
			local picked = Rng.pickWeighted(rng, entries, function(entry: any): number
				return entry.w
			end)
			counts[picked.id] += 1
		end
		t.eq(counts.never, 0)
		t.eq(counts.neg, 0)
		t.near(counts.b / (counts.a + counts.b), 0.75, 0.03, "b is picked ~3x as often as a")
		t.eq(
			Rng.pickWeighted(rng, { { w = 0 } }, function(entry: any): number
				return entry.w
			end),
			nil
		)
		t.eq(
			Rng.pickWeighted(rng, {}, function(entry: any): number
				return 1
			end),
			nil
		)
	end)
end
