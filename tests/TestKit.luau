--!strict
--[[
	tests/TestKit.luau

	A deliberately tiny test harness (no dependencies). TestEZ is superseded by
	Jest-Lua for large suites (verify current status in Roblox docs); for pure
	logic modules this is enough, and it runs unchanged in Studio's command bar
	and in the offline runner (tools/verify).

	Specs receive `(t, load)`:
	  t.test(name, fn)            registers and runs a test immediately
	  t.eq / t.truthy / t.falsy / t.near / t.throws
	  t.hasIssue(issues, code, pathFragment?)   an Issue with that code exists
	  t.noIssues(issues)                        no issues at all (prints them if any)
	  load("Utils/Rng")                         requires a module under Shared
]]

local TestKit = {}

export type Kit = {
	suite: (name: string) -> (),
	test: (name: string, fn: () -> any) -> (),
	eq: (actual: any, expected: any, message: string?) -> (),
	truthy: (value: any, message: string?) -> (),
	falsy: (value: any, message: string?) -> (),
	near: (actual: number, expected: number, tolerance: number, message: string?) -> (),
	throws: (fn: () -> any, fragment: string?) -> (),
	hasIssue: (issues: { any }, code: string, pathFragment: string?) -> (),
	noIssues: (issues: { any }) -> (),
	results: () -> (number, number, { string }),
}

local function show(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function describeIssues(issues: { any }): string
	local parts: { string } = {}
	for index, issue in issues do
		if index > 8 then
			table.insert(parts, `... +{#issues - 8} more`)
			break
		end
		table.insert(parts, `[{issue.code}] {issue.path}: {issue.message}`)
	end
	return table.concat(parts, "\n      ")
end

function TestKit.new(): Kit
	local passed = 0
	local failed = 0
	local failures: { string } = {}
	local currentSuite = "?"

	local function check(condition: boolean, message: string)
		if not condition then
			error(message, 3)
		end
	end

	local kit: Kit = {
		suite = function(name: string)
			currentSuite = name
		end,

		test = function(name: string, fn: () -> any)
			local ok, err = pcall(fn)
			if ok then
				passed += 1
			else
				failed += 1
				table.insert(failures, `  FAIL {currentSuite} > {name}\n      {tostring(err)}`)
			end
		end,

		eq = function(actual: any, expected: any, message: string?)
			check(deepEqual(actual, expected), `{message or "values differ"}: expected {show(expected)}, got {show(actual)}`)
		end,

		truthy = function(value: any, message: string?)
			check(value ~= nil and value ~= false, message or `expected a truthy value, got {show(value)}`)
		end,

		falsy = function(value: any, message: string?)
			check(value == nil or value == false, message or `expected a falsy value, got {show(value)}`)
		end,

		near = function(actual: number, expected: number, tolerance: number, message: string?)
			check(math.abs(actual - expected) <= tolerance, `{message or "not near"}: expected {expected} +- {tolerance}, got {actual}`)
		end,

		throws = function(fn: () -> any, fragment: string?)
			local ok, err = pcall(fn)
			check(not ok, "expected the function to throw")
			if fragment ~= nil then
				check(string.find(tostring(err), fragment, 1, true) ~= nil, `error "{tostring(err)}" does not contain "{fragment}"`)
			end
		end,

		hasIssue = function(issues: { any }, code: string, pathFragment: string?)
			for _, issue in issues do
				if issue.code == code and (pathFragment == nil or string.find(issue.path, pathFragment, 1, true) ~= nil) then
					return
				end
			end
			local where = ""
			if pathFragment ~= nil then
				where = ` at "{pathFragment}"`
			end
			error(`no issue with code "{code}"{where}; got:\n      {describeIssues(issues)}`, 2)
		end,

		noIssues = function(issues: { any })
			check(#issues == 0, `expected no issues, got {#issues}:\n      {describeIssues(issues)}`)
		end,

		results = function(): (number, number, { string })
			return passed, failed, failures
		end,
	}
	return kit
end

return TestKit
