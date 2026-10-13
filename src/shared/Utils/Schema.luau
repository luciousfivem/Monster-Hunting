--!strict
--[[
	Utils/Schema.luau

	Composable runtime checks for UNTRUSTED data: content tables today, loaded
	profiles and Remote arguments in later phases.

	WHY a library instead of ad-hoc `type(x) == ...` ladders:
	  * Roblox gives no runtime type safety. `--!strict` only checks code you
	    wrote; it says nothing about a table a client sent or a DataStore returned.
	  * One implementation of "is this a finite integer in range" means one place
	    to get NaN / inf / -0 / holes-in-arrays right, instead of fifty.
	  * Checks report ALL problems with a path, so a bad data deploy yields one
	    complete error list rather than one crash at a time.

	Design rules
	  * A check never throws on bad input; it appends Issues to `out`.
	  * Objects reject unknown keys. For authored content that catches typos
	    (`catchrate` vs `catchRate`). For profiles Phase 2 will strip instead.
	  * Numbers must be finite. NaN and +-inf cannot be saved in a DataStore and
	    poison every comparison, so they are rejected at the door.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Table)

local Schema = {}

--------------------------------------------------------------------------------
-- Issue helpers
--------------------------------------------------------------------------------

function Schema.add(out: { Types.Issue }, severity: Types.Severity, code: string, path: string, message: string)
	table.insert(out, { severity = severity, code = code, path = path, message = message })
end

local function fail(out: { Types.Issue }, code: string, path: string, message: string)
	Schema.add(out, "error", code, path, message)
end

local function describe(value: any): string
	local kind = typeof(value)
	if kind == "string" then
		local text = value :: string
		if #text > 24 then
			text = string.sub(text, 1, 24) .. "..."
		end
		return string.format("string %q", text)
	elseif kind == "number" then
		return "number " .. tostring(value)
	end
	return kind
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function make(validate: (value: any, path: string, out: { Types.Issue }) -> (), optional: boolean): Types.SchemaCheck
	return { optional = optional, validate = validate }
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

function Schema.integer(min: number, max: number): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "number" then
			fail(out, "type", path, "expected integer, got " .. describe(value))
		elseif not isFinite(value) then
			fail(out, "not_finite", path, "number must be finite, got " .. tostring(value))
		elseif math.floor(value) ~= value then
			fail(out, "not_integer", path, "expected an integer, got " .. tostring(value))
		elseif value < min or value > max then
			fail(out, "range", path, `{value} is outside [{min}, {max}]`)
		end
	end, false)
end

function Schema.number(min: number, max: number): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "number" then
			fail(out, "type", path, "expected number, got " .. describe(value))
		elseif not isFinite(value) then
			fail(out, "not_finite", path, "number must be finite, got " .. tostring(value))
		elseif value < min or value > max then
			fail(out, "range", path, `{value} is outside [{min}, {max}]`)
		end
	end, false)
end

function Schema.boolean(): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "boolean" then
			fail(out, "type", path, "expected boolean, got " .. describe(value))
		end
	end, false)
end

-- Length is in bytes (these strings are ASCII-oriented ids and labels).
-- Control characters are always rejected: they have no business in names and are
-- a classic way to smuggle log-injection or invisible text.
function Schema.string(minLength: number, maxLength: number, pattern: string?, patternDescription: string?): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "string" then
			fail(out, "type", path, "expected string, got " .. describe(value))
			return
		end
		local text = value :: string
		if #text < minLength or #text > maxLength then
			fail(out, "length", path, `length {#text} is outside [{minLength}, {maxLength}]`)
		elseif string.find(text, "%c") ~= nil then
			fail(out, "format", path, "contains control characters")
		elseif pattern ~= nil and string.find(text, pattern) == nil then
			fail(out, "format", path, `{describe(text)} does not match {patternDescription or pattern}`)
		end
	end, false)
end

-- lower_snake_case identifier used for every record id and cross-reference.
function Schema.identifier(): Types.SchemaCheck
	return Schema.string(1, 48, "^[a-z][a-z0-9_]*$", "lower_snake_case identifier")
end

function Schema.oneOf(options: { string }): Types.SchemaCheck
	local allowed = TableUtil.toSet(options)
	local listing = table.concat(options, ", ")
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "string" then
			fail(out, "type", path, `expected one of [{listing}], got {describe(value)}`)
		elseif not allowed[value] then
			fail(out, "enum", path, `{describe(value)} is not one of [{listing}]`)
		end
	end, false)
end

--------------------------------------------------------------------------------
-- Combinators
--------------------------------------------------------------------------------

-- `nil` passes; anything else must satisfy `check`.
function Schema.optional(check: Types.SchemaCheck): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if value ~= nil then
			check.validate(value, path, out)
		end
	end, true)
end

function Schema.custom(validate: (value: any, path: string, out: { Types.Issue }) -> ()): Types.SchemaCheck
	return make(validate, false)
end

function Schema.array(item: Types.SchemaCheck, minLength: number, maxLength: number): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if not TableUtil.isArray(value) then
			fail(out, "not_array", path, "expected a dense array (1..n, no holes, no metatable), got " .. describe(value))
			return
		end
		local length = #value
		if length < minLength or length > maxLength then
			fail(out, "length", path, `array length {length} is outside [{minLength}, {maxLength}]`)
		end
		for index, element in value do
			item.validate(element, `{path}[{index}]`, out)
		end
	end, false)
end

function Schema.map(keyCheck: Types.SchemaCheck, valueCheck: Types.SchemaCheck, maxEntries: number): Types.SchemaCheck
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			fail(out, "type", path, "expected a plain table, got " .. describe(value))
			return
		end
		local count = 0
		for _ in value do
			count += 1
		end
		if count > maxEntries then
			fail(out, "length", path, `{count} entries exceeds the limit of {maxEntries}`)
			return
		end
		for key, element in value do
			if type(key) ~= "string" then
				fail(out, "type", path, "map keys must be strings, got " .. describe(key))
			else
				keyCheck.validate(key, `{path}.<key {key}>`, out)
				valueCheck.validate(element, `{path}.{key}`, out)
			end
		end
	end, false)
end

-- Fixed-shape record. Missing non-optional fields and unknown fields are errors.
-- Keys are visited in sorted order so reports are stable run to run.
function Schema.object(shape: { [string]: Types.SchemaCheck }): Types.SchemaCheck
	local shapeKeys = TableUtil.sortedKeys(shape)
	return make(function(value: any, path: string, out: { Types.Issue })
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			fail(out, "type", path, "expected a plain table, got " .. describe(value))
			return
		end
		for _, key in shapeKeys do
			local check = shape[key]
			local field = value[key]
			if field == nil then
				if not check.optional then
					fail(out, "missing", `{path}.{key}`, "required field is missing")
				end
			else
				check.validate(field, `{path}.{key}`, out)
			end
		end
		local extra: { string } = {}
		for key in value do
			if type(key) ~= "string" then
				fail(out, "type", path, "object keys must be strings, got " .. describe(key))
			elseif shape[key] == nil then
				table.insert(extra, key)
			end
		end
		table.sort(extra)
		for _, key in extra do
			fail(out, "unknown_field", `{path}.{key}`, "field is not part of the schema (typo?)")
		end
	end, false)
end

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

-- Runs `check` against `value` and returns every issue found (empty = valid).
function Schema.check(check: Types.SchemaCheck, value: any, rootPath: string): { Types.Issue }
	local out: { Types.Issue } = {}
	if value == nil and check.optional then
		return out
	end
	check.validate(value, rootPath, out)
	return out
end

return table.freeze(Schema)
