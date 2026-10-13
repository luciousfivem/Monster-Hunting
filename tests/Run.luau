--!strict
--[[
	tests/Run.luau

	Runs every `*.spec` ModuleScript that sits next to this file.

	In Studio (server command bar):
	    local passed, failed, report = require(game.ServerStorage.Tests.Run)(game.ReplicatedStorage.Shared)
	    print(report)

	Each spec module returns `function(t, load)`; see TestKit.
	This lives in ServerStorage, so it is never replicated to clients. Do not
	call it from game code.
]]

local TestKit = require(script.Parent.TestKit)

local function loadFrom(shared: Instance, path: string): any
	local node: Instance = shared
	for segment in string.gmatch(path, "[^/]+") do
		local child = node:FindFirstChild(segment)
		if child == nil then
			error(`test loader: "{path}" not found (missing "{segment}")`, 2)
		end
		node = child
	end
	return require(node :: ModuleScript)
end

local function run(shared: Instance): (number, number, string)
	local kit = TestKit.new()

	local specs: { Instance } = {}
	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and string.sub(child.Name, -5) == ".spec" then
			table.insert(specs, child)
		end
	end
	table.sort(specs, function(a: Instance, b: Instance): boolean
		return a.Name < b.Name
	end)

	for _, spec in specs do
		kit.suite(spec.Name)
		local ok, err = pcall(function()
			local define = require(spec :: ModuleScript) :: any
			define(kit, function(path: string): any
				return loadFrom(shared, path)
			end)
		end)
		if not ok then
			kit.test("spec module loads", function()
				error(tostring(err), 0)
			end)
		end
	end

	local passed, failed, failures = kit.results()
	local lines: { string } = { `[tests] {passed} passed, {failed} failed` }
	for _, failure in failures do
		table.insert(lines, failure)
	end
	return passed, failed, table.concat(lines, "\n")
end

return run
