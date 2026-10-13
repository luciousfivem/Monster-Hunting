--!strict
--[[
	Data/init.luau  ==  `require(ReplicatedStorage.Shared.Data)`

	The game-data entry point. Requires every content module, builds the indexed
	snapshot, and deep-freezes it.

	Usage
	  local GameData = require(Shared.Data)
	  local species = GameData.species["embercub"]       -- map by id
	  for _, s in GameData.speciesList do ... end        -- ordered by dex number

	Everything returned is frozen. Mutating game data at runtime is a bug, and a
	frozen table makes it a loud one at the exact line that tried.

	Validation is NOT run here: `require` must stay cheap and side-effect free on
	clients. The server runs Data/DataValidator once at startup
	(Services/DataValidationService) and refuses to boot on errors.
]]

local Types = require(script.Parent.Types)
local TableUtil = require(script.Parent.Utils.Table)
local Registry = require(script.Registry)

local raw: Types.RawGameData = {
	species = require(script.Species),
	moves = require(script.Moves),
	abilities = require(script.Abilities),
	items = require(script.Items),
	statusEffects = require(script.StatusEffects),
	natures = require(script.Natures),
	growthCurves = require(script.GrowthCurves),
	encounterTables = require(script.EncounterTables),
	typeChart = require(script.TypeChart),
}

local snapshot, buildIssues = Registry.build(raw)

-- Snapshot fields are copied flat so call sites read `GameData.species[id]`.
local gameData = table.clone(snapshot) :: any
gameData.raw = raw
gameData.buildIssues = buildIssues

return TableUtil.deepFreeze(gameData :: Types.GameData)
