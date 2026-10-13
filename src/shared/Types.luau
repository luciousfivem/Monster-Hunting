--!strict
--[[
	Types.luau

	Every type shared between modules lives here, on purpose:
	  * One place to read the whole data model.
	  * Other modules reference these as `Types.Foo` and never re-declare them,
	    so a schema change is a one-file edit and the analyzer flags every
	    consumer that no longer fits.

	Conventions
	  * Ids are lower_snake_case strings ("fire_pup"). They are the only way
	    records reference each other, so they survive renames of display names.
	  * Optional fields are `T?`. `nil` always means "use the documented default".
	  * Data records are frozen at load time (see Utils/Table.deepFreeze);
	    these types describe their shape, not their mutability.
]]

--------------------------------------------------------------------------------
-- Validation / diagnostics
--------------------------------------------------------------------------------

export type Severity = "error" | "warning"

export type Issue = {
	severity: Severity,
	code: string, -- stable machine-readable tag, e.g. "range", "bad_ref"
	path: string, -- where, e.g. "species.embercub.baseStats.hp"
	message: string,
}

export type ValidationReport = {
	errors: { Issue },
	warnings: { Issue },
	counts: { [string]: number },
}

-- A composable runtime check for untrusted data. Built by Utils/Schema.
export type SchemaCheck = {
	optional: boolean,
	validate: (value: any, path: string, out: { Issue }) -> (),
}

--------------------------------------------------------------------------------
-- Randomness (implemented in Utils/Rng; pure Luau, no Roblox dependencies)
--------------------------------------------------------------------------------

export type RngState = { number } -- four uint32 words

export type Rng = {
	seed: number,
	nextU32: () -> number, -- [0, 2^32)
	nextFloat: () -> number, -- [0, 1)
	nextInt: (min: number, max: number) -> number, -- inclusive, unbiased
	chance: (percent: number) -> boolean, -- consumes exactly one draw
	getState: () -> RngState,
}

--------------------------------------------------------------------------------
-- Stats, elements, natures, growth
--------------------------------------------------------------------------------

export type StatId = "hp" | "attack" | "defense" | "spAttack" | "spDefense" | "speed"

export type StatBlock = {
	hp: number,
	attack: number,
	defense: number,
	spAttack: number,
	spDefense: number,
	speed: number,
}

-- Stats that can be raised/lowered in battle (stages), including hit chance.
export type BattleStatId =
	"attack"
	| "defense"
	| "spAttack"
	| "spDefense"
	| "speed"
	| "accuracy"
	| "evasion"

export type ElementType = {
	id: string,
	name: string,
}

-- matchups[attackerTypeId][defenderTypeId] = multiplier. Missing entry = 1.0.
export type TypeChart = {
	types: { ElementType },
	matchups: { [string]: { [string]: number } },
}

-- increased/decreased are both nil (neutral) or both set and different.
export type Nature = {
	id: string,
	name: string,
	increased: StatId?,
	decreased: StatId?,
}

-- Integer-only polynomial so level thresholds are bit-exact on every machine:
--   xp(n) = max(0, floor((a*n^3 + b*n^2 + c*n + d) / divisor))
export type GrowthCurve = {
	id: string,
	name: string,
	a: number,
	b: number,
	c: number,
	d: number,
	divisor: number,
}

--------------------------------------------------------------------------------
-- Moves, abilities, status effects
--------------------------------------------------------------------------------

export type MoveCategory = "physical" | "special" | "status"
export type MoveTarget = "opponent" | "self"
export type MoveEffectKind = "inflictStatus" | "statStage" | "recoil" | "drain" | "heal"

-- Declarative move side effect, interpreted by the battle engine (Phase 3).
-- Which optional fields apply depends on `kind`; the validator enforces it:
--   inflictStatus : statusId, target            (chance optional)
--   statStage     : stat, stages, target        (chance optional)
--   recoil/drain  : fraction of damage dealt    (damaging moves only)
--   heal          : fraction of user's max HP
export type MoveEffect = {
	kind: MoveEffectKind,
	chance: number?, -- percent 1..100, nil = always
	target: MoveTarget?,
	statusId: string?,
	stat: BattleStatId?,
	stages: number?, -- -6..6, never 0
	fraction: number?, -- (0, 1]
}

