--!strict
--[[
	Monster/MonsterSchema.luau

	STRICT validation of one OwnedMonster record: "is this a legal monster?"
	It reports; it never repairs. Callers decide what to do with a bad record:
	  * Phase 2 (profile load) repairs what is safely repairable and QUARANTINES
	    the rest (never silently deletes a player's monster).
	  * Phase 6 (trade execution) rejects the trade.
	  * Tests assert factory output always passes.

	Validated in two layers (shape via Utils/Schema, then rules that need game
	data): species/nature/ability/move references, xp <-> level agreement on the
	species' growth curve, and currentHp <= max HP.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)
local Schema = require(script.Parent.Parent.Utils.Schema)
local Growth = require(script.Parent.Growth)
local Nickname = require(script.Parent.Nickname)
local StatCalculator = require(script.Parent.StatCalculator)

local S = Schema

local MonsterSchema = {}

local ivShape: { [string]: Types.SchemaCheck } = {}
for _, statId in Constants.STAT_IDS do
	ivShape[statId] = S.integer(0, Constants.IV_MAX)
end

local nicknameCheck = S.custom(function(value: any, path: string, out: { Types.Issue })
	local ok, reason = Nickname.validate(value)
	if not ok then
		S.add(out, "error", "nickname", path, reason or "invalid nickname")
	end
end)

local shape = S.object({
	-- GUID format is intentionally permissive (alphanumerics and hyphens, 16-64
	-- chars): uniqueness comes from the generator (HttpService:GenerateGUID in
	-- production), not from this pattern.
	guid = S.string(16, 64, "^[%w%-]+$", "alphanumeric/hyphen GUID"),
	speciesId = S.identifier(),
	nickname = S.optional(nicknameCheck),
	level = S.integer(Constants.MIN_LEVEL, Constants.MAX_LEVEL),
	xp = S.integer(0, Constants.MAX_XP),
	ivs = S.object(ivShape),
	natureId = S.identifier(),
	moveset = S.array(S.identifier(), 1, Constants.MAX_MOVES),
	abilityId = S.identifier(),
	originalTrainerUserId = S.integer(Constants.MIN_USER_ID, Constants.MAX_SAFE_INTEGER),
	caughtAt = S.integer(0, 4102444800), -- 2100-01-01 UTC: rejects obviously corrupt timestamps
	caughtMethod = S.oneOf(Constants.CAUGHT_METHODS),
	tradeCount = S.integer(0, 1000000),
	currentHp = S.optional(S.integer(0, 1000000)),
	schemaVersion = S.integer(1, 1000),
})

-- Returns every problem found (empty = valid). Never throws.
function MonsterSchema.validate(data: Types.GameDataSnapshot, monster: any, rootPath: string?): { Types.Issue }
	local path = rootPath or "monster"
	local issues = S.check(shape, monster, path)
	if #issues > 0 then
		return issues -- semantic checks below rely on the shape being sound
	end

	local m = monster :: Types.OwnedMonster

	if m.schemaVersion ~= Constants.MONSTER_SCHEMA_VERSION then
		S.add(issues, "error", "schema_version", `{path}.schemaVersion`, `expected {Constants.MONSTER_SCHEMA_VERSION}, got {m.schemaVersion} (run migrations first)`)
	end

	local species = data.species[m.speciesId]
	if species == nil then
		S.add(issues, "error", "bad_ref", `{path}.speciesId`, `unknown species "{m.speciesId}"`)
		return issues -- nothing else can be checked without the species
	end

	local nature = data.natures[m.natureId]
	if nature == nil then
		S.add(issues, "error", "bad_ref", `{path}.natureId`, `unknown nature "{m.natureId}"`)
	end

	local inPool = false
	for _, slot in species.abilityPool do
		if slot.abilityId == m.abilityId then
			inPool = true
			break
		end
	end
	if not inPool then
		S.add(issues, "error", "illegal_ability", `{path}.abilityId`, `"{m.abilityId}" is not in the ability pool of "{species.id}"`)
	end

	local seenMoves: { [string]: boolean } = {}
	for index, moveId in m.moveset do
		if data.moves[moveId] == nil then
			S.add(issues, "error", "bad_ref", `{path}.moveset[{index}]`, `unknown move "{moveId}"`)
		end
		if seenMoves[moveId] then
			S.add(issues, "error", "duplicate", `{path}.moveset[{index}]`, `move "{moveId}" is listed twice`)
		end
		seenMoves[moveId] = true
	end

	local curve = data.growthCurves[species.growthCurveId]
	if curve ~= nil then
		local floor = Growth.xpForLevel(curve, m.level)
		if m.xp < floor then
			S.add(issues, "error", "xp_level_mismatch", `{path}.xp`, `xp {m.xp} is below the {floor} needed for level {m.level}`)
		elseif m.level < Constants.MAX_LEVEL then
			local ceiling = Growth.xpForLevel(curve, m.level + 1)
			if m.xp >= ceiling then
				S.add(issues, "error", "xp_level_mismatch", `{path}.xp`, `xp {m.xp} reaches level {m.level + 1} ({ceiling}) but level is {m.level}`)
			end
		end
	end

	if m.currentHp ~= nil then
		local maxHp = StatCalculator.computeStat("hp", species.baseStats.hp, m.ivs.hp, m.level, nature)
		if m.currentHp > maxHp then
			S.add(issues, "error", "range", `{path}.currentHp`, `currentHp {m.currentHp} exceeds max HP {maxHp}`)
		end
	end

	return issues
end

return table.freeze(MonsterSchema)
