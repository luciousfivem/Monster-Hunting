--!strict
--[[
	Utils/Rng.luau

	Deterministic, seedable PRNG in pure Luau (xoshiro128**, seeded via splitmix32).

	WHY not Roblox's `Random`: replays and dispute review need "same seed, same
	sequence, forever". Roblox does not document `Random`'s algorithm as stable
	across engine versions (unverified), so a battle recorded today could replay
	differently after an engine update. Owning the algorithm removes that risk
	and keeps this module free of Roblox APIs, so it is unit-testable anywhere.

	NOT cryptographic. Never use it for anything an attacker benefits from
	predicting beyond what the server already controls (it is server-side only;
	clients never see the seed of a live battle).

	Arithmetic notes
	  * Luau numbers are doubles; integers are exact up to 2^53.
	  * `bit32` operates on uint32. The only operation that can exceed 2^53 is a
	    32x32 multiply, so `imul32` splits one operand into 16-bit halves.
]]

local Types = require(script.Parent.Parent.Types)

local Rng = {}

local TWO_32 = 4294967296

-- (a * b) mod 2^32 for uint32 a, b, exactly (a plain `a * b` can reach 2^64).
local function imul32(a: number, b: number): number
	local high = bit32.rshift(a, 16)
	local low = bit32.band(a, 0xFFFF)
	return (((high * b) % 65536) * 65536 + low * b) % TWO_32
end

-- Returns (nextState, output).
local function splitmix32(state: number): (number, number)
	local a = (state + 0x9E3779B9) % TWO_32
	local t = bit32.bxor(a, bit32.rshift(a, 16))
	t = imul32(t, 0x21F0AAAD)
	t = bit32.bxor(t, bit32.rshift(t, 15))
	t = imul32(t, 0x735A2D97)
	t = bit32.bxor(t, bit32.rshift(t, 15))
	return a, t
end

local function build(seed: number, w0: number, w1: number, w2: number, w3: number): Types.Rng
	local s0, s1, s2, s3 = w0, w1, w2, w3

	local function nextU32(): number
		local result = (bit32.lrotate((s1 * 5) % TWO_32, 7) * 9) % TWO_32
		local t = bit32.lshift(s1, 9)
		s2 = bit32.bxor(s2, s0)
		s3 = bit32.bxor(s3, s1)
		s1 = bit32.bxor(s1, s2)
		s0 = bit32.bxor(s0, s3)
		s2 = bit32.bxor(s2, t)
		s3 = bit32.lrotate(s3, 11)
		return result
	end

	local function nextFloat(): number
		return nextU32() / TWO_32
	end

	-- Inclusive range. Rejection sampling removes modulo bias. A range of exactly
	-- one value consumes no draw (documented so replays stay predictable).
	local function nextInt(min: number, max: number): number
		if min ~= min or max ~= max or math.floor(min) ~= min or math.floor(max) ~= max then
			error("Rng.nextInt: bounds must be integers", 2)
		end
		if min > max then
			error("Rng.nextInt: min must be <= max", 2)
		end
		local range = max - min + 1
		if range > TWO_32 then
			error("Rng.nextInt: range exceeds 2^32", 2)
		end
		if range == 1 then
			return min
		end
		local limit = TWO_32 - (TWO_32 % range)
		local x = nextU32()
		while x >= limit do
			x = nextU32()
		end
		return min + (x % range)
	end

	-- Always consumes exactly one draw so call sites stay aligned in replays.
	local function chance(percent: number): boolean
		return nextFloat() * 100 < percent
	end

	local function getState(): Types.RngState
		return { s0, s1, s2, s3 }
	end

	return {
		seed = seed,
		nextU32 = nextU32,
		nextFloat = nextFloat,
		nextInt = nextInt,
		chance = chance,
		getState = getState,
	}
end

-- Creates a generator from any finite number (floored, wrapped into uint32).
function Rng.new(seed: number): Types.Rng
	local normalized = 0
	if seed == seed and seed ~= math.huge and seed ~= -math.huge then
		normalized = math.floor(seed) % TWO_32
	end

	local words: { number } = {}
	local state = normalized
	for i = 1, 4 do
		local output
		state, output = splitmix32(state)
		words[i] = output
	end
	-- xoshiro's all-zero state is a fixed point. splitmix cannot realistically
	-- emit four zeros, but a degenerate state would silently freeze every roll.
	if words[1] == 0 and words[2] == 0 and words[3] == 0 and words[4] == 0 then
		words[1] = 1
	end
	return build(normalized, words[1], words[2], words[3], words[4])
end

-- Restores a generator from a snapshot taken with `getState()`.
function Rng.fromState(seed: number, state: Types.RngState): Types.Rng
	if #state ~= 4 then
		error("Rng.fromState: state must contain 4 words", 2)
	end
	for i = 1, 4 do
		local word = state[i]
		if type(word) ~= "number" or word ~= word or word < 0 or word >= TWO_32 or math.floor(word) ~= word then
			error("Rng.fromState: state words must be uint32", 2)
		end
	end
	if state[1] == 0 and state[2] == 0 and state[3] == 0 and state[4] == 0 then
		error("Rng.fromState: all-zero state is invalid", 2)
	end
	return build(seed, state[1], state[2], state[3], state[4])
end

-- Weighted pick. Entries with weight <= 0 are never chosen. Returns nil when no
-- entry has positive weight. Consumes exactly one draw.
function Rng.pickWeighted<T>(rng: Types.Rng, entries: { T }, weightOf: (T) -> number): T?
	local total = 0
	for _, entry in entries do
		local weight = weightOf(entry)
		if weight > 0 then
			total += weight
		end
	end
	local roll = rng.nextFloat() * total
	if total <= 0 then
		return nil
	end
	local cumulative = 0
	local lastPositive: T? = nil
	for _, entry in entries do
		local weight = weightOf(entry)
		if weight > 0 then
			cumulative += weight
			lastPositive = entry
			if roll < cumulative then
				return entry
			end
		end
	end
	return lastPositive -- float rounding fell off the end; clamp to the last valid entry
end

return table.freeze(Rng)
