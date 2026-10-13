--!strict
--[[
	Monster/StatCalculator.luau

	Derives battle stats from species base stats, the monster's own variance
	(IVs), level and nature. Stats are NEVER stored on an OwnedMonster; they are
	recomputed on demand so a rebalance of base stats or the formula applies to
	every existing monster instantly and nothing can desync.

	Formula (no EVs in this game):
	  HP    = floor((2*base + iv) * level / 100) + level + 10
	  other = floor( (floor((2*base + iv) * level / 100) + 5) * natureMultiplier )

	The nature multiplier is applied with integer math (x * 110 // 100), never
	x * 1.1. For +-10% a float happens to agree, but the percentage is a
	constant (Constants.NATURE_PERCENT) that a designer may change, and most
	multipliers are not exactly representable: floor(100 * 1.13) is 112, not 113.
	Integer math is exact for every percentage.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)

local StatCalculator = {}

function StatCalculator.computeStat(
	statId: Types.StatId,
	base: number,
	iv: number,
	level: number,
	nature: Types.Nature?
): number
	local core = ((2 * base + iv) * level) // 100
	if statId == "hp" then
		return core + level + 10
	end

	local value = core + 5
	if nature ~= nil then
		if nature.increased == statId then
			value = (value * (100 + Constants.NATURE_PERCENT)) // 100
		elseif nature.decreased == statId then
			value = (value * (100 - Constants.NATURE_PERCENT)) // 100
		end
	end
	return value
end

function StatCalculator.computeAll(species: Types.Species, monster: Types.OwnedMonster, nature: Types.Nature?): Types.StatBlock
	local base = species.baseStats
	local ivs = monster.ivs
	local level = monster.level
	return {
		hp = StatCalculator.computeStat("hp", base.hp, ivs.hp, level, nature),
		attack = StatCalculator.computeStat("attack", base.attack, ivs.attack, level, nature),
		defense = StatCalculator.computeStat("defense", base.defense, ivs.defense, level, nature),
		spAttack = StatCalculator.computeStat("spAttack", base.spAttack, ivs.spAttack, level, nature),
		spDefense = StatCalculator.computeStat("spDefense", base.spDefense, ivs.spDefense, level, nature),
		speed = StatCalculator.computeStat("speed", base.speed, ivs.speed, level, nature),
	}
end

return table.freeze(StatCalculator)
