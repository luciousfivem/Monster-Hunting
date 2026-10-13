--!strict
--[[
	Data/EncounterTables.luau

	One table per world zone type. `weight` is relative within the slots that are
	eligible at the moment of the roll (matching timeOfDay or timeOfDay = nil).
	The validator guarantees every table has at least one eligible slot for BOTH
	day and night, so a zone can never silently stop spawning at dusk.

	`biomeId` is a free tag; Phase 4 maps it onto world zones.
]]

local Types = require(script.Parent.Parent.Types)

local encounterTables: { Types.EncounterTable } = {
	{
		id = "mossglen_grass",
		biomeId = "mossglen",
		name = "Mossglen Meadow",
		slots = {
			{ speciesId = "sproutle", weight = 30, minLevel = 2, maxLevel = 6 },
			{ speciesId = "zapling", weight = 20, minLevel = 3, maxLevel = 7 },
			{ speciesId = "snuffle", weight = 25, minLevel = 2, maxLevel = 6 },
			{ speciesId = "gustwing", weight = 20, minLevel = 3, maxLevel = 7, timeOfDay = "day" },
			{ speciesId = "embercub", weight = 10, minLevel = 4, maxLevel = 7, timeOfDay = "night" },
		},
	},
	{
		id = "mossglen_pond",
		biomeId = "mossglen",
		name = "Mossglen Pond",
		slots = {
			{ speciesId = "ripplet", weight = 70, minLevel = 2, maxLevel = 6 },
			{ speciesId = "sproutle", weight = 10, minLevel = 3, maxLevel = 5, timeOfDay = "day" },
			{ speciesId = "zapling", weight = 10, minLevel = 4, maxLevel = 6, timeOfDay = "night" },
		},
	},
	{
		id = "mossglen_cave",
		biomeId = "mossglen",
		name = "Mossglen Caverns",
		slots = {
			{ speciesId = "pebblit", weight = 50, minLevel = 3, maxLevel = 8 },
			{ speciesId = "zapling", weight = 20, minLevel = 4, maxLevel = 8 },
			{ speciesId = "snuffle", weight = 20, minLevel = 3, maxLevel = 7 },
			{ speciesId = "gustwing", weight = 10, minLevel = 5, maxLevel = 8, timeOfDay = "night" },
		},
	},
}

return encounterTables
