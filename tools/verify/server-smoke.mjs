// Executes src/server/Bootstrap.server.luau and Services/DataValidationService
// against a MOCK of the Roblox services they touch (Players, RunService,
// ServerScriptService, ReplicatedStorage), to exercise their control flow, in
// particular the fail-closed paths.
//
// LIMITS, stated plainly: the mock encodes what the code assumes about the
// Roblox API (GetService, WaitForChild, FindFirstChild, IsA, Player:Kick,
// RunService:IsStudio, Players.PlayerAdded:Connect). It proves the logic and
// syntax, NOT that those APIs behave as assumed. Verify in Studio (see the
// manual checklist in the Phase 1 report).

import { LuauState } from 'luau-web'
import { buildBundle, roots, repoRoot } from './lib.mjs'
import path from 'node:path'

const rootMap = { ...roots, Server: path.join(repoRoot, 'src', 'server') }
delete rootMap.Tests

const MOCK = (studio) => `
local logs = { prints = {}, warns = {}, kicked = {}, handlers = {} }
local config = { studio = ${studio}, players = {} }

local function join(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	return table.concat(parts, " ")
end
local function print(...) table.insert(logs.prints, join(...)) end
local function warn(...) table.insert(logs.warns, join(...)) end

local function makePlayer(name)
	return { Name = name, Kick = function(self, message) table.insert(logs.kicked, { name = name, message = message }) end }
end

local Players = {
	GetPlayers = function(self) return config.players end,
	PlayerAdded = { Connect = function(self, handler) table.insert(logs.handlers, handler); return { Disconnect = function() end } end },
}
local RunService = { IsStudio = function(self) return config.studio end }
local services = {
	Players = Players,
	RunService = RunService,
	ServerScriptService = nodes["Server"],
	ReplicatedStorage = { WaitForChild = function(self, name) if name == "Shared" then return nodes["Shared"] end return nil end },
}
local game = { GetService = function(self, name)
	local service = services[name]
	if service == nil then error("mock: unexpected GetService(" .. tostring(name) .. ")") end
	return service
end }
`

const DRIVER = `
config.players = { makePlayer("existing1"), makePlayer("existing2") }
local ok, err = pcall(sources["Server/Bootstrap.server"], nodes["Server/Bootstrap.server"])
local kickedBeforeJoin = #logs.kicked
local kickMessage = ""
if logs.kicked[1] ~= nil then kickMessage = logs.kicked[1].message end
local lateJoinKicked = false
if #logs.handlers > 0 then
	logs.handlers[1](makePlayer("late_joiner"))
	lateJoinKicked = #logs.kicked == kickedBeforeJoin + 1 and logs.kicked[#logs.kicked].name == "late_joiner"
end
return ok, tostring(err), kickedBeforeJoin, #logs.handlers, lateJoinKicked, kickMessage, table.concat(logs.prints, "\\n"), table.concat(logs.warns, "\\n")
`

const scenarios = [
	{
		name: 'live server, valid data: boots, kicks nobody',
		studio: false,
		expect: (r) => [
			[r.ok === true, 'bootstrap completes without error'],
			[r.prints.includes('[Bootstrap] all services started'), 'prints the all-started line'],
			[r.prints.includes('[DataValidator] OK: 15 species'), 'validator reports 15 species'],
			[r.kicked === 0, 'no player is kicked'],
			[r.handlers === 0, 'no PlayerAdded kick handler is installed'],
			[r.warns.includes('assets_unassigned'), 'unassigned-art warning is surfaced via warn()'],
		],
	},
	{
		name: 'live server, INVALID data: fails closed (kicks current + late joiners) and errors',
		studio: false,
		overrides: { 'Shared/Data/Species': (s) => s.replace('catchRate = 190', 'catchRate = 999') },
		expect: (r) => [
			[r.ok === false, 'bootstrap raises an error'],
			[r.err.includes('DataValidationService'), 'error names the failing service'],
			[r.err.includes('species.embercub.catchRate'), 'error carries the validator report'],
			[r.kicked === 2, 'both existing players are kicked'],
			[r.kickMessage.includes('rejoin'), 'players get a retry message'],
			[r.handlers === 1, 'a PlayerAdded handler is installed'],
			[r.lateJoinKicked, 'a late joiner is kicked by that handler'],
			[!r.prints.includes('all services started'), 'does not claim success'],
		],
	},
	{
		name: 'Studio, INVALID data: errors loudly but does not kick',
		studio: true,
		overrides: { 'Shared/Data/Species': (s) => s.replace('catchRate = 190', 'catchRate = 999') },
		expect: (r) => [
			[r.ok === false, 'bootstrap raises an error'],
			[r.err.includes('species.embercub.catchRate'), 'error carries the validator report'],
			[r.kicked === 0, 'nobody is kicked in Studio'],
			[r.handlers === 0, 'no kick handler in Studio'],
		],
	},
	{
		name: 'a service listed in SERVICE_ORDER that does not exist fails closed',
		studio: false,
		overrides: { 'Server/Bootstrap.server': (s) => s.replace('"DataValidationService",', '"NopeService",') },
		expect: (r) => [
			[r.ok === false, 'bootstrap raises an error'],
			[r.err.includes('NopeService') && r.err.includes('module not found'), 'error says the module was not found'],
			[r.kicked === 2 && r.handlers === 1, 'fails closed'],
		],
	},
	{
		name: 'a service whose start() throws fails closed and reports the cause',
		studio: false,
		overrides: {
			'Server/Services/DataValidationService': (s) =>
				s.replace('function DataValidationService.start()', 'function DataValidationService.start()\n\terror("boom from start", 0)'),
		},
		expect: (r) => [
			[r.ok === false, 'bootstrap raises an error'],
			[r.err.includes('boom from start'), 'underlying error is preserved'],
			[r.kicked === 2 && r.handlers === 1, 'fails closed'],
		],
	},
]

let failures = 0
for (const scenario of scenarios) {
	const { bundle, mapLines } = buildBundle({
		rootMap,
		afterNodes: MOCK(scenario.studio),
		driver: DRIVER,
		overrides: scenario.overrides ?? {},
	})
	const state = await LuauState.createAsync({})
	let result
	try {
		const main = state.loadstring(bundle, 'bundle', true)
		result = await main()
	} catch (error) {
		console.log(`ERROR  ${scenario.name}\n       ${mapLines(error?.stack ?? error?.message ?? error)}`)
		failures++
		state.destroy()
		continue
	}
	state.destroy()
	const [ok, err, kicked, handlers, lateJoinKicked, kickMessage, prints, warns] = result
	const checks = scenario.expect({ ok, err: mapLines(err), kicked, handlers, lateJoinKicked, kickMessage, prints, warns })
	const failed = checks.filter(([pass]) => !pass)
	console.log(`${failed.length === 0 ? 'PASS ' : 'FAIL '} ${scenario.name}`)
	for (const [, label] of failed) console.log(`       x ${label}`)
	if (failed.length > 0) {
		failures++
		console.log(`       err: ${mapLines(err).split('\n')[0]}`)
	}
}

console.log(`\n${scenarios.length - failures}/${scenarios.length} server scenarios passed`)
process.exit(failures > 0 ? 1 : 0)
