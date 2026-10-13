--!strict
--[[
	Data/TypeChart.luau

	Element types and the effectiveness matrix.

	matchups[attacker][defender] = damage multiplier. A missing entry means 1.0,
	so only deviations are listed. Allowed values: 0 (immune), 0.5, 2.
	Adding a new element = one entry in `types` + its row/column entries here.
]]

local Types = require(script.Parent.Parent.Types)

local typeChart: Types.TypeChart = {
	types = {
		{ id = "neutral", name = "Neutral" },
		{ id = "flame", name = "Flame" },
		{ id = "tide", name = "Tide" },
		{ id = "verdant", name = "Verdant" },
		{ id = "volt", name = "Volt" },
		{ id = "stone", name = "Stone" },
		{ id = "gale", name = "Gale" },
		{ id = "umbra", name = "Umbra" },
	},

	matchups = {
		neutral = { stone = 0.5, umbra = 0 },
		flame = { verdant = 2, gale = 2, flame = 0.5, tide = 0.5, stone = 0.5 },
		tide = { flame = 2, stone = 2, tide = 0.5, verdant = 0.5 },
		verdant = { tide = 2, stone = 2, flame = 0.5, verdant = 0.5, gale = 0.5 },
		volt = { tide = 2, gale = 2, volt = 0.5, verdant = 0.5, stone = 0 },
		stone = { flame = 2, volt = 2, gale = 2, verdant = 0.5, tide = 0.5 },
		gale = { verdant = 2, umbra = 2, volt = 0.5, stone = 0.5 },
		umbra = { neutral = 2, tide = 2, umbra = 0.5, stone = 0.5 },
	},
}

return typeChart
