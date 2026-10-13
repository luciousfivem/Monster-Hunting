--!strict
--[[
	Data/Abilities.luau

	Pure data. `behavior` names a hook module implemented by the battle engine
	(Phase 3). Several abilities below share one behavior and differ only in
	params: that is the point. `ability_type_power_boost_low_hp` powers three
	different abilities without three code paths.

	Param names ending in TypeId / StatusId / MoveId / ItemId are validated as
	references to existing records.
]]

local Types = require(script.Parent.Parent.Types)

local abilities: { Types.Ability } = {
	{
		id = "thick_hide",
		name = "Thick Hide",
		description = "Takes less damage from super-effective moves.",
		behavior = "ability_resist_super_effective",
		params = { multiplier = 0.75 },
	},
	{
		id = "fierce_aura",
		name = "Fierce Aura",
		description = "Lowers the opponent's Attack when it enters battle.",
		behavior = "ability_switch_in_stat_stage",
		params = { stat = "attack", stages = -1, target = "opponent" },
	},
	{
		id = "sprinter",
		name = "Sprinter",
		description = "Speed rises a little at the end of every turn.",
		behavior = "ability_turn_end_stat_stage",
		params = { stat = "speed", stages = 1, target = "self" },
	},
	{
		id = "ember_heart",
		name = "Ember Heart",
		description = "Flame moves are stronger when HP is low.",
		behavior = "ability_type_power_boost_low_hp",
		params = { elementTypeId = "flame", multiplier = 1.5, hpFractionBelow = 0.33 },
	},
	{
		id = "tide_veil",
		name = "Tide Veil",
		description = "Tide moves are stronger when HP is low.",
		behavior = "ability_type_power_boost_low_hp",
		params = { elementTypeId = "tide", multiplier = 1.5, hpFractionBelow = 0.33 },
	},
	{
		id = "leaf_mantle",
		name = "Leaf Mantle",
		description = "Verdant moves are stronger when HP is low.",
		behavior = "ability_type_power_boost_low_hp",
		params = { elementTypeId = "verdant", multiplier = 1.5, hpFractionBelow = 0.33 },
	},
	{
		id = "shadow_cloak",
		name = "Shadow Cloak",
		description = "Umbra moves are stronger when HP is low.",
		behavior = "ability_type_power_boost_low_hp",
		params = { elementTypeId = "umbra", multiplier = 1.5, hpFractionBelow = 0.33 },
	},
	{
		id = "grounded",
		name = "Grounded",
		description = "Immune to Volt moves.",
		behavior = "ability_type_immunity",
		params = { elementTypeId = "volt" },
	},
	{
		id = "steady_aim",
		name = "Steady Aim",
		description = "Moves are more accurate.",
		behavior = "ability_accuracy_multiplier",
		params = { multiplier = 1.3 },
	},
}

return abilities
