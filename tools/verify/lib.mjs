// Shared helpers for the offline verification tools.
//
// Mirrors Rojo's file -> instance naming rules closely enough to resolve
// `require(script.Parent.Foo)`-style paths between the pure-Luau modules:
//   Foo.luau          -> ModuleScript "Foo"
//   Foo.spec.luau     -> ModuleScript "Foo.spec"
//   Dir/init.luau     -> ModuleScript "Dir" whose children are Dir/*
//   Dir/ (no init)    -> Folder "Dir"
//
// This is a verification aid, NOT Roblox. It cannot catch Roblox API misuse.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

// Virtual roots: name -> directory on disk.
export const roots = {
	Shared: path.join(repoRoot, 'src', 'shared'),
	Tests: path.join(repoRoot, 'tests'),
}

// Returns [{ vpath: 'Shared/Data/Species', file, className }]
export function collectModules(rootMap = roots) {
	const modules = []
	for (const [rootName, dir] of Object.entries(rootMap)) {
		const walk = (current, segments) => {
			for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
				const full = path.join(current, entry.name)
				if (entry.isDirectory()) {
					walk(full, [...segments, entry.name])
				} else if (entry.name.endsWith('.luau')) {
					const base = entry.name.slice(0, -'.luau'.length)
					const vsegments = base === 'init' ? segments : [...segments, base]
					modules.push({ vpath: [rootName, ...vsegments].join('/'), file: full, className: 'ModuleScript' })
				}
			}
		}
		walk(dir, [])
	}
	return modules
}

// Resolves `script.Parent.Foo.Bar` (the expression inside require(...)) from the
// module at `vpath` to the vpath of the target module.
export function resolveRequire(fromVpath, expr, knownVpaths) {
	const parts = expr.trim().split('.').map((p) => p.trim())
	if (parts[0] !== 'script') throw new Error(`unsupported require expression: ${expr}`)
	let segments = fromVpath.split('/')
	for (const part of parts.slice(1)) {
		if (part === 'Parent') {
			segments = segments.slice(0, -1)
		} else {
			segments = [...segments, part]
		}
	}
	const target = segments.join('/')
	if (!knownVpaths.has(target)) throw new Error(`require(${expr}) from ${fromVpath} -> ${target}: no such module`)
	return target
}

// Matches `require(script....)` anywhere on a line.
export const REQUIRE_RE = /require\(\s*(script(?:\s*\.\s*\w+)+)\s*\)/g

export function readSource(file) {
	return fs.readFileSync(file, 'utf8')
}

const luaString = (s) => JSON.stringify(s)

// Builds ONE Luau chunk containing a virtual instance tree for every module under
// `rootMap`, a `require` that understands it, and the module sources.
//
//   rootMap      { RootName: dir }            virtual roots (see `roots`)
//   afterNodes   Luau text inserted after the tree exists but before module
//                sources are defined (put mocks such as `game` here so modules
//                capture them as upvalues)
//   driver       Luau text that runs last; its `return` values go back to JS
//   overrides    { vpath: (source) => source } rewrite a module before bundling
//                (used by tests to inject bad data)
//
// Returns { bundle, mapLines } where mapLines rewrites `[string "bundle"]:N`
// positions in error text to `relative/file.luau:line`.
export function buildBundle({ rootMap = roots, afterNodes = '', driver, overrides = {} }) {
	const modules = collectModules(rootMap)
	const byVpath = new Map(modules.map((m) => [m.vpath, m]))

	// Every prefix of a module path is an instance: a ModuleScript if it is a
	// module itself (init.luau), otherwise a Folder.
	const nodeOrder = []
	const seen = new Set()
	for (const { vpath } of modules) {
		const segments = vpath.split('/')
		for (let i = 1; i <= segments.length; i++) {
			const prefix = segments.slice(0, i).join('/')
			if (!seen.has(prefix)) {
				seen.add(prefix)
				nodeOrder.push(prefix)
			}
		}
	}
	nodeOrder.sort((a, b) => a.split('/').length - b.split('/').length || a.localeCompare(b))

	const parts = [PRELUDE]
	const moduleRanges = [] // { start, end, file } in bundle line numbers (1-based)
	const countLines = () => parts.join('\n').split('\n').length

	for (const vpath of nodeOrder) {
		const segments = vpath.split('/')
		const name = segments[segments.length - 1]
		const parent = segments.length > 1 ? `nodes[${luaString(segments.slice(0, -1).join('/'))}]` : 'nil'
		const isModule = byVpath.has(vpath)
		parts.push(`nodes[${luaString(vpath)}] = newNode(${luaString(name)}, ${luaString(isModule ? 'ModuleScript' : 'Folder')}, ${parent})`)
		if (isModule) parts.push(`rawset(nodes[${luaString(vpath)}], "__id", ${luaString(vpath)})`)
	}

	parts.push(afterNodes)

	for (const m of modules) {
		// Types are erased at runtime; `export type` is only legal at a module's top
		// level, so strip the modifier when wrapping the module in a function.
		let source = readSource(m.file).replace(/^export type /gm, 'type ')
		if (overrides[m.vpath]) source = overrides[m.vpath](source)
		const header = `sources[${luaString(m.vpath)}] = function(script)`
		const start = countLines() + 1 // line of the header; source line 1 is start + 1
		parts.push(`${header}\n${source}\nend`)
		moduleRanges.push({ start: start + 1, end: start + source.split('\n').length, file: path.relative(repoRoot, m.file) })
	}

	parts.push(driver)

	function mapLines(text) {
		return String(text).replace(/\[string "bundle"\]:(\d+)/g, (match, n) => {
			const line = Number(n)
			const range = moduleRanges.find((r) => line >= r.start && line <= r.end)
			return range ? `${range.file}:${line - range.start + 1}` : match
		})
	}

	return { bundle: parts.join('\n'), mapLines }
}

const PRELUDE = `
local NodeMethods = {}
local NodeMeta = {}
function NodeMeta.__index(self, key)
	local method = NodeMethods[key]
	if method ~= nil then return method end
	return NodeMethods.FindFirstChild(self, key)
end
local function newNode(name, className, parent)
	local node = { Name = name, ClassName = className, Parent = parent, __children = {} }
	setmetatable(node, NodeMeta)
	if parent ~= nil then table.insert(rawget(parent, "__children"), node) end
	return node
end
function NodeMethods.FindFirstChild(self, childName)
	for _, child in rawget(self, "__children") do
		if child.Name == childName then return child end
	end
	return nil
end
NodeMethods.WaitForChild = NodeMethods.FindFirstChild
function NodeMethods.GetChildren(self)
	local out = {}
	for _, child in rawget(self, "__children") do table.insert(out, child) end
	return out
end
function NodeMethods.IsA(self, className)
	return self.ClassName == className or className == "Instance"
end

local nodes = {}
local sources = {}
local cache = {}

local function require(node)
	local id = rawget(node, "__id")
	if id == nil then error("require: not a ModuleScript: " .. tostring(node.Name), 2) end
	local entry = cache[id]
	if entry ~= nil then
		if entry.loading then error("cyclic require involving " .. id, 2) end
		return entry.value
	end
	entry = { loading = true }
	cache[id] = entry
	local value = sources[id](node)
	entry.loading = false
	entry.value = value
	return value
end
`
