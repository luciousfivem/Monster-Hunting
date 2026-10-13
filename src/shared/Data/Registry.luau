--!strict
--[[
	Data/Registry.luau

	Pure function: RawGameData -> (GameDataSnapshot, issues).

	It indexes records by id and builds the derived lookups other systems need
	(sorted lists, element-type map, reverse evolution map). It NEVER throws on
	malformed input: duplicate or missing ids become Issues and the offending
	record is skipped. That is deliberate. The validator and the tests feed it
	broken data on purpose and must get a complete report instead of a crash.

	The module is separate from Data/init so that it has no side effects on
	require, which is what lets tests build snapshots from mutated copies.
]]

local Types = require(script.Parent.Parent.Types)
local TableUtil = require(script.Parent.Parent.Utils.Table)
local Schema = require(script.Parent.Parent.Utils.Schema)

local Registry = {}

-- Indexes `list` by `record.id`. First occurrence wins; later duplicates are
-- reported and dropped so lookups stay deterministic.
local function indexById(list: any, kind: string, issues: { Types.Issue }): ({ [string]: any }, { any })
	local map: { [string]: any } = {}
	local ordered: { any } = {}
	if not TableUtil.isArray(list) then
		Schema.add(issues, "error", "not_array", kind, `{kind} must be a dense array of records`)
		return map, ordered
	end
	for index, record in list do
		local id: any = nil
		if type(record) == "table" then
			id = record.id
		end
		if type(id) ~= "string" then
			Schema.add(issues, "error", "missing_id", `{kind}[{index}]`, "record has no string id")
		elseif map[id] ~= nil then
			Schema.add(issues, "error", "duplicate_id", `{kind}.{id}`, `id "{id}" is defined more than once`)
		else
			map[id] = record
			table.insert(ordered, record)
		end
	end
	return map, ordered
end

local function dexOrder(a: any, b: any): boolean
	local dexA = if type(a.dexNumber) == "number" then a.dexNumber else math.huge
	local dexB = if type(b.dexNumber) == "number" then b.dexNumber else math.huge
	if dexA ~= dexB then
		return dexA < dexB
	end
	return a.id < b.id
end

function Registry.build(raw: any): (Types.GameDataSnapshot, { Types.Issue })
	local issues: { Types.Issue } = {}
	if type(raw) ~= "table" then
		raw = {}
		Schema.add(issues, "error", "type", "gameData", "raw game data must be a table")
	end

	local speciesMap, speciesList = indexById(raw.species, "species", issues)
	local moveMap, moveList = indexById(raw.moves, "moves", issues)
	local abilityMap, abilityList = indexById(raw.abilities, "abilities", issues)
	local itemMap, itemList = indexById(raw.items, "items", issues)
	local statusMap, statusList = indexById(raw.statusEffects, "statusEffects", issues)
	local natureMap, natureList = indexById(raw.natures, "natures", issues)
	local curveMap, curveList = indexById(raw.growthCurves, "growthCurves", issues)
	local encounterMap, encounterList = indexById(raw.encounterTables, "encounterTables", issues)

	table.sort(speciesList, dexOrder)

	local typeChart = raw.typeChart
	if type(typeChart) ~= "table" then
		Schema.add(issues, "error", "type", "typeChart", "typeChart must be a table")
		typeChart = { types = {}, matchups = {} }
	end
	local elementMap, _ = indexById(typeChart.types, "typeChart.types", issues)

	-- Reverse evolution map: target species -> species that evolve into it.
	local evolvesFrom: { [string]: { string } } = {}
	for _, record in speciesList do
		local evolutions = record.evolutions
		if TableUtil.isArray(evolutions) then
			for _, rule in evolutions do
				if type(rule) == "table" and type(rule.toSpeciesId) == "string" then
					local sources = evolvesFrom[rule.toSpeciesId]
					if sources == nil then
						sources = {}
						evolvesFrom[rule.toSpeciesId] = sources
					end
					if not table.find(sources, record.id) then
						table.insert(sources, record.id)
					end
				end
			end
		end
	end

	local snapshot: Types.GameDataSnapshot = {
		species = speciesMap,
		speciesList = speciesList,
		moves = moveMap,
		moveList = moveList,
		abilities = abilityMap,
		abilityList = abilityList,
		items = itemMap,
		itemList = itemList,
		statusEffects = statusMap,
		statusEffectList = statusList,
		natures = natureMap,
		natureList = natureList,
		growthCurves = curveMap,
		growthCurveList = curveList,
		encounterTables = encounterMap,
		encounterTableList = encounterList,
		elementTypes = elementMap,
		typeChart = typeChart,
		evolvesFrom = evolvesFrom,
	}
	return snapshot, issues
end

return table.freeze(Registry)
