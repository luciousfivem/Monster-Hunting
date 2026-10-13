--!strict
--[[
	Data/DataValidator.luau

	Startup validation of ALL content. Pure Luau (no Roblox APIs) so it runs in
	Studio, on the server, and in offline tests.

	Two layers per record:
	  1. SHAPE   : Utils/Schema checks types, ranges, lengths, unknown fields.
	  2. SEMANTICS: cross-references (does this move exist?), rules that span
	     fields (status moves need effects), and graph rules (evolution chains).
	Semantic checks for a record run only if its shape passed, so they can rely
	on field types and never crash on bad data.

	Everything is collected into one ValidationReport; nothing throws mid-way.
	`assertValid` throws once, with the complete list.

	Severity policy
	  error   : the data would crash, corrupt saves, or break a rule. Server
	            refuses to boot.
	  warning : legal but suspicious (unreachable monster, unassigned art,
	            unverified behavior references). Printed, never fatal.
]]

local Types = require(script.Parent.Parent.Types)
local Constants = require(script.Parent.Parent.Constants)
local Schema = require(script.Parent.Parent.Utils.Schema)
local TableUtil = require(script.Parent.Parent.Utils.Table)
local Growth = require(script.Parent.Parent.Monster.Growth)
local Registry = require(script.Parent.Registry)

local S = Schema

local DataValidator = {}

--------------------------------------------------------------------------------
-- Shapes
--------------------------------------------------------------------------------

local MAX_LEVEL = Constants.MAX_LEVEL
local idCheck = S.identifier()

local function statBlock(min: number, max: number): Types.SchemaCheck
	local shape: { [string]: Types.SchemaCheck } = {}
	for _, statId in Constants.STAT_IDS do
		shape[statId] = S.integer(min, max)
	end
	return S.object(shape)
end

-- Behavior params: camelCase names, primitive values only.
local paramValue = S.custom(function(value: any, path: string, out: { Types.Issue })
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			S.add(out, "error", "not_finite", path, "param must be finite")
		end
	elseif kind == "string" then
		if #value > 32 or string.find(value, "%c") ~= nil then
			S.add(out, "error", "format", path, "string param must be <= 32 chars with no control characters")
		end
	elseif kind ~= "boolean" then
		S.add(out, "error", "type", path, `param must be a number, string or boolean, got {typeof(value)}`)
	end
end)
local paramsCheck = S.map(S.string(1, 32, "^[%a][%w]*$", "camelCase name"), paramValue, 16)

local abilityShape = S.object({
	id = idCheck,
	name = S.string(1, 32),
	description = S.string(1, 200),
	behavior = idCheck,
	params = S.optional(paramsCheck),
})

local statusShape = S.object({
	id = idCheck,
	name = S.string(1, 32),
	abbreviation = S.string(1, 4),
	description = S.string(1, 200),
	category = S.oneOf(Constants.STATUS_CATEGORIES),
	behavior = idCheck,
	params = S.optional(paramsCheck),
	duration = S.optional(S.object({ min = S.integer(1, 20), max = S.integer(1, 20) })),
})

local moveEffectShape = S.object({
	kind = S.oneOf(Constants.MOVE_EFFECT_KINDS),
	chance = S.optional(S.integer(1, 100)),
	target = S.optional(S.oneOf(Constants.MOVE_TARGETS)),
	statusId = S.optional(idCheck),
	stat = S.optional(S.oneOf(Constants.BATTLE_STAT_IDS)),
	stages = S.optional(S.integer(-Constants.MAX_STAT_STAGE, Constants.MAX_STAT_STAGE)),
	fraction = S.optional(S.number(0.01, 1)),
})

local moveShape = S.object({
	id = idCheck,
	name = S.string(1, 32),
	description = S.string(1, 200),
	elementType = idCheck,
	category = S.oneOf(Constants.MOVE_CATEGORIES),
	power = S.optional(S.integer(1, 250)),
	accuracy = S.optional(S.integer(1, 100)),
	pp = S.integer(1, 64),
	priority = S.integer(-7, 7),
	target = S.oneOf(Constants.MOVE_TARGETS),
	critStage = S.optional(S.integer(0, 3)),
	effects = S.optional(S.array(moveEffectShape, 0, 4)),
})

