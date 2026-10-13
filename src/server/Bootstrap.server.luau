--!strict
--[[
	ServerScriptService/Bootstrap  (a Script)

	The ONLY entry-point script on the server. It requires services in an
	explicit order and starts them one at a time. Everything else is a
	ModuleScript in ServerScriptService/Services.

	WHY one bootstrap with an explicit order (instead of each service being its
	own Script): script start order across multiple Scripts is not something to
	depend on, and later services need earlier ones ready (persistence before
	battles, battles before trading). Explicit order makes dependencies visible.

	FAIL-CLOSED policy: if any service fails to start, the server must not run
	half-initialised. A server that accepts players with no working persistence
	or invalid game data can corrupt saves. So on failure:
	  * Studio : error out so the Output window shows the full message.
	  * Live   : kick every current and future player with a retry message, then
	             error so the failure reaches logging. Players land on a healthy
	             server on rejoin.

	A Service is `{ name: string, start: () -> () }`. Add new services to
	SERVICE_ORDER as the phases land.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

type Service = {
	name: string,
	start: () -> (),
}

local SERVICE_ORDER: { string } = {
	"DataValidationService", -- Phase 1: refuse to boot on invalid content
	-- "PersistenceService",  -- Phase 2
	-- "BattleService",       -- Phase 3
	-- ...
}

local KICK_MESSAGE = "The server failed to start correctly. Please rejoin in a moment."

local function failClosed(serviceName: string, err: any)
	local message = `[Bootstrap] service "{serviceName}" failed to start:\n{tostring(err)}`
	if not RunService:IsStudio() then
		local function kick(player: Player)
			player:Kick(KICK_MESSAGE)
		end
		-- Intentionally never disconnected: this server must stay closed for its lifetime.
		Players.PlayerAdded:Connect(kick)
		for _, player in Players:GetPlayers() do
			kick(player)
		end
	end
	error(message, 0)
end

local servicesFolder = ServerScriptService:WaitForChild("Services")

for _, serviceName in SERVICE_ORDER do
	local moduleInstance = servicesFolder:FindFirstChild(serviceName)
	if moduleInstance == nil or not moduleInstance:IsA("ModuleScript") then
		failClosed(serviceName, "module not found in ServerScriptService/Services")
		return
	end

	local loaded, service = pcall(function(): Service
		return require(moduleInstance :: ModuleScript) :: Service
	end)
	if not loaded then
		failClosed(serviceName, service)
		return
	end

	local started, startError = pcall(service.start)
	if not started then
		failClosed(serviceName, startError)
		return
	end

	print(`[Bootstrap] started {service.name}`)
end

print("[Bootstrap] all services started")
