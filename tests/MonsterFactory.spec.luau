--!strict
-- MonsterFactory (creation) and MonsterSchema (strict validation) including
-- hostile / corrupted records.
return function(t: any, load: (string) -> any)
	local MonsterFactory = load("Monster/MonsterFactory")
	local MonsterSchema = load("Monster/MonsterSchema")
	local Rng = load("Utils/Rng")
	local TableUtil = load("Utils/Table")
	local GameData = load("Data")

	local FIXED_NOW = 1700000000

	local function deps(seed: number): any
		local counter = 0
		return {
			rng = Rng.new(seed),
			newGuid = function(): string
				counter += 1
				return string.format("00000000-0000-4000-8000-%012d", counter)
			end,
			now = function(): number
				return FIXED_NOW
			end,
		}
	end

	local function create(speciesId: string, level: number, seed: number?, overrides: any?): (any, string?)
		local params: { [string]: any } = {
			speciesId = speciesId,
			level = level,
			originalTrainerUserId = 12345,
			caughtMethod = "wild",
		}
		for key, value in overrides or {} do
			params[key] = value
		end
		return MonsterFactory.create(GameData, params :: any, deps(seed or 1))
	end

	local function validMonster(): any
		local monster, err = create("embercub", 10, 7)
		t.truthy(monster, `setup failed: {err}`)
		return TableUtil.deepCopy(monster)
	end

	local function tampered(mutate: (monster: any) -> ()): { any }
		local monster = validMonster()
		mutate(monster)
		return MonsterSchema.validate(GameData, monster)
	end

	--------------------------------------------------------------------------
	-- Factory
	--------------------------------------------------------------------------

	t.test("every species at several levels produces a schema-valid monster", function()
		for _, species in GameData.speciesList do
			for _, level in { 1, 2, 5, 36, 99, 100 } do
				local monster, err = create(species.id, level, level * 31 + species.dexNumber)
				t.truthy(monster, `{species.id} L{level}: {err}`)
				t.noIssues(MonsterSchema.validate(GameData, monster))
				t.eq(monster.level, level)
				t.truthy(#monster.moveset >= 1 and #monster.moveset <= 4)
			end
		end
	end)

	t.test("new monsters start with the documented defaults", function()
		local monster = create("embercub", 5, 3)
		t.eq(monster.speciesId, "embercub")
		t.eq(monster.tradeCount, 0)
		t.eq(monster.caughtAt, FIXED_NOW)
		t.eq(monster.caughtMethod, "wild")
		t.eq(monster.originalTrainerUserId, 12345)
		t.eq(monster.schemaVersion, 1)
		t.eq(monster.currentHp, nil, "nil = full health")
		t.eq(monster.nickname, nil)
		t.eq(monster.guid, "00000000-0000-4000-8000-000000000001")
		local level1 = create("embercub", 1, 3)
		t.eq(level1.xp, 0, "a level-1 monster has 0 xp")
	end)

	t.test("is deterministic for a given seed and varies across seeds", function()
		t.eq(create("embercub", 12, 42), create("embercub", 12, 42))
		local different = 0
		for seed = 1, 20 do
			local a = create("embercub", 12, seed)
			local b = create("embercub", 12, seed + 1000)
			if a.natureId ~= b.natureId or a.ivs.hp ~= b.ivs.hp or a.ivs.speed ~= b.ivs.speed then
				different += 1
			end
		end
		t.truthy(different >= 18, "different seeds produce different rolls")
	end)

	t.test("IVs cover the whole 0..31 range and natures/abilities are all reachable", function()
		local rng = Rng.new(2024)
		local d = deps(2024)
		d.rng = rng
		local minIv, maxIv = 99, -1
		local natures: { [string]: boolean } = {}
		local abilities: { [string]: number } = {}
		for _ = 1, 1500 do
			local monster = MonsterFactory.create(GameData, {
				speciesId = "embercub",
				level = 5,
				originalTrainerUserId = 1,
				caughtMethod = "wild",
			}, d)
			for _, value in monster.ivs do
				minIv = math.min(minIv, value)
				maxIv = math.max(maxIv, value)
			end
			natures[monster.natureId] = true
			abilities[monster.abilityId] = (abilities[monster.abilityId] or 0) + 1
		end
		t.eq(minIv, 0)
		t.eq(maxIv, 31)
		t.eq(TableUtil.countKeys(natures), 25, "all 25 natures appear")
		-- embercub pool: ember_heart 80 / fierce_aura 20
		t.near((abilities.fierce_aura or 0) / 1500, 0.2, 0.04, "ability weights are honored")
	end)

	t.test("moveset = last four learnset entries at or below the level", function()
		t.eq(create("embercub", 1, 1).moveset, { "bump", "rally" })
		t.eq(create("embercub", 5, 1).moveset, { "bump", "rally", "cinder_bite" })
		t.eq(create("embercub", 14, 1).moveset, { "rally", "cinder_bite", "quick_strike", "flare_burst" })
		t.eq(create("embercub", 100, 1).moveset, { "cinder_bite", "quick_strike", "flare_burst", "reckless_charge" })
	end)

	t.test("scripted overrides are honored when legal", function()
		local ivs = { hp = 31, attack = 31, defense = 31, spAttack = 31, spDefense = 31, speed = 31 }
		local monster = create("embercub", 10, 1, { ivs = ivs, natureId = "brash", abilityId = "fierce_aura", nickname = "Ash" })
		t.eq(monster.ivs, ivs)
		t.truthy(monster.ivs ~= ivs, "ivs are copied, not aliased")
		t.eq(monster.natureId, "brash")
		t.eq(monster.abilityId, "fierce_aura")
		t.eq(monster.nickname, "Ash")
	end)

	t.test("rejects bad parameters instead of producing bad monsters", function()
		local function failsWith(speciesId: string, level: any, overrides: any?, fragment: string)
			local monster, err = create(speciesId, level, 1, overrides)
			t.eq(monster, nil, `expected failure for {speciesId} L{tostring(level)}`)
			t.truthy(err and string.find(err, fragment, 1, true), `error "{tostring(err)}" should mention "{fragment}"`)
		end
		failsWith("nobody", 5, nil, "unknown species")
		failsWith("embercub", 0, nil, "level")
		failsWith("embercub", 101, nil, "level")
		failsWith("embercub", 2.5, nil, "level")
		failsWith("embercub", 0 / 0, nil, "level")
		failsWith("embercub", "5", nil, "level")
		failsWith("embercub", 5, { nickname = "bad name!" }, "nickname")
		failsWith("embercub", 5, { natureId = "grumpy" }, "unknown nature")
		failsWith("embercub", 5, { abilityId = "thick_hide" }, "abilityId") -- not in embercub's pool
		failsWith("embercub", 5, { ivs = { hp = 99, attack = 1, defense = 1, spAttack = 1, spDefense = 1, speed = 1 } }, "ivs")
		failsWith("embercub", 5, { originalTrainerUserId = 1.5 }, "originalTrainerUserId")
	end)

	--------------------------------------------------------------------------
	-- MonsterSchema: hostile / corrupted records
	--------------------------------------------------------------------------

	t.test("a valid monster has no issues", function()
		t.noIssues(MonsterSchema.validate(GameData, validMonster()))
	end)

	t.test("garbage input never throws", function()
		local garbage: { any } = { 5, "x", true, {}, { guid = 5 }, { 1, 2, 3 } }
		for _, value in garbage do
			local ok, issues = pcall(MonsterSchema.validate, GameData, value)
			t.truthy(ok, "validate must not throw")
			t.truthy(#issues > 0)
		end
		local ok, issues = pcall(MonsterSchema.validate, GameData, nil)
		t.truthy(ok and #issues > 0)
	end)

	t.test("level / xp tampering", function()
		t.hasIssue(
			tampered(function(m)
				m.level = 0
			end),
			"range",
			"monster.level"
		)
		t.hasIssue(
			tampered(function(m)
				m.level = 101
			end),
			"range",
			"monster.level"
		)
		t.hasIssue(
			tampered(function(m)
				m.level = 50
			end),
			"xp_level_mismatch",
			"monster.xp"
		)
		t.hasIssue(
			tampered(function(m)
				m.xp = m.xp + 1000000
			end),
			"xp_level_mismatch",
			"monster.xp"
		)
		t.hasIssue(
			tampered(function(m)
				m.xp = -5
			end),
			"range",
			"monster.xp"
		)
		t.hasIssue(
			tampered(function(m)
				m.xp = 0 / 0
			end),
			"not_finite",
			"monster.xp"
		)
		t.hasIssue(
			tampered(function(m)
				m.level = 10.5
			end),
			"not_integer",
			"monster.level"
		)
	end)

	t.test("IV tampering", function()
		t.hasIssue(
			tampered(function(m)
				m.ivs.hp = 32
			end),
			"range",
			"monster.ivs.hp"
		)
		t.hasIssue(
			tampered(function(m)
				m.ivs.speed = -1
			end),
			"range",
			"monster.ivs.speed"
		)
		t.hasIssue(
			tampered(function(m)
				m.ivs.attack = math.huge
			end),
			"not_finite",
			"monster.ivs.attack"
		)
		t.hasIssue(
			tampered(function(m)
				m.ivs.luck = 31
			end),
			"unknown_field",
			"monster.ivs.luck"
		)
		t.hasIssue(
			tampered(function(m)
				m.ivs.defense = nil
			end),
			"missing",
			"monster.ivs.defense"
		)
	end)

	t.test("reference tampering: species, nature, ability, moves", function()
		t.hasIssue(
			tampered(function(m)
				m.speciesId = "mewtwo"
			end),
			"bad_ref",
			"monster.speciesId"
		)
		t.hasIssue(
			tampered(function(m)
				m.natureId = "perfect"
			end),
			"bad_ref",
			"monster.natureId"
		)
		t.hasIssue(
			tampered(function(m)
				m.abilityId = "thick_hide"
			end),
			"illegal_ability",
			"monster.abilityId"
		)
		t.hasIssue(
			tampered(function(m)
				m.moveset = { "bump", "godmode" }
			end),
			"bad_ref",
			"monster.moveset[2]"
		)
		t.hasIssue(
			tampered(function(m)
				m.moveset = { "bump", "bump" }
			end),
			"duplicate",
			"monster.moveset[2]"
		)
		t.hasIssue(
			tampered(function(m)
				m.moveset = { "bump", "rally", "harden", "mend", "quicken" }
			end),
			"length",
			"monster.moveset"
		)
		t.hasIssue(
			tampered(function(m)
				m.moveset = {}
			end),
			"length",
			"monster.moveset"
		)
		t.hasIssue(
			tampered(function(m)
				m.moveset = { [1] = "bump", [3] = "rally" }
			end),
			"not_array",
			"monster.moveset"
		)
	end)

	t.test("structural tampering: unknown fields, missing fields, bad types", function()
		t.hasIssue(
			tampered(function(m)
				m.cheat = true
			end),
			"unknown_field",
			"monster.cheat"
		)
		t.hasIssue(
			tampered(function(m)
				m.guid = nil
			end),
			"missing",
			"monster.guid"
		)
		t.hasIssue(
			tampered(function(m)
				m.guid = "short"
			end),
			"length",
			"monster.guid"
		)
		t.hasIssue(
			tampered(function(m)
				m.guid = "00000000-0000-4000-8000-00000000000'; DROP"
			end),
			"format",
			"monster.guid"
		)
		t.hasIssue(
			tampered(function(m)
				m.caughtMethod = "stolen"
			end),
			"enum",
			"monster.caughtMethod"
		)
		t.hasIssue(
			tampered(function(m)
				m.tradeCount = -1
			end),
			"range",
			"monster.tradeCount"
		)
		t.hasIssue(
			tampered(function(m)
				m.caughtAt = 9999999999999
			end),
			"range",
			"monster.caughtAt"
		)
		t.hasIssue(
			tampered(function(m)
				m.originalTrainerUserId = "123"
			end),
			"type",
			"monster.originalTrainerUserId"
		)
		t.hasIssue(
			tampered(function(m)
				m.schemaVersion = 2
			end),
			"schema_version",
			"monster.schemaVersion"
		)
		t.hasIssue(
			tampered(function(m)
				m.ivs = "max"
			end),
			"type",
			"monster.ivs"
		)
	end)

	t.test("nickname tampering", function()
		t.hasIssue(
			tampered(function(m)
				m.nickname = "x\0y"
			end),
			"nickname",
			"monster.nickname"
		)
		t.hasIssue(
			tampered(function(m)
				m.nickname = "<script>"
			end),
			"nickname",
			"monster.nickname"
		)
		t.hasIssue(
			tampered(function(m)
				m.nickname = string.rep("a", 17)
			end),
			"nickname",
			"monster.nickname"
		)
		t.noIssues(tampered(function(m)
			m.nickname = "Sir Fluff"
		end))
	end)

	t.test("currentHp cannot exceed the computed max HP", function()
		local monster = validMonster()
		local StatCalculator = load("Monster/StatCalculator")
		local maxHp = StatCalculator.computeStat("hp", GameData.species.embercub.baseStats.hp, monster.ivs.hp, monster.level, GameData.natures[monster.natureId])
		t.noIssues(tampered(function(m)
			m.currentHp = maxHp
		end))
		t.noIssues(tampered(function(m)
			m.currentHp = 0
		end))
		t.hasIssue(
			tampered(function(m)
				m.currentHp = maxHp + 1
			end),
			"range",
			"monster.currentHp"
		)
		t.hasIssue(
			tampered(function(m)
				m.currentHp = -1
			end),
			"range",
			"monster.currentHp"
		)
	end)

	t.test("validate reports every problem at once with a custom root path", function()
		local monster = validMonster()
		monster.level = 0
		monster.ivs.hp = 99
		monster.cheat = 1
		local issues = MonsterSchema.validate(GameData, monster, "party[2]")
		t.truthy(#issues >= 3)
		t.hasIssue(issues, "range", "party[2].level")
		t.hasIssue(issues, "range", "party[2].ivs.hp")
		t.hasIssue(issues, "unknown_field", "party[2].cheat")
	end)
end
