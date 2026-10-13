--!strict
--[[
	Monster/Growth.luau

	XP <-> level conversion from data-driven growth curves.

	WHY integer coefficients + a divisor instead of floats like 1.2*n^3:
	1.2 has no exact binary representation, so `floor(1.2 * 1000000)` can land on
	1199999 on one platform and 1200000 on another. Level thresholds must be
	bit-identical everywhere (server, tests, a future web tool), so every
	intermediate here is an exact integer below 2^53 and the single division is
	floored.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)

local Growth = {}

-- Total xp needed to REACH `level` (level 1 always needs 0).
function Growth.xpForLevel(curve: Types.GrowthCurve, level: number): number
	local n = level
	local n2 = n * n
	local n3 = n2 * n
	local numerator = curve.a * n3 + curve.b * n2 + curve.c * n + curve.d
	return math.max(0, math.floor(numerator / curve.divisor))
end

-- Highest level whose threshold is <= xp, in [1, MAX_LEVEL]. Binary search is
-- valid because the validator guarantees each curve is strictly increasing.
function Growth.levelForXp(curve: Types.GrowthCurve, xp: number): number
	local low = Constants.MIN_LEVEL
	local high = Constants.MAX_LEVEL
	while low < high do
		local mid = (low + high + 1) // 2
		if Growth.xpForLevel(curve, mid) <= xp then
			low = mid
		else
			high = mid - 1
		end
	end
	return low
end

return table.freeze(Growth)