export type Move = {
	id: string,
	name: string,
	description: string,
	elementType: string,
	category: MoveCategory,
	power: number?, -- required for physical/special, forbidden for status
	accuracy: number?, -- 1..100, nil = never misses
	pp: number, -- battle-scoped in the MVP (not persisted)
	priority: number, -- -7..7
	target: MoveTarget,
	critStage: number?, -- 0..3, default 0
	effects: { MoveEffect }?,
}

-- Behavior params: values must be number | string | boolean. Typed as `any`
-- because Luau's table invariance rejects a literal like `{ multiplier = 0.75 }`
-- against a union-valued indexer; the DataValidator enforces the real rule at
-- startup. Naming convention it also enforces: a param whose name ends in
-- "TypeId", "StatusId", "MoveId" or "ItemId" must reference an existing record.

-- Abilities and status effects are DATA that name a BEHAVIOR (a hook module
-- implemented by the battle engine in Phase 3). Adding a new ability that
-- reuses an existing behavior needs zero code; a genuinely new behavior is one
-- new module that registers itself, never an edit to the engine core.
export type Ability = {
	id: string,
	name: string,
	description: string,
	behavior: string,
	params: { [string]: any }?,
}

export type StatusCategory = "major" | "volatile" -- major persists until cured; volatile is battle-only

export type StatusEffect = {
	id: string,
	name: string,
	abbreviation: string, -- UI badge, e.g. "BRN"
	description: string,
	category: StatusCategory,
	behavior: string,
	params: { [string]: any }?,
	duration: { min: number, max: number }?, -- turns; nil = until cured
}

-- What a behavior must declare so the validator can check data against it.
export type BehaviorSpec = {
	paramsCheck: SchemaCheck?,
}
export type BehaviorRegistry = { [string]: BehaviorSpec }

--------------------------------------------------------------------------------
-- Items
--------------------------------------------------------------------------------

export type ItemCategory = "ball" | "medicine" | "evolution" | "key"
export type ItemUseKind = "healHp" | "cureStatus" | "revive" | "ball"

export type ItemUse = {
	kind: ItemUseKind,
	hp: number?, -- healHp: flat amount (exactly one of hp / fraction)
	fraction: number?, -- healHp / revive: fraction of max HP
	statusIds: { string }?, -- cureStatus: which statuses (exactly one of statusIds / cureAll)
	cureAll: boolean?,
	catchMultiplier: number?, -- ball: >= 1
}

export type Item = {
	id: string,
	name: string,
	description: string,
	category: ItemCategory,
	buyPrice: number?, -- nil = not sold in shops
	sellPrice: number?, -- nil = cannot be sold; must be <= buyPrice
	stackLimit: number,
	tradeable: boolean,
	consumable: boolean,
	use: ItemUse?,
	iconAssetId: number, -- 0 = unassigned
}

--------------------------------------------------------------------------------
-- Species
--------------------------------------------------------------------------------

export type TimeOfDay = "day" | "night"
export type EvolutionTrigger = "level" | "item" | "trade" | "condition"

-- Required fields per trigger (validator-enforced):
--   level     : minLevel
--   item      : itemId (the consumed evolution item)
--   trade     : nothing (itemId optionally = required held item)
--   condition : at least one of timeOfDay / knowsMoveId
-- timeOfDay, knowsMoveId and minLevel may further restrict any trigger.
export type EvolutionRule = {
	toSpeciesId: string,
	trigger: EvolutionTrigger,
	minLevel: number?,
	itemId: string?,
	timeOfDay: TimeOfDay?,
	knowsMoveId: string?,
}

export type AbilitySlot = {
	abilityId: string,
	weight: number, -- relative roll weight when a monster is generated
}

export type LearnsetEntry = {
	level: number,
	moveId: string,
}

export type SpeciesAssets = {
	modelAssetId: number, -- 0 = unassigned
	iconAssetId: number, -- 0 = unassigned
}

