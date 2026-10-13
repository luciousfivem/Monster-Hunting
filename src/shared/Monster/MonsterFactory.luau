--!strict
--[[
	Monster/MonsterFactory.luau

	Creates a new, legal OwnedMonster. Pure: every source of non-determinism or
	environment access is injected, so the same inputs always yield the same
	monster and the module has no Roblox dependencies.

	  deps.rng      : Types.Rng        (server RNG; seeded in tests)
	  deps.newGuid  : () -> string     (production: HttpService:GenerateGUID(false))
	  deps.now      : () -> number     (production: os.time)

	WHY the server must be the only caller: IVs, nature and ability are the
	"rolls" of the game. If any of them could come from the client, players
	would just ask for perfect monsters. Clients never reach this module with
	values; they only send intent ("throw orb"), and the capture code (Phase 4)
	calls this with server-side RNG.

	Failure model: bad `params` are a server-side programming/data error (never
	client input), so create() returns (nil, reason) for the caller to log
	rather than throwing mid-capture.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)
local Rng = require(script.Parent.Parent.Utils.Rng)
local Growth = require(script.Parent.Growth)
local Nickname = require(script.Parent.Nickname)
local MonsterSchema = require(script.Parent.MonsterSchema)

local MonsterFactory = {}

-- Starting moves = the last MAX_MOVES learnset entries at or below `level`.
function MonsterFactory.defaultMoveset(species: Types.Species, level: number): { string }
	local learned: { string } = {}
	for _, entry in species.learnset do
		if entry.level <= level then
			table.insert(learned, entry.moveId)
		end
	end
	local moveset: { string } = {}
	local first = math.max(1, #learned - Constants.MAX_MOVES + 1)
	for index = first, #learned do
		table.insert(moveset, learned[index])
	end
	return moveset
end

function MonsterFactory.create(
	data: Types.GameDataSnapshot,
	params: Types.MonsterCreateParams,
	deps: Types.MonsterFactoryDeps
): (Types.OwnedMonster?, string?)
	local species = data.species[params.speciesId]
	if species == nil then
		return nil, `unknown species "{params.speciesId}"`
	end
	local level = params.level
	if
		type(level) ~= "number"
		or level ~= level
		or math.floor(level) ~= level
		or level < Constants.MIN_LEVEL
		or level > Constants.MAX_LEVEL
	then
		return nil, `level must be an integer in [{Constants.MIN_LEVEL}, {Constants.MAX_LEVEL}]`
	end
	local curve = data.growthCurves[species.growthCurveId]
	if curve == nil then
		return nil, `species "{species.id}" references missing growth curve "{species.growthCurveId}"`
	end
	if params.nickname ~= nil then
		local ok, reason = Nickname.validate(params.nickname)
		if not ok then
			return nil, reason
		end
	end
	local rng = deps.rng

	-- Roll order is fixed (ivs -> nature -> ability) so a seeded test is stable.
	local ivs: Types.StatBlock
	if params.ivs ~= nil then
		ivs = table.clone(params.ivs)
	else
		ivs = {
			hp = rng.nextInt(0, Constants.IV_MAX),
			attack = rng.nextInt(0, Constants.IV_MAX),
			defense = rng.nextInt(0, Constants.IV_MAX),
			spAttack = rng.nextInt(0, Constants.IV_MAX),
			spDefense = rng.nextInt(0, Constants.IV_MAX),
			speed = rng.nextInt(0, Constants.IV_MAX),
		}
	end

	local natureId: string
	if params.natureId ~= nil then
		if data.natures[params.natureId] == nil then
			return nil, `unknown nature "{params.natureId}"`
		end
		natureId = params.natureId
	else
		if #data.natureList == 0 then
			return nil, "no natures are defined"
		end
		natureId = data.natureList[rng.nextInt(1, #data.natureList)].id
	end

	local abilityId: string
	if params.abilityId ~= nil then
		abilityId = params.abilityId
	else
		local slot = Rng.pickWeighted(rng, species.abilityPool, function(candidate: Types.AbilitySlot): number
			return candidate.weight
		end)
		if slot == nil then
			return nil, `species "{species.id}" has an empty ability pool`
		end
		abilityId = slot.abilityId
	end

	local monster: Types.OwnedMonster = {
		guid = deps.newGuid(),
		speciesId = species.id,
		nickname = params.nickname,
		level = level,
		xp = Growth.xpForLevel(curve, level),
		ivs = ivs,
		natureId = natureId,
		moveset = MonsterFactory.defaultMoveset(species, level),
		abilityId = abilityId,
		originalTrainerUserId = params.originalTrainerUserId,
		caughtAt = deps.now(),
		caughtMethod = params.caughtMethod,
		tradeCount = 0,
		currentHp = nil,
		schemaVersion = Constants.MONSTER_SCHEMA_VERSION,
	}

	-- Invariant: the factory never returns an illegal monster. This also covers
	-- scripted overrides (bad ivs / ability / user id) that the checks above do not.
	local issues = MonsterSchema.validate(data, monster, "newMonster")
	if #issues > 0 then
		return nil, `{issues[1].path}: {issues[1].message}`
	end
	return monster, nil
end

return table.freeze(MonsterFactory)
