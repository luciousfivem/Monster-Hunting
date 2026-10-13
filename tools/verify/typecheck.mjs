// Type-checks the pure-Luau modules under `--!strict` with Luau's own analyzer
// (Luau.Analysis compiled to WebAssembly, via @luau2ts/analyzer).
//
// The analyzer sees ONE source string at a time and has no module resolver, so
// this tool LINKS each module before analysing it:
//   * shared types: Types.luau is inlined at the top and `Types.Foo` -> `Foo`
//   * `require(script....)`: replaced by an immediately-invoked function holding
//     the target module's (recursively linked) source, so call signatures and
//     return types are checked across modules.
//
// Not covered: files that use Roblox APIs (src/server, src/client, tests/Run).
// The analyzer has no Roblox type definitions, so those need Luau LSP / Studio.

import { analyze } from '@luau2ts/analyzer'
import { collectModules, readSource, resolveRequire, REQUIRE_RE } from './lib.mjs'

const modules = collectModules()
const byVpath = new Map(modules.map((m) => [m.vpath, m]))
const known = new Set(byVpath.keys())

const SKIP = new Set(['Tests/Run']) // uses Instance / ModuleScript

function typesBlock() {
	return readSource(byVpath.get('Shared/Types').file)
		.replace(/^--!strict[^\n]*\n/, '')
		.replace(/^export type /gm, 'type ')
		.replace(/^return \{\}\s*$/m, '')
}

function link(vpath, stack) {
	const mod = byVpath.get(vpath)
	let src = readSource(mod.file)
	src = src.replace(/^--!strict[^\n]*\n/, '\n') // keep the line, drop the directive
	src = src.replace(/^export type /gm, 'type ')
	src = src.replace(/^local Types = require\(\s*script[^)]*\)\s*$/gm, '-- (types inlined by typecheck.mjs)')
	src = src.replace(REQUIRE_RE, (_match, expr) => {
		const target = resolveRequire(vpath, expr, known)
		if (target === 'Shared/Types') throw new Error(`${vpath}: unexpected non-local require of Types`)
		if (stack.includes(target)) throw new Error(`cyclic require: ${[...stack, vpath, target].join(' -> ')}`)
		return `(function()\n${link(target, [...stack, vpath])}\nend)()`
	})
	return src.replace(/\bTypes\.([A-Z]\w*)/g, '$1')
}

const TYPES = typesBlock()
let errorCount = 0
let warningCount = 0
let analyzed = 0

for (const mod of modules) {
	if (mod.vpath === 'Shared/Types' || SKIP.has(mod.vpath)) continue
	const linked = `--!strict\n${TYPES}\n${link(mod.vpath, [])}\n`
	const lines = linked.split('\n')
	const diagnostics = await analyze(linked)
	analyzed++

	const seen = new Set()
	for (const d of diagnostics) {
		const lineText = (lines[d.line - 1] ?? '').trim()
		const key = `${d.code}|${d.message}|${lineText}`
		if (seen.has(key)) continue
		seen.add(key)
		if (d.severity === 'error') errorCount++
		else warningCount++
		console.log(`${d.severity.toUpperCase()} ${mod.vpath} [${d.code}] ${d.message.replace(/\n/g, ' | ')}\n      > ${lineText.slice(0, 160)}`)
	}
}

console.log(`\nanalyzed ${analyzed} modules: ${errorCount} error(s), ${warningCount} warning(s)`)
process.exit(errorCount > 0 ? 1 : 0)
