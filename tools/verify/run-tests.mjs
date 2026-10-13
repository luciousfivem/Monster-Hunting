// Runs tests/*.spec.luau against src/shared in a Luau VM (luau-web: Luau compiled
// to WebAssembly). Usage: `npm install && npm test` from tools/verify.
//
// What this proves: the pure-Luau modules COMPILE and their specs PASS under a
// real Luau VM. What it does NOT prove: anything about Roblox's runtime/APIs, or
// `--!strict` type correctness (use `npm run typecheck` for that).

import { LuauState } from 'luau-web'
import { buildBundle } from './lib.mjs'

const { bundle, mapLines } = buildBundle({
	driver: `
local run = require(nodes["Tests/Run"])
local passed, failed, report = run(nodes["Shared"])
return passed, failed, report
`,
})

const state = await LuauState.createAsync({})
let main
try {
	main = state.loadstring(bundle, 'bundle', true)
} catch (error) {
	console.error('Luau failed to COMPILE the bundle:\n' + mapLines(error?.message ?? error))
	process.exit(2)
}

let result
try {
	result = await main()
} catch (error) {
	console.error('Luau raised a runtime error:\n' + mapLines(error?.stack ?? error?.message ?? error))
	process.exit(2)
}

const [passed, failed, report] = result
console.log(mapLines(report))
state.destroy()
process.exit(failed > 0 ? 1 : 0)
