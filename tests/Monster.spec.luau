--!strict
-- Growth curves, stat formula and nickname rules.
return function(t: any, load: (string) -> any)
	local Growth = load("Monster/Growth")
	local StatCalculator = load("Monster/StatCalculator")
	local Nickname = load("Monster/Nickname")
	local GameData = load("Data")

	t.test("growth curves produce the expected thresholds exactly", function()
		local medSlow = GameData.growthCurves.medium_slow
		t.eq(Growth.xpForLevel(medSlow, 1), 0, "level-1 clamp")
		for _, curve in GameData.growthCurveList do
			t.eq(Growth.xpForLevel(curve, 1), 0, `{curve.id} must start at 0 xp`)
		end
		t.eq(Growth.xpForLevel(medSlow, 2), 9)
		t.eq(Growth.xpForLevel(medSlow, 9), 419)
		t.eq(Growth.xpForLevel(medSlow, 10), 560)
		t.eq(Growth.xpForLevel(medSlow, 100), 1059860)
		t.eq(Growth.xpForLevel(GameData.growthCurves.medium_fast, 100), 999999)
		t.eq(Growth.xpForLevel(GameData.growthCurves.fast, 100), 800000)
		t.eq(Growth.xpForLevel(GameData.growthCurves.slow, 100), 1249998)
	end)

	t.test("levelForXp inverts xpForLevel at every boundary for every curve", function()
		for _, curve in GameData.growthCurveList do
			for level = 1, 100 do
				local needed = Growth.xpForLevel(curve, level)
				t.eq(Growth.levelForXp(curve, needed), level, `{curve.id}: xp {needed} should be level {level}`)
				if level > 1 then
					t.eq(Growth.levelForXp(curve, needed - 1), level - 1, `{curve.id}: xp {needed - 1} should be level {level - 1}`)
				end
			end
			t.eq(Growth.levelForXp(curve, 0), 1)
			t.eq(Growth.levelForXp(curve, 2000000000), 100, "xp beyond max level clamps to max level")
		end
	end)

	t.test("stat formula matches hand-computed values", function()
		-- hp: floor((2*45+31)*50/100) + 50 + 10 = 60 + 60
		t.eq(StatCalculator.computeStat("hp", 45, 31, 50, nil), 120)
		-- other: floor((2*55+0)*50/100) + 5 = 60
		t.eq(StatCalculator.computeStat("attack", 55, 0, 50, nil), 60)
		local brash = GameData.natures.brash
		t.eq(StatCalculator.computeStat("attack", 55, 0, 50, brash), 66, "+10%")
		t.eq(StatCalculator.computeStat("defense", 55, 0, 50, brash), 54, "-10%")
		t.eq(StatCalculator.computeStat("speed", 55, 0, 50, brash), 60, "untouched stat")
		t.eq(StatCalculator.computeStat("hp", 45, 31, 50, brash), 120, "natures never touch hp")
		t.eq(StatCalculator.computeStat("hp", 1, 0, 1, nil), 11, "level 1 minimum hp")
	end)

	t.test("nature adjustments equal exact integer percentages across a wide range", function()
		local up = { id = "up", name = "Up", increased = "attack", decreased = "defense" }
		for base = 1, 255 do
			for level = 1, 100, 11 do
				local neutral = StatCalculator.computeStat("attack", base, 15, level, nil)
				local raised = StatCalculator.computeStat("attack", base, 15, level, up)
				local lowered = StatCalculator.computeStat("defense", base, 15, level, up)
				t.eq(raised, (neutral * 110) // 100)
				t.eq(lowered, (neutral * 90) // 100)
			end
		end
	end)

	t.test("nicknames: accepted forms", function()
		for _, name in { "Sir Fluff", "Mr. O'Neil-2", "A", "1234567890123456", "Fire pup" } do
			local ok, reason = Nickname.validate(name)
			t.truthy(ok, `"{name}" should be valid: {reason}`)
		end
	end)

	t.test("nicknames: rejected forms", function()
		local bad: { any } = {
			"",
			" lead",
			"trail ",
			"dbl  space",
			"-dash",
			"'quote",
			"way too long nickname",
			"emoji\u{1F600}",
			"tab\tname",
			"new\nline",
			"zero\u{200B}width",
			"rtl\u{202E}override",
			"semi;colon",
			"<b>html</b>",
			5,
			true,
			{},
		}
		for _, name in bad do
			local ok, reason = Nickname.validate(name)
			t.falsy(ok, `{tostring(name)} should be invalid`)
			t.truthy(reason, "a reason is given")
		end
		t.eq((Nickname.validate(nil)), false)
	end)

	t.test("nickname.normalize trims and collapses whitespace", function()
		t.eq(Nickname.normalize("  Sir   Fluff \t"), "Sir Fluff")
		t.eq(Nickname.normalize("\n"), "")
		t.eq(Nickname.normalize("ok"), "ok")
	end)
end