export type Species = {
	id: string,
	dexNumber: number,
	name: string,
	description: string,
	types: { string }, -- 1 or 2 element ids
	baseStats: StatBlock,
	abilityPool: { AbilitySlot },
	learnset: { LearnsetEntry }, -- ascending by level; must contain a level-1 entry
	evolutions: { EvolutionRule }?, -- nil/empty = final form
	catchRate: number, -- 1..255, higher = easier
	growthCurveId: string,
	baseXpYield: number,
	tradeable: boolean,
	assets: SpeciesAssets,
}

--------------------------------------------------------------------------------
-- Encounters
--------------------------------------------------------------------------------

export type EncounterSlot = {
	speciesId: string,
	weight: number,
	minLevel: number,
	maxLevel: number,
	timeOfDay: TimeOfDay?, -- nil = any time
}

export type EncounterTable = {
	id: string,
	biomeId: string, -- free tag; Phase 4 maps it to world zones
	name: string,
	slots: { EncounterSlot },
}

--------------------------------------------------------------------------------
-- Owned monsters (persisted)
--------------------------------------------------------------------------------

export type CaughtMethod = "wild" | "starter" | "egg" | "event" | "gift" | "admin"

-- Stored in the player's profile. Derived values (max HP, stats) are NEVER
-- stored: they are recomputed from species + level + ivs + nature so they can
-- never desync from the rules.
--
-- xp is the source of truth for progression; `level` is a cached copy that the
-- validator requires to agree with xp on the species' growth curve.
export type OwnedMonster = {
	guid: string,
	speciesId: string,
	nickname: string?, -- nil = show species name
	level: number,
	xp: number, -- total xp
	ivs: StatBlock, -- per-monster variance, each 0..31
	natureId: string,
	moveset: { string }, -- 1..4 distinct move ids
	abilityId: string, -- must be in the species' ability pool
	originalTrainerUserId: number,
	caughtAt: number, -- unix seconds
	caughtMethod: CaughtMethod,
	tradeCount: number,
	currentHp: number?, -- nil = full health (ADDITION to the original spec; see docs)
	schemaVersion: number,
}

export type MonsterCreateParams = {
	speciesId: string,
	level: number,
	originalTrainerUserId: number,
	caughtMethod: CaughtMethod,
	nickname: string?,
	-- Overrides for scripted monsters (event gifts, tests). Omit for a normal roll.
	ivs: StatBlock?,
	natureId: string?,
	abilityId: string?,
}

-- Everything MonsterFactory needs from its environment, injected so the factory
-- stays pure: production passes server RNG, HttpService:GenerateGUID and os.time.
export type MonsterFactoryDeps = {
	rng: Rng,
	newGuid: () -> string,
	now: () -> number,
}

--------------------------------------------------------------------------------
-- Game data container
--------------------------------------------------------------------------------

-- What the content modules (Data/*.luau) hand to the registry.
export type RawGameData = {
	species: { Species },
	moves: { Move },
	abilities: { Ability },
	items: { Item },
	statusEffects: { StatusEffect },
	natures: { Nature },
	growthCurves: { GrowthCurve },
	encounterTables: { EncounterTable },
	typeChart: TypeChart,
}

-- Indexed, read-only view built by Data/Registry from RawGameData.
export type GameDataSnapshot = {
	species: { [string]: Species },
	speciesList: { Species }, -- ascending dexNumber
	moves: { [string]: Move },
	moveList: { Move },
	abilities: { [string]: Ability },
	abilityList: { Ability },
	items: { [string]: Item },
	itemList: { Item },
	statusEffects: { [string]: StatusEffect },
	statusEffectList: { StatusEffect },
	natures: { [string]: Nature },
	natureList: { Nature },
	growthCurves: { [string]: GrowthCurve },
	growthCurveList: { GrowthCurve },
	encounterTables: { [string]: EncounterTable },
	encounterTableList: { EncounterTable },
	elementTypes: { [string]: ElementType },
	typeChart: TypeChart,
	evolvesFrom: { [string]: { string } }, -- speciesId -> species that evolve into it
}

-- What `require(Shared.Data)` returns.
export type GameData = GameDataSnapshot & {
	raw: RawGameData,
	buildIssues: { Issue }, -- duplicate/missing ids found while indexing
}

export type ValidateOptions = {
	-- When nil, behavior references cannot be verified; the validator reports a
	-- single warning instead of silently passing. Phase 3 supplies the registry.
	behaviors: BehaviorRegistry?,
}

return {}