local itemUseShape = S.object({
	kind = S.oneOf(Constants.ITEM_USE_KINDS),
	hp = S.optional(S.integer(1, 9999)),
	fraction = S.optional(S.number(0.01, 1)),
	statusIds = S.optional(S.array(idCheck, 1, 8)),
	cureAll = S.optional(S.boolean()),
	catchMultiplier = S.optional(S.number(1, 255)),
})

local itemShape = S.object({
	id = idCheck,
	name = S.string(1, 32),
	description = S.string(1, 200),
	category = S.oneOf(Constants.ITEM_CATEGORIES),
	buyPrice = S.optional(S.integer(1, 1000000000)),
	sellPrice = S.optional(S.integer(1, 1000000000)),
	stackLimit = S.integer(1, 999),
	tradeable = S.boolean(),
	consumable = S.boolean(),
	use = S.optional(itemUseShape),
	iconAssetId = S.integer(0, Constants.MAX_SAFE_INTEGER),
})

local natureShape = S.object({
	id = idCheck,
	name = S.string(1, 16),
	increased = S.optional(S.oneOf(Constants.STAT_IDS)),
	decreased = S.optional(S.oneOf(Constants.STAT_IDS)),
})

local growthShape = S.object({
	id = idCheck,
	name = S.string(1, 24),
	a = S.integer(-1000000, 1000000),
	b = S.integer(-1000000, 1000000),
	c = S.integer(-1000000, 1000000),
	d = S.integer(-1000000000, 1000000000),
	divisor = S.integer(1, 1000),
})

local elementTypeShape = S.object({ id = idCheck, name = S.string(1, 16) })

local typeChartShape = S.object({
	types = S.array(elementTypeShape, 1, 32),
	matchups = S.map(idCheck, S.map(idCheck, S.number(0, 4), 32), 32),
})

local evolutionShape = S.object({
	toSpeciesId = idCheck,
	trigger = S.oneOf(Constants.EVOLUTION_TRIGGERS),
	minLevel = S.optional(S.integer(2, MAX_LEVEL)),
	itemId = S.optional(idCheck),
	timeOfDay = S.optional(S.oneOf(Constants.TIMES_OF_DAY)),
	knowsMoveId = S.optional(idCheck),
})

local speciesShape = S.object({
	id = idCheck,
	dexNumber = S.integer(1, 9999),
	name = S.string(1, 24),
	description = S.string(1, 400),
	types = S.array(idCheck, 1, 2),
	baseStats = statBlock(1, 255),
	abilityPool = S.array(S.object({ abilityId = idCheck, weight = S.integer(1, 1000) }), 1, 6),
	learnset = S.array(S.object({ level = S.integer(1, MAX_LEVEL), moveId = idCheck }), 1, 64),
	evolutions = S.optional(S.array(evolutionShape, 0, 8)),
	catchRate = S.integer(1, 255),
	growthCurveId = idCheck,
	baseXpYield = S.integer(1, 1000),
	tradeable = S.boolean(),
	assets = S.object({
		modelAssetId = S.integer(0, Constants.MAX_SAFE_INTEGER),
		iconAssetId = S.integer(0, Constants.MAX_SAFE_INTEGER),
	}),
})

local encounterTableShape = S.object({
	id = idCheck,
	biomeId = idCheck,
	name = S.string(1, 32),
	slots = S.array(
		S.object({
			speciesId = idCheck,
			weight = S.integer(1, 10000),
			minLevel = S.integer(1, MAX_LEVEL),
			maxLevel = S.integer(1, MAX_LEVEL),
			timeOfDay = S.optional(S.oneOf(Constants.TIMES_OF_DAY)),
		}),
		1,
		64
	),
})

--------------------------------------------------------------------------------
-- Context
--------------------------------------------------------------------------------

type Context = {
	snap: Types.GameDataSnapshot,
	options: Types.ValidateOptions,
	errors: { Types.Issue },
	warnings: { Types.Issue },
	validSpecies: { [string]: boolean }, -- species whose SHAPE passed
	unverifiedBehaviors: number,
}

local function addError(ctx: Context, code: string, path: string, message: string)
	S.add(ctx.errors, "error", code, path, message)
end

local function addWarning(ctx: Context, code: string, path: string, message: string)
	S.add(ctx.warnings, "warning", code, path, message)
end

local function absorb(ctx: Context, issues: { Types.Issue })
	for _, issue in issues do
		table.insert(ctx.errors, issue)
	end
end

local function requireRef(ctx: Context, map: { [string]: any }, id: string, kind: string, path: string)
	if map[id] == nil then
		addError(ctx, "bad_ref", path, `references unknown {kind} "{id}"`)
	end
