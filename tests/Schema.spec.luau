--!strict
return function(t: any, load: (string) -> any)
	local S = load("Utils/Schema")
	local TableUtil = load("Utils/Table")

	local nan = 0 / 0
	local inf = math.huge

	local function run(check: any, value: any): { any }
		return S.check(check, value, "v")
	end

	t.test("integer accepts valid integers and rejects everything else", function()
		local check = S.integer(1, 10)
		t.noIssues(run(check, 1))
		t.noIssues(run(check, 10))
		t.hasIssue(run(check, 0), "range")
		t.hasIssue(run(check, 11), "range")
		t.hasIssue(run(check, 2.5), "not_integer")
		t.hasIssue(run(check, nan), "not_finite")
		t.hasIssue(run(check, inf), "not_finite")
		t.hasIssue(run(check, -inf), "not_finite")
		t.hasIssue(run(check, "5"), "type")
		t.hasIssue(run(check, nil), "type")
		t.hasIssue(run(check, true), "type")
	end)

	t.test("number accepts floats but still rejects NaN and infinity", function()
		local check = S.number(0, 1)
		t.noIssues(run(check, 0.25))
		t.hasIssue(run(check, 1.5), "range")
		t.hasIssue(run(check, nan), "not_finite")
		t.hasIssue(run(check, inf), "not_finite")
		t.hasIssue(run(check, "0.5"), "type")
	end)

	t.test("boolean", function()
		t.noIssues(run(S.boolean(), false))
		t.hasIssue(run(S.boolean(), 0), "type")
		t.hasIssue(run(S.boolean(), nil), "type")
	end)

	t.test("string enforces length, control characters and patterns", function()
		local check = S.string(2, 5, "^%a+$", "letters")
		t.noIssues(run(check, "abc"))
		t.hasIssue(run(check, "a"), "length")
		t.hasIssue(run(check, "abcdef"), "length")
		t.hasIssue(run(check, "ab1"), "format")
		t.hasIssue(run(S.string(0, 10), "a\nb"), "format", "v")
		t.hasIssue(run(S.string(0, 10), "a\0b"), "format")
		t.hasIssue(run(check, 5), "type")
	end)

	t.test("identifier is lower_snake_case", function()
		local check = S.identifier()
		t.noIssues(run(check, "fire_pup2"))
		t.hasIssue(run(check, "Fire"), "format")
		t.hasIssue(run(check, "2fire"), "format")
		t.hasIssue(run(check, "fire-pup"), "format")
		t.hasIssue(run(check, ""), "length")
		t.hasIssue(run(check, string.rep("a", 49)), "length")
	end)

	t.test("oneOf", function()
		local check = S.oneOf({ "a", "b" })
		t.noIssues(run(check, "a"))
		t.hasIssue(run(check, "c"), "enum")
		t.hasIssue(run(check, 1), "type")
	end)

	t.test("array rejects holes, extra keys, metatables and bad lengths", function()
		local check = S.array(S.integer(0, 9), 1, 3)
		t.noIssues(run(check, { 1, 2, 3 }))
		t.hasIssue(run(check, {}), "length")
		t.hasIssue(run(check, { 1, 2, 3, 4 }), "length")
		t.hasIssue(run(check, { [1] = 1, [3] = 3 }), "not_array", "v")
		local holey: { any } = { 1, nil, 3 } -- hole inside the array part
		t.hasIssue(run(check, holey), "not_array", "v")
		t.hasIssue(run(check, { 1, 2, extra = 5 }), "not_array")
		t.hasIssue(run(check, { a = 1 }), "not_array")
		t.hasIssue(run(check, setmetatable({ 1 }, {})), "not_array")
		t.hasIssue(run(check, "x"), "not_array")
		t.hasIssue(run(check, { 1, 20 }), "range", "v[2]")
	end)

	t.test("map validates keys, values and size", function()
		local check = S.map(S.identifier(), S.integer(0, 5), 2)
		t.noIssues(run(check, { a = 1, b = 2 }))
		t.hasIssue(run(check, { a = 1, b = 2, c = 3 }), "length")
		t.hasIssue(run(check, { A = 1 }), "format")
		t.hasIssue(run(check, { a = 9 }), "range", "v.a")
		t.hasIssue(run(check, { [1] = 1 }), "type")
		t.hasIssue(run(check, 5), "type")
	end)

	t.test("object reports missing, unknown and nested problems with paths", function()
		local check = S.object({
			id = S.identifier(),
			stats = S.object({ hp = S.integer(1, 9) }),
			note = S.optional(S.string(0, 5)),
		})
		t.noIssues(run(check, { id = "x", stats = { hp = 3 } }))
		t.noIssues(run(check, { id = "x", stats = { hp = 3 }, note = "hi" }))
		t.hasIssue(run(check, { stats = { hp = 3 } }), "missing", "v.id")
		t.hasIssue(run(check, { id = "x", stats = { hp = 30 } }), "range", "v.stats.hp")
		t.hasIssue(run(check, { id = "x", stats = { hp = 3 }, typo = 1 }), "unknown_field", "v.typo")
		t.hasIssue(run(check, { id = "x", stats = { hp = 3 }, note = "toolong" }), "length", "v.note")
		t.hasIssue(run(check, { id = "x", stats = {} }), "missing", "v.stats.hp")
		t.hasIssue(run(check, "nope"), "type")
		t.hasIssue(run(check, setmetatable({ id = "x", stats = { hp = 3 } }, {})), "type")
		t.hasIssue(run(check, { id = "x", stats = { hp = 3 }, [5] = 1 }), "type")
	end)

	t.test("object reports ALL problems, in a stable order", function()
		local check = S.object({ a = S.integer(1, 2), b = S.integer(1, 2), c = S.integer(1, 2) })
		local first = run(check, { a = 9, b = 9, c = 9, z = 1, y = 1 })
		local second = run(check, { z = 1, c = 9, y = 1, b = 9, a = 9 })
		t.eq(#first, 5)
		t.eq(first, second, "issue order does not depend on table construction order")
	end)

	t.test("optional passes nil and checks present values", function()
		local check = S.optional(S.integer(1, 3))
		t.noIssues(run(check, nil))
		t.noIssues(run(check, 2))
		t.hasIssue(run(check, 9), "range")
	end)

	t.test("custom checks can add issues", function()
		local check = S.custom(function(value: any, path: string, out: { any })
			if value ~= "ok" then
				S.add(out, "error", "custom_fail", path, "nope")
			end
		end)
		t.noIssues(run(check, "ok"))
		t.hasIssue(run(check, "bad"), "custom_fail")
	end)

	t.test("Table.isArray / deepCopy / deepFreeze behave", function()
		t.truthy(TableUtil.isArray({}))
		t.truthy(TableUtil.isArray({ 1, 2 }))
		t.falsy(TableUtil.isArray({ [2] = 1 }))
		local holey: { any } = { 1, nil, 3 }
		local leading: { any } = { nil, 2 }
		t.falsy(TableUtil.isArray(holey), "a hole inside the array part")
		t.falsy(TableUtil.isArray(leading), "a leading hole")
		t.falsy(TableUtil.isArray({ 1, x = 1 }))
		t.falsy(TableUtil.isArray({ [1.5] = 1 }))

		local original = { a = { b = { 1, 2 } } }
		original.self = original -- cycle
		local copy = TableUtil.deepCopy(original)
		t.truthy(copy ~= original)
		t.truthy(copy.a ~= original.a)
		t.truthy(copy.self == copy, "cycle is preserved in the copy")
		copy.a.b[1] = 99
		t.eq(original.a.b[1], 1, "mutating the copy leaves the original untouched")

		local frozen = TableUtil.deepFreeze({ a = { b = { 1 } } })
		t.truthy(table.isfrozen(frozen))
		t.truthy(table.isfrozen(frozen.a.b), "nested tables are frozen")
		t.throws(function()
			frozen.a.b[1] = 2
		end)
	end)
end
