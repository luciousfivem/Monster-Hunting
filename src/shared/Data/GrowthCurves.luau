--!strict
--[[
	Data/GrowthCurves.luau

	xp(n) = max(0, floor((a*n^3 + b*n^2 + c*n + d) / divisor)) -- see Monster/Growth.

	  fast        : 4n^3 / 5
	  medium_fast : n^3 - 1
	  medium_slow : (6n^3 - 75n^2 + 500n - 700) / 5   (= 6/5 n^3 - 15 n^2 + 100 n - 140)
	  slow        : (5n^3 - 5) / 4

	INVARIANT (enforced by the validator): level 1 costs exactly 0 xp, so a new
	monster starts with xp = 0. medium_slow is negative at level 1 and relies on
	the max(0, ...) clamp; medium_fast and slow carry a small negative `d` so
	their level-1 value is 0 instead of 1.
]]

local Types = require(script.Parent.Parent.Types)

local growthCurves: { Types.GrowthCurve } = {
	{ id = "fast", name = "Fast", a = 4, b = 0, c = 0, d = 0, divisor = 5 },
	{ id = "medium_fast", name = "Medium Fast", a = 1, b = 0, c = 0, d = -1, divisor = 1 },
	{ id = "medium_slow", name = "Medium Slow", a = 6, b = -75, c = 500, d = -700, divisor = 5 },
	{ id = "slow", name = "Slow", a = 5, b = 0, c = 0, d = -5, divisor = 4 },
}

return growthCurves