end

-- Shape-checks every record of one kind, then runs `semantic` on the survivors.
local function checkRecords(
	ctx: Context,
	list: { any },
	kind: string,
	shape: Types.SchemaCheck,
	semantic: (ctx: Context, record: any, path: string) -> ()
)
	for _, record in list do
		local path = `{kind}.{record.id}`
		local issues = S.check(shape, record, path)
		if #issues > 0 then
			absorb(ctx, issues)
		else
			semantic(ctx, record, path)
			if kind == "species" then
				ctx.validSpecies[record.id] = true
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Behaviors / params (abilities + status effects)
--------------------------------------------------------------------------------

local REFERENCE_SUFFIXES: { { suffix: string, kind: string } } = {
	{ suffix = "typeid", kind = "elementTypes" },
	{ suffix = "statusid", kind = "statusEffects" },
	{ suffix = "moveid", kind = "moves" },
	{ suffix = "itemid", kind = "items" },
}

local function checkParams(ctx: Context, params: { [string]: any }?, path: string)
	if params == nil then
		return
	end
	for _, name in TableUtil.sortedKeys(params) do
		local value = params[name]
		local lowered = string.lower(name)
		for _, rule in REFERENCE_SUFFIXES do
			if string.sub(lowered, -#rule.suffix) == rule.suffix then
				if type(value) ~= "string" then
					addError(ctx, "type", `{path}.params.{name}`, "reference params must be string ids")
				else
					local map = (ctx.snap :: any)[rule.kind] :: { [string]: any }
					requireRef(ctx, map, value, rule.kind, `{path}.params.{name}`)
				end
			end
		end
	end
end

local function checkBehavior(ctx: Context, behavior: string, params: { [string]: any }?, path: string)
	checkParams(ctx, params, path)
	local registry = ctx.options.behaviors
	if registry == nil then
		ctx.unverifiedBehaviors += 1
		return
	end
	local spec = registry[behavior]
	if spec == nil then
		addError(ctx, "unknown_behavior", `{path}.behavior`, `no behavior module "{behavior}" is registered`)
		return
	end
	if spec.paramsCheck ~= nil then
		absorb(ctx, S.check(spec.paramsCheck, params or {}, `{path}.params`))
	end
end

--------------------------------------------------------------------------------
-- Per-kind semantics
--------------------------------------------------------------------------------

local function checkAbility(ctx: Context, ability: Types.Ability, path: string)
	checkBehavior(ctx, ability.behavior, ability.params, path)
end

local function checkStatus(ctx: Context, status: Types.StatusEffect, path: string)
	checkBehavior(ctx, status.behavior, status.params, path)
	local duration = status.duration
	if duration ~= nil and duration.min > duration.max then
		addError(ctx, "range", `{path}.duration`, `min ({duration.min}) is greater than max ({duration.max})`)
	end
	if status.category == "volatile" and duration == nil then
		addWarning(ctx, "volatile_no_duration", path, "volatile status has no duration; it will last the whole battle")
	end
end

local function checkMove(ctx: Context, move: Types.Move, path: string)
	requireRef(ctx, ctx.snap.elementTypes, move.elementType, "element type", `{path}.elementType`)

	if move.category == "status" then
		if move.power ~= nil then
			addError(ctx, "bad_field", `{path}.power`, "status moves must not have power")
		end
		if move.effects == nil or #move.effects == 0 then
			addError(ctx, "no_effect", `{path}.effects`, "status move has no effects and would do nothing")
		end
	else
		if move.power == nil then
			addError(ctx, "missing", `{path}.power`, `{move.category} moves require power`)
		end
		if move.target == "self" then
			addError(ctx, "bad_field", `{path}.target`, "damaging moves cannot target self")
		end
	end

	local effects: { Types.MoveEffect } = move.effects or {}
	for index, effect in effects do
		local effectPath = `{path}.effects[{index}]`
		local kind = effect.kind

		local function forbid(field: string)
			if (effect :: any)[field] ~= nil then
				addError(ctx, "unused_field", `{effectPath}.{field}`, `"{field}" is not used by effect kind "{kind}"`)
			end
		end
		local function need(field: string)
			if (effect :: any)[field] == nil then
				addError(ctx, "missing", `{effectPath}.{field}`, `effect kind "{kind}" requires "{field}"`)
			end
		end

		if kind == "inflictStatus" then
			need("statusId")
			need("target")
			forbid("stat")
			forbid("stages")
			forbid("fraction")
			if effect.statusId ~= nil then
				requireRef(ctx, ctx.snap.statusEffects, effect.statusId, "status effect", `{effectPath}.statusId`)
			end
		elseif kind == "statStage" then
			need("stat")
			need("stages")
			need("target")
			forbid("statusId")
			forbid("fraction")
			if effect.stages == 0 then
				addError(ctx, "range", `{effectPath}.stages`, "stages must not be 0")
			end
		elseif kind == "recoil" or kind == "drain" then
			need("fraction")
			forbid("statusId")
			forbid("stat")
			forbid("stages")
			forbid("target")
			if move.category == "status" then
				addError(ctx, "bad_field", effectPath, `"{kind}" needs damage dealt; status moves deal none`)
			end
		elseif kind == "heal" then
			need("fraction")
			forbid("statusId")
			forbid("stat")
			forbid("stages")
			forbid("target")
		end
	end
end

local function checkItem(ctx: Context, item: Types.Item, path: string)
	local use = item.use

	if item.sellPrice ~= nil and item.buyPrice ~= nil and item.sellPrice > item.buyPrice then
		addError(
			ctx,
			"economy_loop",
			path,
			`sellPrice ({item.sellPrice}) exceeds buyPrice ({item.buyPrice}): buy-and-resell would mint currency`
		)
	end

	if item.category == "key" then
		if item.tradeable then
			addError(ctx, "bad_field", `{path}.tradeable`, "key items must not be tradeable")
		end
		if item.buyPrice ~= nil or item.sellPrice ~= nil then
			addError(ctx, "bad_field", path, "key items must not have shop prices")
		end
	end

	if item.category == "ball" then
		if use == nil or use.kind ~= "ball" then
			addError(ctx, "bad_field", `{path}.use`, 'ball items require use.kind = "ball"')
		end
	elseif item.category == "medicine" then
		if use == nil or use.kind == "ball" then
			addError(ctx, "bad_field", `{path}.use`, "medicine items require a healHp / cureStatus / revive use")
		end
	elseif use ~= nil then
		addError(ctx, "bad_field", `{path}.use`, `{item.category} items must not have a use effect`)
	end

	if use == nil then
		return
	end
	local usePath = `{path}.use`
	local function forbid(field: string)
		if (use :: any)[field] ~= nil then
			addError(ctx, "unused_field", `{usePath}.{field}`, `"{field}" is not used by use kind "{use.kind}"`)
		end
	end

	if use.kind == "healHp" then
		if (use.hp == nil) == (use.fraction == nil) then
			addError(ctx, "bad_field", usePath, "healHp requires exactly one of hp / fraction")
		end
		forbid("statusIds")
		forbid("cureAll")
		forbid("catchMultiplier")
	elseif use.kind == "revive" then
		if use.fraction == nil then
			addError(ctx, "missing", `{usePath}.fraction`, "revive requires fraction")
		end
		forbid("hp")
		forbid("statusIds")
		forbid("cureAll")
		forbid("catchMultiplier")
	elseif use.kind == "cureStatus" then
		local hasList = use.statusIds ~= nil
		local hasAll = use.cureAll == true
		if hasList == hasAll then
			addError(ctx, "bad_field", usePath, "cureStatus requires exactly one of statusIds / cureAll = true")
		end
		local statusIds: { string } = use.statusIds or {}
		for index, statusId in statusIds do
			requireRef(ctx, ctx.snap.statusEffects, statusId, "status effect", `{usePath}.statusIds[{index}]`)
		end
		forbid("hp")
		forbid("fraction")
		forbid("catchMultiplier")
	elseif use.kind == "ball" then
		if use.catchMultiplier == nil then
			addError(ctx, "missing", `{usePath}.catchMultiplier`, "ball requires catchMultiplier")
		end
		forbid("hp")
		forbid("fraction")
		forbid("statusIds")
		forbid("cureAll")
	end
end

local function checkNature(ctx: Context, nature: Types.Nature, path: string)
	if (nature.increased == nil) ~= (nature.decreased == nil) then
		addError(ctx, "bad_field", path, "increased and decreased must both be set or both be nil")
	elseif nature.increased ~= nil and nature.increased == nature.decreased then
		addError(ctx, "bad_field", path, "a nature cannot raise and lower the same stat")
	end
	if nature.increased == "hp" or nature.decreased == "hp" then
		addError(ctx, "bad_field", path, "natures must not modify hp")
	end
end

local function checkGrowthCurve(ctx: Context, curve: Types.GrowthCurve, path: string)
	local previous = Growth.xpForLevel(curve, 1)
	if previous ~= 0 then
		addError(ctx, "xp_level1", path, `level 1 must need 0 xp, got {previous}`)
	end
	for level = 2, MAX_LEVEL do
		local xp = Growth.xpForLevel(curve, level)
		if xp <= previous then
			addError(
				ctx,
				"xp_not_increasing",
				path,
				`xp for level {level} ({xp}) is not greater than level {level - 1} ({previous}); level lookup would be wrong`
			)
			return
		end
		previous = xp
	end
	if previous > Constants.MAX_XP then
		addError(ctx, "xp_overflow", path, `xp at max level ({previous}) exceeds the int32 cap {Constants.MAX_XP}`)
	end
end

local function checkTypeChart(ctx: Context, chart: Types.TypeChart, path: string)
	for _, attackerId in TableUtil.sortedKeys(chart.matchups) do
		requireRef(ctx, ctx.snap.elementTypes, attackerId, "element type", `{path}.matchups.{attackerId}`)
		local row = chart.matchups[attackerId]
		for _, defenderId in TableUtil.sortedKeys(row) do
			requireRef(ctx, ctx.snap.elementTypes, defenderId, "element type", `{path}.matchups.{attackerId}.{defenderId}`)
			local multiplier = row[defenderId]
			if multiplier ~= 0 and multiplier ~= 0.5 and multiplier ~= 1 and multiplier ~= 2 then
				addWarning(
					ctx,
					"odd_multiplier",
					`{path}.matchups.{attackerId}.{defenderId}`,
					`multiplier {multiplier} is not one of 0, 0.5, 1, 2`
				)
			end
		end
	end
end

local function checkSpecies(ctx: Context, species: Types.Species, path: string)
	local snap = ctx.snap

	-- Types
	if #species.types == 2 and species.types[1] == species.types[2] then
		addError(ctx, "duplicate", `{path}.types`, "a species cannot list the same type twice")
	end
	for index, typeId in species.types do
		requireRef(ctx, snap.elementTypes, typeId, "element type", `{path}.types[{index}]`)
	end

	-- Base stat total sanity
	local total = 0
	for _, statId in Constants.STAT_IDS do
		total += (species.baseStats :: any)[statId]
	end
	if total < 150 or total > 720 then
		addWarning(ctx, "stat_total", `{path}.baseStats`, `base stat total {total} is outside the usual 150-720 range`)
	end

	-- Abilities
	local seenAbilities: { [string]: boolean } = {}
	for index, slot in species.abilityPool do
		local slotPath = `{path}.abilityPool[{index}]`
		requireRef(ctx, snap.abilities, slot.abilityId, "ability", `{slotPath}.abilityId`)
		if seenAbilities[slot.abilityId] then
			addError(ctx, "duplicate", slotPath, `ability "{slot.abilityId}" listed twice`)
		end
		seenAbilities[slot.abilityId] = true
	end

	-- Growth
	requireRef(ctx, snap.growthCurves, species.growthCurveId, "growth curve", `{path}.growthCurveId`)

	-- Learnset
	local seenMoves: { [string]: boolean } = {}
	local previousLevel = 0
	local hasLevelOne = false
	local hasDamagingStarter = false
	for index, entry in species.learnset do
		local entryPath = `{path}.learnset[{index}]`
		if entry.level < previousLevel then
			addError(ctx, "learnset_order", entryPath, `level {entry.level} comes after level {previousLevel}; learnset must be ascending`)
		end
		previousLevel = entry.level
		if seenMoves[entry.moveId] then
			addError(ctx, "duplicate", entryPath, `move "{entry.moveId}" appears twice in the learnset`)
		end
		seenMoves[entry.moveId] = true

		local move = snap.moves[entry.moveId]
		if move == nil then
			addError(ctx, "bad_ref", `{entryPath}.moveId`, `references unknown move "{entry.moveId}"`)
		elseif entry.level == 1 then
			hasLevelOne = true
			if move.category ~= "status" then
				hasDamagingStarter = true
			end
		end
	end
	if not hasLevelOne then
		addError(ctx, "no_starter_move", `{path}.learnset`, "learnset needs at least one valid level-1 move or new monsters would have no moves")
	elseif not hasDamagingStarter then
		addWarning(ctx, "no_damaging_starter", `{path}.learnset`, "no damaging move at level 1; fresh monsters cannot fight")
	end

	-- Evolutions (references only; graph rules run later)
	local targets: { [string]: boolean } = {}
	local evolutions: { Types.EvolutionRule } = species.evolutions or {}
	for index, rule in evolutions do
		local rulePath = `{path}.evolutions[{index}]`
		requireRef(ctx, snap.species, rule.toSpeciesId, "species", `{rulePath}.toSpeciesId`)
		if rule.toSpeciesId == species.id then
			addError(ctx, "evolution_self", rulePath, "a species cannot evolve into itself")
		end
		if targets[rule.toSpeciesId] then
			addWarning(ctx, "duplicate", rulePath, `more than one rule evolves into "{rule.toSpeciesId}"`)
		end
		targets[rule.toSpeciesId] = true

		if rule.itemId ~= nil then
			requireRef(ctx, snap.items, rule.itemId, "item", `{rulePath}.itemId`)
		end
		if rule.knowsMoveId ~= nil then
			requireRef(ctx, snap.moves, rule.knowsMoveId, "move", `{rulePath}.knowsMoveId`)
		end

		if rule.trigger == "level" then
			if rule.minLevel == nil then
				addError(ctx, "missing", `{rulePath}.minLevel`, 'trigger "level" requires minLevel')
			end
			if rule.itemId ~= nil then
				addError(ctx, "unused_field", `{rulePath}.itemId`, 'trigger "level" does not use itemId')
			end
		elseif rule.trigger == "item" then
			if rule.itemId == nil then
				addError(ctx, "missing", `{rulePath}.itemId`, 'trigger "item" requires itemId')
			end
		elseif rule.trigger == "condition" then
			if rule.timeOfDay == nil and rule.knowsMoveId == nil then
				addError(ctx, "missing", rulePath, 'trigger "condition" requires timeOfDay and/or knowsMoveId')
			end
		end
	end
end

local function checkEncounterTable(ctx: Context, tbl: Types.EncounterTable, path: string)
	local hasSlotFor: { [string]: boolean } = {}
	for index, slot in tbl.slots do
		local slotPath = `{path}.slots[{index}]`
		requireRef(ctx, ctx.snap.species, slot.speciesId, "species", `{slotPath}.speciesId`)
		if slot.minLevel > slot.maxLevel then
			addError(ctx, "range", slotPath, `minLevel ({slot.minLevel}) is greater than maxLevel ({slot.maxLevel})`)
		end
		for _, timeOfDay in Constants.TIMES_OF_DAY do
			if slot.timeOfDay == nil or slot.timeOfDay == timeOfDay then
				hasSlotFor[timeOfDay] = true
			end
		end
	end
	for _, timeOfDay in Constants.TIMES_OF_DAY do
		if not hasSlotFor[timeOfDay] then
			addError(ctx, "no_spawns", path, `no slot is eligible at "{timeOfDay}"; this zone would stop spawning`)
		end
	end
end

--------------------------------------------------------------------------------
-- Cross-record / graph rules
--------------------------------------------------------------------------------

local function checkEvolutionGraph(ctx: Context)
	local snap = ctx.snap

	-- Cycles. Colors: nil = unvisited, 1 = on the current path, 2 = finished.
	local color: { [string]: number } = {}
	local hasCycle = false
	local function visit(id: string, trail: { string })
		color[id] = 1
		table.insert(trail, id)
		local species = snap.species[id]
		local evolutions: { Types.EvolutionRule } = species.evolutions or {}
		for _, rule in evolutions do
			local target = rule.toSpeciesId
			if ctx.validSpecies[target] then
				if color[target] == 1 then
					hasCycle = true
					addError(
						ctx,
						"evolution_cycle",
						`species.{id}.evolutions`,
						`evolution cycle: {table.concat(trail, " -> ")} -> {target}`
					)
				elseif color[target] == nil then
					visit(target, trail)
				end
			end
		end
		table.remove(trail)
		color[id] = 2
	end
	for _, species in snap.speciesList do
		if ctx.validSpecies[species.id] and color[species.id] == nil then
			visit(species.id, {})
		end
	end

	-- A species with several pre-evolutions makes "what does this evolve from?" ambiguous.
	for _, targetId in TableUtil.sortedKeys(snap.evolvesFrom) do
		local sources = snap.evolvesFrom[targetId]
		if #sources > 1 then
			local sorted = table.clone(sources)
			table.sort(sorted)
			addError(
				ctx,
				"multiple_preevolutions",
				`species.{targetId}`,
				`evolved from more than one species ({table.concat(sorted, ", ")})`
			)
		end
	end

	if hasCycle then
		return -- depth/order analysis below assumes a DAG
	end

	-- Chain depth and level ordering.
	local depthCache: { [string]: number } = {}
	local function depthFrom(id: string): number
		local cached = depthCache[id]
		if cached ~= nil then
			return cached
		end
		local best = 1
		local species = snap.species[id]
		local evolutions: { Types.EvolutionRule } = species.evolutions or {}
		for _, rule in evolutions do
			if ctx.validSpecies[rule.toSpeciesId] then
				best = math.max(best, 1 + depthFrom(rule.toSpeciesId))
			end
		end
		depthCache[id] = best
		return best
	end
	for _, species in snap.speciesList do
		if ctx.validSpecies[species.id] and snap.evolvesFrom[species.id] == nil then
			local depth = depthFrom(species.id)
			if depth > 3 then
				addWarning(ctx, "long_chain", `species.{species.id}`, `evolution chain is {depth} stages long`)
			end
		end
		local evolutions: { Types.EvolutionRule } = species.evolutions or {}
		for _, rule in evolutions do
			local target = snap.species[rule.toSpeciesId]
			if ctx.validSpecies[species.id] and target ~= nil and rule.trigger == "level" and rule.minLevel ~= nil then
				local followingRules: { Types.EvolutionRule } = target.evolutions or {}
				for _, following in followingRules do
					if following.trigger == "level" and following.minLevel ~= nil and following.minLevel <= rule.minLevel then
						addWarning(
							ctx,
							"evolution_level_order",
							`species.{target.id}`,
							`evolves at level {following.minLevel}, not after its pre-evolution's level {rule.minLevel}`
						)
					end
				end
			end
		end
	end
end

local function listPreview(ids: { string }): string
	local shown: { string } = {}
	for index = 1, math.min(#ids, 6) do
		shown[index] = ids[index]
	end
	local text = table.concat(shown, ", ")
	if #ids > #shown then
		text ..= `, ... (+{#ids - #shown} more)`
	end
	return text
end

local function checkCrossRecordRules(ctx: Context)
	local snap = ctx.snap

	-- Species reachable from encounters, following evolutions.
	local reachable: { [string]: boolean } = {}
	local queue: { string } = {}
	for _, tbl in snap.encounterTableList do
		if TableUtil.isArray(tbl.slots) then
			for _, slot in tbl.slots do
				if type(slot) == "table" and type(slot.speciesId) == "string" and snap.species[slot.speciesId] ~= nil then
					if not reachable[slot.speciesId] then
						reachable[slot.speciesId] = true
						table.insert(queue, slot.speciesId)
					end
				end
			end
		end
	end
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		local species = snap.species[id]
		if ctx.validSpecies[id] then
			local evolutions: { Types.EvolutionRule } = species.evolutions or {}
			for _, rule in evolutions do
				if snap.species[rule.toSpeciesId] ~= nil and not reachable[rule.toSpeciesId] then
					reachable[rule.toSpeciesId] = true
					table.insert(queue, rule.toSpeciesId)
				end
			end
		end
	end
	local unreachable: { string } = {}
	for _, species in snap.speciesList do
		if not reachable[species.id] then
			table.insert(unreachable, species.id)
		end
	end
	if #unreachable > 0 then
		addWarning(
			ctx,
			"unreachable_species",
			"species",
			`{#unreachable} species cannot be obtained from any encounter table or evolution: {listPreview(unreachable)}`
		)
	end

	-- Moves nobody learns.
	local learned: { [string]: boolean } = {}
	for _, species in snap.speciesList do
		if ctx.validSpecies[species.id] then
			for _, entry in species.learnset do
				learned[entry.moveId] = true
			end
		end
	end
	local unused: { string } = {}
	for _, move in snap.moveList do
		if not learned[move.id] then
			table.insert(unused, move.id)
		end
	end
	if #unused > 0 then
		addWarning(ctx, "unused_move", "moves", `{#unused} moves are not in any learnset: {listPreview(unused)}`)
	end

	-- Unassigned art, aggregated so one warning replaces a wall of them.
	local unassigned: { string } = {}
	for _, species in snap.speciesList do
		if ctx.validSpecies[species.id] and (species.assets.modelAssetId == 0 or species.assets.iconAssetId == 0) then
			table.insert(unassigned, species.id)
		end
	end
	if #unassigned > 0 then
		addWarning(
			ctx,
			"assets_unassigned",
			"species",
			`{#unassigned} species have unassigned model/icon asset ids (0): {listPreview(unassigned)}`
		)
	end

	-- Dex number uniqueness (the registry indexes by id, so check numbers here).
	local byDex: { [number]: string } = {}
	for _, species in snap.speciesList do
		if ctx.validSpecies[species.id] then
			local existing = byDex[species.dexNumber]
			if existing ~= nil then
				addError(
					ctx,
					"duplicate_dex",
					`species.{species.id}.dexNumber`,
					`dex number {species.dexNumber} is already used by "{existing}"`
				)
			else
				byDex[species.dexNumber] = species.id
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function DataValidator.validate(raw: any, options: Types.ValidateOptions?): Types.ValidationReport
	local snap, buildIssues = Registry.build(raw)
	local ctx: Context = {
		snap = snap,
		options = options or { behaviors = nil },
		errors = {},
		warnings = {},
		validSpecies = {},
		unverifiedBehaviors = 0,
	}
	for _, issue in buildIssues do
		table.insert(ctx.errors, issue)
	end

	-- Shape-check the chart before anything cross-references it.
	local chartIssues = S.check(typeChartShape, snap.typeChart, "typeChart")
	if #chartIssues > 0 then
		absorb(ctx, chartIssues)
	else
		checkTypeChart(ctx, snap.typeChart, "typeChart")
	end

	checkRecords(ctx, snap.growthCurveList, "growthCurves", growthShape, checkGrowthCurve)
	checkRecords(ctx, snap.natureList, "natures", natureShape, checkNature)
	checkRecords(ctx, snap.statusEffectList, "statusEffects", statusShape, checkStatus)
	checkRecords(ctx, snap.abilityList, "abilities", abilityShape, checkAbility)
	checkRecords(ctx, snap.moveList, "moves", moveShape, checkMove)
	checkRecords(ctx, snap.itemList, "items", itemShape, checkItem)
	checkRecords(ctx, snap.speciesList, "species", speciesShape, checkSpecies)
	checkRecords(ctx, snap.encounterTableList, "encounterTables", encounterTableShape, checkEncounterTable)

	if #snap.speciesList > 0 then
		checkEvolutionGraph(ctx)
		checkCrossRecordRules(ctx)
	end
	if ctx.unverifiedBehaviors > 0 then
		addWarning(
			ctx,
			"behaviors_unverified",
			"abilities/statusEffects",
			`{ctx.unverifiedBehaviors} behavior references were not verified because no BehaviorRegistry was supplied`
		)
	end

	return {
		errors = ctx.errors,
		warnings = ctx.warnings,
		counts = {
			species = #snap.speciesList,
			moves = #snap.moveList,
			abilities = #snap.abilityList,
			items = #snap.itemList,
			statusEffects = #snap.statusEffectList,
			natures = #snap.natureList,
			growthCurves = #snap.growthCurveList,
			encounterTables = #snap.encounterTableList,
			elementTypes = TableUtil.countKeys(snap.elementTypes),
		},
	}
end

local MAX_REPORT_LINES = 200

function DataValidator.formatReport(report: Types.ValidationReport): string
	local lines: { string } = {
		`[DataValidator] {#report.errors} error(s), {#report.warnings} warning(s)`,
	}
	local function append(issues: { Types.Issue }, label: string)
		for _, issue in issues do
			if #lines >= MAX_REPORT_LINES then
				return
			end
			table.insert(lines, `  {label} [{issue.code}] {issue.path}: {issue.message}`)
		end
	end
	append(report.errors, "ERROR  ")
	append(report.warnings, "WARNING")
	local total = #report.errors + #report.warnings
	if total > #lines - 1 then
		table.insert(lines, `  ... {total - (#lines - 1)} more issue(s) not shown`)
	end
	return table.concat(lines, "\n")
end

-- Throws ONE error carrying the complete report when any error exists.
function DataValidator.assertValid(report: Types.ValidationReport)
	if #report.errors > 0 then
		error(DataValidator.formatReport(report), 0)
	end
end

return table.freeze(DataValidator)
