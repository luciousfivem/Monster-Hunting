--!strict
--[[
	Data/StatusEffects.luau

	Pure data. `behavior` names a hook module the battle engine implements in
	Phase 3 (status_burn, status_poison, ...). `params` tune that behavior so a
	new status with a familiar shape needs no new code. Until Phase 3 supplies a
	BehaviorRegistry, the validator reports these references as unverified.

	major    : one at a time per monster, persists until cured or battle ends (MVP: battle-scoped)
	volatile : battle-only, can coexist with a major status
]]

local Types = require(script.Parent.Parent.Types)

local statusEffects: { Types.StatusEffect } = {
	{
		id = "burn",
		name = "Burn",
		abbreviation = "BRN",
		description = "Takes damage each turn. Physical attacks deal less damage.",
		category = "major",
		behavior = "status_burn",
		params = { residualFraction = 0.0625, attackMultiplier = 0.5 },
	},
	{
		id = "poison",
		name = "Poison",
		abbreviation = "PSN",
		description = "Takes damage at the end of every turn.",
		category = "major",
		behavior = "status_poison",
		params = { residualFraction = 0.125 },
	},
	{
		id = "paralysis",
		name = "Paralysis",
		abbreviation = "PAR",
		description = "Speed is halved and the monster may be unable to move.",
		category = "major",
		behavior = "status_paralysis",
		params = { speedMultiplier = 0.5, skipChancePercent = 25 },
	},
	{
		id = "sleep",
		name = "Sleep",
		abbreviation = "SLP",
		description = "Cannot act for a few turns.",
		category = "major",
		behavior = "status_sleep",
		duration = { min = 1, max = 3 },
	},
	{
		id = "confusion",
		name = "Confusion",
		abbreviation = "CNF",
		description = "May hurt itself instead of acting.",
		category = "volatile",
		behavior = "status_confusion",
		params = { selfHitChancePercent = 33, selfHitPower = 40 },
		duration = { min = 2, max = 4 },
	},
}

return statusEffects
