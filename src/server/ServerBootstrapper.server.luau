local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- Modules
local AbilityServer = ServerScriptService:WaitForChild("AbilityServer")
local AbilityServerManager = require(AbilityServer:WaitForChild("AbilityServerManager"))

-- Require WeaponServerManager so server listeners (WeaponFire, WeaponReload) operate
local FpsServer = ServerScriptService:WaitForChild("FpsServer")
local WeaponServerManager = require(FpsServer:WaitForChild("WeaponServerManager")) :: any

-- [[ TARGETING YOUR ACTUAL VIEWMODELS CONTEXT LOCATION ]]
local FpsSystem = ReplicatedStorage:WaitForChild("FpsSystem")
local WeaponsFolder = FpsSystem:WaitForChild("ViewModels") :: Folder

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local ToggleGameModeEvent = Remotes:WaitForChild("ToggleGameMode") :: RemoteEvent
local RequestSwapModeEvent = Remotes:WaitForChild("RequestSwapMode") :: RemoteEvent

local currentMode = nil

-- [[ PRIVATE COMPONENT UTILITIES ]]

-- Run-time weapon sanitizer pipeline
local function sanitizeAndWeldAllTools()
	print("🛠️ [Bootstrapper Sanitizer] Running initialization optimization on weapon assets...")
	local optimizedToolsCount = 0

	for _, item in ipairs(WeaponsFolder:GetChildren()) do
		if item:IsA("Tool") then
			optimizedToolsCount += 1
			local handle = item:FindFirstChild("Handle") :: BasePart?

			-- Force clean baseline settings on everything in the tool
			for _, descendant in ipairs(item:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					descendant.CanCollide = false

					-- If it's a multi-part weapon, dynamically link loose pieces to the Handle
					if handle and descendant ~= handle then
						-- Wipe old broken or conflicting constraints
						for _, oldLink in ipairs(descendant:GetChildren()) do
							if oldLink:IsA("WeldConstraint") or oldLink:IsA("Weld") or oldLink:IsA("ManualWeld") then
								oldLink:Destroy()
							end
						end

						-- Build fresh production-stable weld bridges
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = handle
						weld.Part1 = descendant
						weld.Parent = descendant
					end
				end
			end

			-- Handle absolute priority checks
			if handle then
				handle.Anchored = false
				handle.CanCollide = false
			else
				warn(string.format("⚠️ [Bootstrapper Sanitizer WARNING] Tool '%s' does not contain a part named 'Handle'!", item.Name))
			end
		end
	end
	print(string.format("✅ [Bootstrapper Sanitizer] Successfully sanitized and prepared %d weapons.", optimizedToolsCount))
end

local function distributeWeaponsToAll()
	print("🎒 [WeaponCloner] Sifting ViewModels folder for weapon assets...")

	local weapons = WeaponsFolder:GetChildren()
	local toolCount = 0

	-- 1. Seed StarterPack so future spawns inherit the tools
	for _, item in ipairs(weapons) do
		if item:IsA("Tool") then
			toolCount += 1
			local clone = item:Clone()
			clone.Parent = game:GetService("StarterPack")
		end
	end

	if toolCount == 0 then
		warn("⚠️ [WeaponCloner ERROR] Found 0 'Tool' instances inside ReplicatedStorage.FpsSystem.ViewModels. Make sure your guns are actual Tool classes!")
		return
	end
	print(string.format("✅ [WeaponCloner] Seeded %d tools from ViewModels into StarterPack.", toolCount))

	-- 2. Inject instantly into online players
	for _, player in ipairs(Players:GetPlayers()) do
		local backpack = player:WaitForChild("Backpack", 5) :: Backpack?
		if backpack then
			for _, item in ipairs(weapons) do
				if item:IsA("Tool") then
					local toolName = item.Name
					local alreadyHasIt = backpack:FindFirstChild(toolName) or (player.Character and player.Character:FindFirstChild(toolName))

					if not alreadyHasIt then
						local toolClone = item:Clone()
						toolClone.Parent = backpack
						print(string.format("🎒 Delivered %s directly to %s's Backpack.", toolName, player.Name))
					end
				end
			end
		end
	end
end

local function stripWeaponsFromGame()
	print("🧹 [WeaponCloner] Systematically purging weapon assets from environment layers.")

	local weaponNames = {}
	for _, item in ipairs(WeaponsFolder:GetChildren()) do
		if item:IsA("Tool") then
			weaponNames[item.Name] = true
		end
	end

	-- 1. Wipe the master StarterPack repository
	for _, item in ipairs(game:GetService("StarterPack"):GetChildren()) do
		if item:IsA("Tool") and weaponNames[item.Name] then
			item:Destroy()
		end
	end

	-- 2. Scrape live characters and backend backpacks
	for _, player in ipairs(Players:GetPlayers()) do
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, item in ipairs(backpack:GetChildren()) do
				if item:IsA("Tool") and weaponNames[item.Name] then
					item:Destroy()
				end
			end
		end

		local character = player.Character
		if character then
			for _, item in ipairs(character:GetChildren()) do
				if item:IsA("Tool") and weaponNames[item.Name] then
					item:Destroy()
				end
			end
		end
	end
end

-- Pure local function to safely transition states
local function swapGameMode(nextModeName: string)
	if currentMode == nextModeName then 
		warn("Server Bootstrapper: Game mode " .. nextModeName .. " is already active.")
		return 
	end

	print("Server Bootstrapper: Intercepted hot-swap from " .. tostring(currentMode) .. " to " .. nextModeName)

	-- 1. Tell all clients to teardown active modules
	ToggleGameModeEvent:FireAllClients("Stop")

	-- 2. Teardown server systems for the old mode
	if currentMode == "DungeonMode" and AbilityServerManager.CleanMode then
		AbilityServerManager.CleanMode(currentMode)
	elseif currentMode == "ArenaMode" then
		stripWeaponsFromGame()
		if WeaponServerManager.CleanMode then
			WeaponServerManager.CleanMode()
		end
	end

	currentMode = nextModeName
	task.wait(0.3) -- State synchronization delay

	-- 3. Initialize server systems for the new mode
	if nextModeName == "DungeonMode" then
		if AbilityServerManager.InitMode then
			AbilityServerManager.InitMode(nextModeName)
		end
	elseif nextModeName == "ArenaMode" then
		distributeWeaponsToAll()
		-- INITIALIZE WEAPON SERVER LISTENTERS (Fire, Reload, Ammo processing)
		if WeaponServerManager.InitMode then
			WeaponServerManager.InitMode()
		end
	end

	-- 4. Tell all clients to build up new modules
	ToggleGameModeEvent:FireAllClients("Start", nextModeName)
end

-- Capture persistent frame requests from the clients
RequestSwapModeEvent.OnServerEvent:Connect(function(player, requestedMode)
	if typeof(requestedMode) ~= "string" then return end
	swapGameMode(requestedMode)
end)

-- [[ OPTIMIZED PLAYER CONNECTIONS MECHANIC ]]
local function handleNewPlayerArrival(player: Player)
	player.CharacterAdded:Connect(function(character)
		if currentMode == "ArenaMode" then
			task.wait(0.5)
			local backpack = player:WaitForChild("Backpack", 5) :: Backpack?
			if backpack then
				for _, item in ipairs(WeaponsFolder:GetChildren()) do
					if item:IsA("Tool") and not backpack:FindFirstChild(item.Name) then
						item:Clone().Parent = backpack
						print(string.format("🎯 Late Joiner: Instantly assigned %s from ViewModels to %s", item.Name, player.Name))
					end
				end
			end
		end
	end)
end

-- Safely process players who loaded into Studio before this script initialized
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(handleNewPlayerArrival, existingPlayer)
end
Players.PlayerAdded:Connect(handleNewPlayerArrival)

-- [[ EXECUTE STRUCTURAL INTEGRITY CLEANUP UPON BOOT ]]
sanitizeAndWeldAllTools()