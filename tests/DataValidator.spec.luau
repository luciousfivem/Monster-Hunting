--!strict
-- Every rule in Data/DataValidator is proven twice: shipped data passes, and a
-- deliberately corrupted copy produces the expected issue code at the expected
-- path. Mutations run on deep copies; the frozen shipped data is never touched.
return function(t: any, load: (string) -> any)
	local DataValidator = load("Data/DataValidator")
	local GameData = load("Data")
	local TableUtil = load("Utils/Table")
	local Schema = load("Utils/Schema")

	local function validateMutated(mutate: (raw: any) -> ()): any
		local raw = TableUtil.deepCopy(GameData.raw)
		mutate(raw)
		return DataValidator.validate(raw)
	end

	local function find(list: { any }, id: string): any
		for _, record in list do
			if record.id == id then
				return record
			end
		end
		error(`test setup: no record "{id}"`)
	end

	local function hasWarning(report: any, code: string): boolean
		for _, warning in report.warnings do
			if warning.code == code then
				return true
			end
		end
		return false
	end

	--------------------------------------------------------------------------
	-- Baseline
	--------------------------------------------------------------------------

	t.test("shipped data has zero errors", function()
		local report = DataValidator.validate(GameData.raw)
		t.noIssues(report.errors)
		t.noIssues(GameData.buildIssues)
	end)

	t.test("shipped data matches the MVP target", function()
		local report = DataValidator.validate(GameData.raw)
		t.eq(report.counts.species, 15, "15 monsters")
		t.eq(report.counts.encounterTables, 3, "one biome, three zone tables")
		t.truthy(report.counts.moves >= 20)
		t.eq(report.counts.natures, 25)
	end)

	t.test("shipped data only warns about known, intentional things", function()
		local report = DataValidator.validate(GameData.raw)
		local codes: { [string]: boolean } = {}
		for _, warning in report.warnings do
			codes[warning.code] = true
		end
		-- Art is not assigned and Phase 3 has not registered behaviors yet.
		t.truthy(codes.assets_unassigned)
		t.truthy(codes.behaviors_unverified)
		-- Anything else would be a content regression.
		for code in codes do
			t.truthy(code == "assets_unassigned" or code == "behaviors_unverified", `unexpected warning code "{code}"`)
		end
	end)

	t.test("game data is deeply frozen", function()
		t.truthy(table.isfrozen(GameData))
		t.truthy(table.isfrozen(GameData.species.embercub))
		t.truthy(table.isfrozen(GameData.species.embercub.baseStats))
		t.truthy(table.isfrozen(GameData.speciesList))
		t.throws(function()
			GameData.species.embercub.catchRate = 1
		end)
		t.throws(function()
			GameData.species.embercub.baseStats.hp = 9999
		end)
		t.throws(function()
			GameData.moves.bump.power = 9999
		end)
	end)

	t.test("registry indexes lists by id, sorted by dex number", function()
		t.eq(GameData.species.embercub.dexNumber, 1)
		t.eq(#GameData.speciesList, 15)
		for index, species in GameData.speciesList do
			t.eq(species.dexNumber, index, "dex numbers are contiguous in the MVP roster")
			t.truthy(GameData.species[species.id] == species)
		end
		t.eq(GameData.evolvesFrom.emberprowl, { "embercub" })
		t.eq(GameData.evolvesFrom.embercub, nil)
	end)

	--------------------------------------------------------------------------
	-- Registry / structure
	--------------------------------------------------------------------------

	t.test("duplicate ids are reported, first definition wins", function()
		local report = validateMutated(function(raw)
			local copy = TableUtil.deepCopy(find(raw.species, "embercub"))
			copy.catchRate = 1
			table.insert(raw.species, copy)
		end)
		t.hasIssue(report.errors, "duplicate_id", "species.embercub")
	end)

	t.test("records without a string id are reported and do not crash", function()
		local report = validateMutated(function(raw)
			table.insert(raw.species, { name = "No Id" })
			table.insert(raw.moves, 5)
			table.insert(raw.items, "item")
		end)
		t.hasIssue(report.errors, "missing_id", "species[")
		t.hasIssue(report.errors, "missing_id", "moves[")
		t.hasIssue(report.errors, "missing_id", "items[")
	end)

	t.test("garbage input never throws", function()
		local garbage: { any } = { {}, 5, "x", { species = 5 }, { species = {}, typeChart = 3 }, { species = { {} }, moves = { {} } } }
		for _, raw in garbage do
			local ok = pcall(DataValidator.validate, raw)
			t.truthy(ok, "validate must not throw on malformed raw data")
		end
		t.hasIssue(DataValidator.validate({}).errors, "not_array", "species")
		t.hasIssue(DataValidator.validate(5).errors, "type", "gameData")
	end)

	t.test("typos and unknown fields are caught", function()
		local report = validateMutated(function(raw)
			local species = find(raw.species, "embercub")
			species.catchrate = species.catchRate -- the classic typo: renamed instead of fixed
			species.catchRate = nil
		end)
		t.hasIssue(report.errors, "unknown_field", "species.embercub.catchrate")
		t.hasIssue(report.errors, "missing", "species.embercub.catchRate")
	end)

	t.test("number problems: range, NaN, infinity, fractions", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").catchRate = 300
			end).errors,
			"range",
			"species.embercub.catchRate"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").baseStats.hp = 0 / 0
			end).errors,
			"not_finite",
			"species.embercub.baseStats.hp"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").baseStats.speed = math.huge
			end).errors,
			"not_finite",
			"baseStats.speed"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").baseStats.attack = 55.5
			end).errors,
			"not_integer",
			"baseStats.attack"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").baseStats.defense = "40"
			end).errors,
			"type",
			"baseStats.defense"
		)
	end)

	t.test("arrays with holes are rejected", function()
		local report = validateMutated(function(raw)
			local species = find(raw.species, "embercub")
			species.learnset = { [1] = species.learnset[1], [3] = species.learnset[2] }
		end)
		t.hasIssue(report.errors, "not_array", "species.embercub.learnset")
	end)

	--------------------------------------------------------------------------
	-- References
	--------------------------------------------------------------------------

	t.test("unknown references are reported with their location", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").learnset[3].moveId = "does_not_exist"
			end).errors,
			"bad_ref",
			"species.embercub.learnset[3].moveId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").abilityPool[1].abilityId = "ghost_ability"
			end).errors,
			"bad_ref",
			"species.embercub.abilityPool[1].abilityId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").growthCurveId = "no_curve"
			end).errors,
			"bad_ref",
			"species.embercub.growthCurveId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").types = { "plasma" }
			end).errors,
			"bad_ref",
			"species.embercub.types[1]"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "bump").elementType = "plasma"
			end).errors,
			"bad_ref",
			"moves.bump.elementType"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.encounterTables, "mossglen_grass").slots[1].speciesId = "nobody"
			end).errors,
			"bad_ref",
			"encounterTables.mossglen_grass.slots[1].speciesId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "antidote").use.statusIds = { "nope" }
			end).errors,
			"bad_ref",
			"items.antidote.use.statusIds[1]"
		)
		t.hasIssue(
			validateMutated(function(raw)
				raw.typeChart.matchups.flame.plasma = 2
			end).errors,
			"bad_ref",
			"typeChart.matchups.flame.plasma"
		)
	end)

	t.test("param names ending in TypeId / StatusId / MoveId / ItemId must reference real records", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.abilities, "ember_heart").params.elementTypeId = "plasma"
			end).errors,
			"bad_ref",
			"abilities.ember_heart.params.elementTypeId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.abilities, "ember_heart").params.elementTypeId = 5
			end).errors,
			"type",
			"abilities.ember_heart.params.elementTypeId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.statusEffects, "burn").params.curesStatusId = "nope"
			end).errors,
			"bad_ref",
			"statusEffects.burn.params.curesStatusId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.abilities, "ember_heart").params.nested = {}
			end).errors,
			"type",
			"abilities.ember_heart.params.nested"
		)
	end)

	--------------------------------------------------------------------------
	-- Species rules
	--------------------------------------------------------------------------

	t.test("learnset rules: ascending, no duplicates, needs a level-1 move", function()
		t.hasIssue(
			validateMutated(function(raw)
				local learnset = find(raw.species, "embercub").learnset
				learnset[3], learnset[4] = learnset[4], learnset[3]
			end).errors,
			"learnset_order",
			"species.embercub.learnset"
		)
		t.hasIssue(
			validateMutated(function(raw)
				local learnset = find(raw.species, "embercub").learnset
				learnset[4].moveId = learnset[3].moveId
			end).errors,
			"duplicate",
			"species.embercub.learnset"
		)
		t.hasIssue(
			validateMutated(function(raw)
				local learnset = find(raw.species, "embercub").learnset
				learnset[1].level = 2
				learnset[2].level = 2
			end).errors,
			"no_starter_move",
			"species.embercub.learnset"
		)
	end)

	t.test("a level-1 set of only status moves warns", function()
		local report = validateMutated(function(raw)
			local learnset = find(raw.species, "embercub").learnset
			learnset[1].moveId = "harden"
		end)
		t.truthy(hasWarning(report, "no_damaging_starter"))
		t.noIssues(report.errors)
	end)

	t.test("types and ability pool: duplicates", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "infernomaw").types = { "flame", "flame" }
			end).errors,
			"duplicate",
			"species.infernomaw.types"
		)
		t.hasIssue(
			validateMutated(function(raw)
				local pool = find(raw.species, "embercub").abilityPool
				pool[2].abilityId = pool[1].abilityId
			end).errors,
			"duplicate",
			"species.embercub.abilityPool"
		)
	end)

	t.test("duplicate dex numbers", function()
		local report = validateMutated(function(raw)
			find(raw.species, "emberprowl").dexNumber = 1
		end)
		t.hasIssue(report.errors, "duplicate_dex", "emberprowl")
	end)

	t.test("absurd base stat totals warn", function()
		local report = validateMutated(function(raw)
			for stat in find(raw.species, "embercub").baseStats do
				find(raw.species, "embercub").baseStats[stat] = 255
			end
		end)
		t.truthy(hasWarning(report, "stat_total"))
	end)

	--------------------------------------------------------------------------
	-- Evolution chains
	--------------------------------------------------------------------------

	t.test("evolution to an unknown species", function()
		local report = validateMutated(function(raw)
			find(raw.species, "embercub").evolutions[1].toSpeciesId = "ghost"
		end)
		t.hasIssue(report.errors, "bad_ref", "species.embercub.evolutions[1].toSpeciesId")
	end)

	t.test("evolving into itself", function()
		local report = validateMutated(function(raw)
			find(raw.species, "embercub").evolutions[1].toSpeciesId = "embercub"
		end)
		t.hasIssue(report.errors, "evolution_self", "species.embercub")
	end)

	t.test("evolution cycles are detected and named", function()
		local report = validateMutated(function(raw)
			find(raw.species, "infernomaw").evolutions = { { toSpeciesId = "embercub", trigger = "level", minLevel = 50 } }
		end)
		t.hasIssue(report.errors, "evolution_cycle")
		local found = false
		for _, issue in report.errors do
			if issue.code == "evolution_cycle" and string.find(issue.message, "embercub -> emberprowl -> infernomaw -> embercub", 1, true) then
				found = true
			end
		end
		t.truthy(found, "the cycle path is spelled out in the message")
	end)

	t.test("a root species that leads INTO a cycle does not crash the depth analysis", function()
		local report = validateMutated(function(raw)
			-- cycle: embercub -> emberprowl -> infernomaw -> embercub, entered from outside by gustwing
			find(raw.species, "infernomaw").evolutions = { { toSpeciesId = "embercub", trigger = "level", minLevel = 50 } }
			find(raw.species, "gustwing").evolutions = { { toSpeciesId = "emberprowl", trigger = "level", minLevel = 20 } }
		end)
		t.hasIssue(report.errors, "evolution_cycle")
	end)

	t.test("two species evolving into the same one is ambiguous", function()
		local report = validateMutated(function(raw)
			find(raw.species, "gustwing").evolutions =
				{ { toSpeciesId = "emberprowl", trigger = "level", minLevel = 20 } }
		end)
		t.hasIssue(report.errors, "multiple_preevolutions", "species.emberprowl")
	end)

	t.test("per-trigger required fields", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").evolutions[1].minLevel = nil
			end).errors,
			"missing",
			"species.embercub.evolutions[1].minLevel"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "zapling").evolutions[1].itemId = nil
			end).errors,
			"missing",
			"species.zapling.evolutions[1].itemId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "gustwing").evolutions[1].timeOfDay = nil
			end).errors,
			"missing",
			"species.gustwing.evolutions[1]"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "zapling").evolutions[1].itemId = "no_such_item"
			end).errors,
			"bad_ref",
			"species.zapling.evolutions[1].itemId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.species, "embercub").evolutions[1].itemId = "volt_shard"
			end).errors,
			"unused_field",
			"species.embercub.evolutions[1].itemId"
		)
	end)

	t.test("a later evolution level that is not after the earlier one warns", function()
		local report = validateMutated(function(raw)
			find(raw.species, "emberprowl").evolutions[1].minLevel = 10
		end)
		t.truthy(hasWarning(report, "evolution_level_order"))
	end)

	t.test("unreachable species are warned about", function()
		local report = validateMutated(function(raw)
			for _, table_ in raw.encounterTables do
				for index = #table_.slots, 1, -1 do
					if table_.slots[index].speciesId == "pebblit" then
						table.remove(table_.slots, index)
					end
				end
			end
			-- keep the cave valid for both times of day
			table.insert(find(raw.encounterTables, "mossglen_cave").slots, { speciesId = "snuffle", weight = 1, minLevel = 3, maxLevel = 4 })
		end)
		t.truthy(hasWarning(report, "unreachable_species"))
		t.noIssues(report.errors)
	end)

	--------------------------------------------------------------------------
	-- Moves
	--------------------------------------------------------------------------

	t.test("move rules: power / effects / target", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "bump").power = nil
			end).errors,
			"missing",
			"moves.bump.power"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "rally").power = 40
			end).errors,
			"bad_field",
			"moves.rally.power"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "rally").effects = nil
			end).errors,
			"no_effect",
			"moves.rally"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "bump").target = "self"
			end).errors,
			"bad_field",
			"moves.bump.target"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "bump").accuracy = 0
			end).errors,
			"range",
			"moves.bump.accuracy"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "quick_strike").priority = 9
			end).errors,
			"range",
			"moves.quick_strike.priority"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "bump").category = "magic"
			end).errors,
			"enum",
			"moves.bump.category"
		)
	end)

	t.test("move effect rules per kind", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "rally").effects[1].stat = nil
			end).errors,
			"missing",
			"moves.rally.effects[1].stat"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "rally").effects[1].stages = 0
			end).errors,
			"range",
			"moves.rally.effects[1].stages"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "rally").effects[1].stages = 7
			end).errors,
			"range",
			"moves.rally.effects[1].stages"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "cinder_bite").effects[1].statusId = "no_status"
			end).errors,
			"bad_ref",
			"moves.cinder_bite.effects[1].statusId"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "cinder_bite").effects[1].chance = 0
			end).errors,
			"range",
			"moves.cinder_bite.effects[1].chance"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "cinder_bite").effects[1].fraction = 0.5
			end).errors,
			"unused_field",
			"moves.cinder_bite.effects[1].fraction"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "reckless_charge").effects[1].fraction = nil
			end).errors,
			"missing",
			"moves.reckless_charge.effects[1].fraction"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "mend").effects[1].target = "self"
			end).errors,
			"unused_field",
			"moves.mend.effects[1].target"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.moves, "mend").effects = { { kind = "recoil", fraction = 0.5 } }
			end).errors,
			"bad_field",
			"moves.mend.effects[1]"
		)
	end)

	--------------------------------------------------------------------------
	-- Items / economy
	--------------------------------------------------------------------------

	t.test("economy: selling for more than the buy price is an error", function()
		local report = validateMutated(function(raw)
			find(raw.items, "tonic_small").sellPrice = 101
		end)
		t.hasIssue(report.errors, "economy_loop", "items.tonic_small")
	end)

	t.test("item category rules", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "world_map").tradeable = true
			end).errors,
			"bad_field",
			"items.world_map.tradeable"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "world_map").buyPrice = 5
			end).errors,
			"bad_field",
			"items.world_map"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "orb_basic").use = nil
			end).errors,
			"bad_field",
			"items.orb_basic.use"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "tonic_small").use = { kind = "ball", catchMultiplier = 2 }
			end).errors,
			"bad_field",
			"items.tonic_small.use"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "volt_shard").use = { kind = "healHp", hp = 5 }
			end).errors,
			"bad_field",
			"items.volt_shard.use"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "tonic_small").use.fraction = 0.5
			end).errors,
			"bad_field",
			"items.tonic_small.use"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "cure_all").use.statusIds = { "poison" }
			end).errors,
			"bad_field",
			"items.cure_all.use"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "orb_basic").use.catchMultiplier = 0.5
			end).errors,
			"range",
			"items.orb_basic.use.catchMultiplier"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.items, "revive_charm").use.fraction = nil
			end).errors,
			"missing",
			"items.revive_charm.use.fraction"
		)
	end)

	--------------------------------------------------------------------------
	-- Encounters
	--------------------------------------------------------------------------

	t.test("encounter tables: eligible slots at every time of day, sane level ranges", function()
		t.hasIssue(
			validateMutated(function(raw)
				local slots = find(raw.encounterTables, "mossglen_pond").slots
				-- leave only a day-only slot: the pond would never spawn at night
				find(raw.encounterTables, "mossglen_pond").slots = { slots[2] }
			end).errors,
			"no_spawns",
			"encounterTables.mossglen_pond"
		)
		t.hasIssue(
			validateMutated(function(raw)
				local slot = find(raw.encounterTables, "mossglen_grass").slots[1]
				slot.minLevel, slot.maxLevel = 9, 3
			end).errors,
			"range",
			"encounterTables.mossglen_grass.slots[1]"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.encounterTables, "mossglen_grass").slots[1].weight = 0
			end).errors,
			"range",
			"encounterTables.mossglen_grass.slots[1].weight"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.encounterTables, "mossglen_grass").slots = {}
			end).errors,
			"length",
			"encounterTables.mossglen_grass.slots"
		)
	end)

	--------------------------------------------------------------------------
	-- Growth curves, natures, status effects, type chart
	--------------------------------------------------------------------------

	t.test("growth curves must be strictly increasing and start at 0", function()
		t.hasIssue(
			validateMutated(function(raw)
				local curve = find(raw.growthCurves, "fast")
				curve.a, curve.b, curve.c, curve.d, curve.divisor = 0, 0, 0, 0, 1
			end).errors,
			"xp_not_increasing",
			"growthCurves.fast"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.growthCurves, "medium_fast").d = 50
			end).errors,
			"xp_level1",
			"growthCurves.medium_fast"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.growthCurves, "slow").a = 999999
			end).errors,
			"xp_overflow",
			"growthCurves.slow"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.growthCurves, "slow").divisor = 0
			end).errors,
			"range",
			"growthCurves.slow.divisor"
		)
	end)

	t.test("nature rules", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.natures, "brash").decreased = nil
			end).errors,
			"bad_field",
			"natures.brash"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.natures, "brash").decreased = "attack"
			end).errors,
			"bad_field",
			"natures.brash"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.natures, "brash").increased = "hp"
			end).errors,
			"bad_field",
			"natures.brash"
		)
	end)

	t.test("status effect rules", function()
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.statusEffects, "sleep").duration = { min = 5, max = 2 }
			end).errors,
			"range",
			"statusEffects.sleep.duration"
		)
		t.hasIssue(
			validateMutated(function(raw)
				find(raw.statusEffects, "burn").category = "permanent"
			end).errors,
			"enum",
			"statusEffects.burn.category"
		)
		t.truthy(hasWarning(
			validateMutated(function(raw)
				find(raw.statusEffects, "confusion").duration = nil
			end),
			"volatile_no_duration"
		))
	end)

	t.test("type chart: odd multipliers warn, bad ones error", function()
		t.truthy(hasWarning(
			validateMutated(function(raw)
				raw.typeChart.matchups.flame.tide = 3
			end),
			"odd_multiplier"
		))
		t.hasIssue(
			validateMutated(function(raw)
				raw.typeChart.matchups.flame.tide = 0 / 0
			end).errors,
			"not_finite",
			"typeChart.matchups.flame.tide"
		)
		t.hasIssue(
			validateMutated(function(raw)
				raw.typeChart.matchups.flame.tide = -1
			end).errors,
			"range",
			"typeChart.matchups.flame.tide"
		)
	end)

	--------------------------------------------------------------------------
	-- Behavior registry (Phase 3 hook-up)
	--------------------------------------------------------------------------

	t.test("with a BehaviorRegistry, behavior references are verified", function()
		local registry: { [string]: any } = {}
		for _, ability in GameData.abilityList do
			registry[ability.behavior] = {}
		end
		for _, status in GameData.statusEffectList do
			registry[status.behavior] = {}
		end
		local complete = DataValidator.validate(GameData.raw, { behaviors = registry })
		t.noIssues(complete.errors)
		t.falsy(hasWarning(complete, "behaviors_unverified"), "nothing is unverified once a registry is supplied")

		registry.status_burn = nil
		local missing = DataValidator.validate(GameData.raw, { behaviors = registry })
		t.hasIssue(missing.errors, "unknown_behavior", "statusEffects.burn.behavior")
	end)

	t.test("a behavior can declare a params schema that data must satisfy", function()
		local registry: { [string]: any } = {}
		for _, ability in GameData.abilityList do
			registry[ability.behavior] = {}
		end
		for _, status in GameData.statusEffects do
			registry[status.behavior] = {}
		end
		registry.status_burn = {
			paramsCheck = Schema.object({
				residualFraction = Schema.number(0.01, 0.5),
				attackMultiplier = Schema.number(0.1, 1),
			}),
		}
		t.noIssues(DataValidator.validate(GameData.raw, { behaviors = registry }).errors)

		local raw = TableUtil.deepCopy(GameData.raw)
		find(raw.statusEffects, "burn").params.residualFraction = 0.9
		t.hasIssue(
			DataValidator.validate(raw, { behaviors = registry }).errors,
			"range",
			"statusEffects.burn.params.residualFraction"
		)
	end)

	--------------------------------------------------------------------------
	-- Reporting
	--------------------------------------------------------------------------

	t.test("assertValid throws once with the full report; formatReport is bounded", function()
		local report = validateMutated(function(raw)
			find(raw.species, "embercub").catchRate = 300
			find(raw.species, "ripplet").catchRate = 300
		end)
		t.throws(function()
			DataValidator.assertValid(report)
		end, "error(s)")
		local text = DataValidator.formatReport(report)
		t.truthy(string.find(text, "species.embercub.catchRate", 1, true))
		t.truthy(string.find(text, "species.ripplet.catchRate", 1, true), "all errors are in the one report")

		DataValidator.assertValid(DataValidator.validate(GameData.raw)) -- must not throw

		local flood = validateMutated(function(raw)
			for _, species in raw.species do
				species.catchRate = 999
				species.baseXpYield = 99999
				species.dexNumber = 0
			end
			for _, move in raw.moves do
				move.pp = 0
				move.priority = 99
			end
		end)
		local lines = 0
		for _ in string.gmatch(DataValidator.formatReport(flood), "[^\n]+") do
			lines += 1
		end
		t.truthy(lines <= 202, "report output is capped")
	end)
end
