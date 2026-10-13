--!strict
--[[
	Services/DataValidationService

	Runs the content validator once at server start. If any ERROR is found the
	service throws with the full report and Bootstrap fails closed (see there).
	Warnings are printed and do not stop the server.

	Phase 3 will pass a BehaviorRegistry here so ability/status `behavior`
	references are verified instead of reported as unverified.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataFolder = Shared:WaitForChild("Data") :: ModuleScript

local GameData = require(DataFolder)
local DataValidator = require(DataFolder:WaitForChild("DataValidator") :: ModuleScript)

local DataValidationService = {
	name = "DataValidationService",
}

function DataValidationService.start()
	local report = DataValidator.validate(GameData.raw, { behaviors = nil })

	if #report.errors > 0 then
		-- One error carrying every problem, so a bad deploy is fixed in one pass.
		DataValidator.assertValid(report)
	end

	for _, warning in report.warnings do
		warn(`[DataValidator] [{warning.code}] {warning.path}: {warning.message}`)
	end

	local counts = report.counts
	print(
		`[DataValidator] OK: {counts.species} species, {counts.moves} moves, {counts.abilities} abilities, `
			.. `{counts.items} items, {counts.statusEffects} statuses, {counts.encounterTables} encounter tables `
			.. `({#report.warnings} warning(s))`
	)
end

return DataValidationService
