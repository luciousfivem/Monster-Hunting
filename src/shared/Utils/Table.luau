--!strict
--[[
	Utils/Table.luau

	Small, dependency-free table helpers.

	WHY deepFreeze matters here: species/move/etc. records are shared by every
	player and every battle on the server. The classic bug is code that copies a
	"base" record into a battler and then mutates the original by accident,
	silently changing the game for everyone. A frozen record turns that bug into
	an immediate, loud error at the line that tried.
]]

local TableUtil = {}

-- True only for a plain, dense, 1..n sequence with no metatable.
-- Why strict: a table with holes or extra keys looks like an array to `#` but is
-- serialized by DataStores as a dictionary, which corrupts it on the next load.
function TableUtil.isArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if getmetatable(value) ~= nil then
		return false
	end
	local length = #value
	local count = 0
	for key in value do
		if type(key) ~= "number" or key < 1 or key > length or math.floor(key) ~= key then
			return false
		end
		count += 1
	end
	return count == length
end

local function freezeInto(value: any, seen: { [any]: boolean })
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	for _, child in value do
		freezeInto(child, seen)
	end
	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

-- Recursively freezes `value` (cycle-safe) and returns it.
function TableUtil.deepFreeze<T>(value: T): T
	freezeInto(value, {})
	return value
end

local function copyInto(value: any, seen: { [any]: any }): any
	if type(value) ~= "table" then
		return value
	end
	local existing = seen[value]
	if existing ~= nil then
		return existing
	end
	local copy: { [any]: any } = {}
	seen[value] = copy
	for key, child in value do
		copy[copyInto(key, seen)] = copyInto(child, seen)
	end
	return copy
end

-- Deep copy of plain data (cycle-safe). Metatables are intentionally not copied:
-- this is for data records, never for objects with behavior. The result is
-- always unfrozen, which is what makes it safe to mutate in tests.
function TableUtil.deepCopy<T>(value: T): T
	return copyInto(value, {})
end

function TableUtil.toSet(list: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, item in list do
		set[item] = true
	end
	return set
end

function TableUtil.countKeys(tbl: { [any]: any }): number
	local count = 0
	for _ in tbl do
		count += 1
	end
	return count
end

-- Keys of a string-keyed table in sorted order. `pairs` order is unspecified in
-- Luau; anything that must produce stable output (error reports, tests) sorts.
function TableUtil.sortedKeys(tbl: { [any]: any }): { string }
	local keys: { string } = {}
	for key in tbl do
		if type(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

return table.freeze(TableUtil)
