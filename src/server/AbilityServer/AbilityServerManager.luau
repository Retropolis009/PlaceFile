--!strict
-- ServerScriptService.AbilityServer.AbilityServerManager

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- Framework Modules
local AbilitySystem = ReplicatedStorage:WaitForChild("AbilitySystem")
local SharedAbilityClass = require(AbilitySystem:WaitForChild("SharedAbilityClass")) :: any
local DataManager = require(ServerScriptService:WaitForChild("DataStore"):WaitForChild("DataManager")) :: any

-- Network 
local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local AbilityNetwork = RemoteEvents:WaitForChild("NetworkHandler") :: RemoteEvent
local replicateVFXRemote = RemoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

-- Types
type SharedAbilityInstance = {
	CanCast: (self: any) -> boolean,
	ServerActivate: (self: any, targetData: any) -> (),
	LastCastTime: number,
	Data: { Name: string }
}

type RuntimeCombatCache = {
	ActiveInstances: { [string]: SharedAbilityInstance }, 
	LookupByName: { [string]: SharedAbilityInstance }     
}

type SilenceZone = {
	Position: Vector3,
	Radius: number,
	Caster: Player,
	EndTime: number
}

-- Private State
local ActiveCombatCaches: { [Player]: RuntimeCombatCache } = {}
local ActiveSilenceZones: { SilenceZone } = {}

local AbilityServerManager = {}

-- Private Utility Functions
local function dispatchAuthoritativeClientSync(player: Player)
	local profile = DataManager.GetProfile(player)
	if not profile then return end

	local loadoutPayload: { [string]: string } = {}
	for _, slotKey in ipairs({"Slot1", "Slot2", "Slot3", "Slot4"}) do
		loadoutPayload[slotKey] = profile.ActiveLoadout[slotKey] or "Empty"
	end

	local unlockedPayload: { [string]: boolean } = {}
	for abilityName, isUnlocked in pairs(profile.UnlockedAbilities) do
		unlockedPayload[abilityName] = isUnlocked
	end

	AbilityNetwork:FireClient(player, "SyncLoadoutPayload", loadoutPayload, unlockedPayload)
end

-- Instance Management
function AbilityServerManager.RebuildRuntimeInstances(player: Player)
	local profile = DataManager.GetProfile(player)
	local character = player.Character
	if not profile or not character or not character:FindFirstChild("Humanoid") then return end

	local cache = ActiveCombatCaches[player]
	if not cache then
		cache = { ActiveInstances = {}, LookupByName = {} }
		ActiveCombatCaches[player] = cache
	end

	table.clear(cache.ActiveInstances)
	table.clear(cache.LookupByName)

	for slotKey, abilityName in pairs(profile.ActiveLoadout) do
		if abilityName ~= "Empty" then
			local instanceObj = SharedAbilityClass.new(character, abilityName)
			if instanceObj then
				cache.ActiveInstances[slotKey] = instanceObj
				cache.LookupByName[abilityName] = instanceObj
			end
		end
	end
end

-- Silence Zone Logic
function AbilityServerManager.CreateSilenceZone(caster: Player, position: Vector3, radius: number, duration: number)
	local zoneData: SilenceZone = {
		Position = position,
		Radius = radius,
		Caster = caster,
		EndTime = os.clock() + duration
	}
	table.insert(ActiveSilenceZones, zoneData)

	replicateVFXRemote:FireAllClients("Silence", "SpawnField", {
		Position = position,
		Radius = radius,
		Duration = duration
	})

	task.delay(duration, function()
		local index = table.find(ActiveSilenceZones, zoneData)
		if index then
			local lastIndex = #ActiveSilenceZones
			if index ~= lastIndex then
				ActiveSilenceZones[index] = ActiveSilenceZones[lastIndex]
			end
			ActiveSilenceZones[lastIndex] = nil
		end
	end)
end

function AbilityServerManager.IsPlayerSilenced(player: Player): boolean
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return false end

	local currentTime = os.clock()
	local playerPos = hrp.Position

	for i = 1, #ActiveSilenceZones do
		local zone = ActiveSilenceZones[i]
		if currentTime < zone.EndTime and zone.Caster ~= player then
			local deltaX = playerPos.X - zone.Position.X
			local deltaY = playerPos.Y - zone.Position.Y
			local deltaZ = playerPos.Z - zone.Position.Z
			local sqrDistance = (deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ)

			if sqrDistance <= (zone.Radius * zone.Radius) then
				return true
			end
		end
	end
	return false
end

-- Loadout Operations
function AbilityServerManager.RequestLoadoutSwap(player: Player, targetSlotKey: string, newAbilityName: string)
	local profile = DataManager.GetProfile(player)
	if not profile then return end

	if not profile.UnlockedAbilities[newAbilityName] and newAbilityName ~= "Empty" then return end

	for slotKey, existingAbilityName in pairs(profile.ActiveLoadout) do
		if slotKey ~= targetSlotKey and existingAbilityName == newAbilityName and newAbilityName ~= "Empty" then
			local existingOccupant = profile.ActiveLoadout[targetSlotKey] or "Empty"
			DataManager.UpdateSlot(player, slotKey, existingOccupant)
			break
		end
	end

	DataManager.UpdateSlot(player, targetSlotKey, newAbilityName)
	AbilityServerManager.RebuildRuntimeInstances(player)
	dispatchAuthoritativeClientSync(player)
end

-- Energy Regeneration Loop
task.spawn(function()
	while true do
		task.wait(1.0)
		local activePlayers = Players:GetPlayers()

		for i = 1, #activePlayers do
			local player = activePlayers[i]
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?

			if character and humanoid and humanoid.Health > 0 then
				local currentEnergy = character:GetAttribute("Energy")
				if typeof(currentEnergy) == "number" then
					if currentEnergy < 100 then
						character:SetAttribute("Energy", math.min(100, currentEnergy + 5))
					end
				else
					character:SetAttribute("Energy", 100)
				end
			end
		end
	end
end)

-- Player Lifecycle Handlers
local function onPlayerAdded(player: Player)
	ActiveCombatCaches[player] = { ActiveInstances = {}, LookupByName = {} }

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then return end

		character:SetAttribute("Energy", 100)
		AbilityServerManager.RebuildRuntimeInstances(player)
		dispatchAuthoritativeClientSync(player)
	end)
end

local function onPlayerRemoving(player: Player)
	ActiveCombatCaches[player] = nil
end

-- Network Handling
AbilityNetwork.OnServerEvent:Connect(function(player: Player, actionOrAbility: any, arg1: any, arg2: any)
	local profile = DataManager.GetProfile(player)
	local combatCache = ActiveCombatCaches[player]

	if not profile or not combatCache then 
		warn(string.format("Dropped remote request from %s: profile or combat cache not initialized.", player.Name))
		return 
	end

	if actionOrAbility == "RequestLoadoutSync" then
		local activeLoadout = profile.ActiveLoadout or {}
		local unlockedPool = profile.UnlockedAbilities or {}
		AbilityNetwork:FireClient(player, "SyncLoadoutPayload", activeLoadout, unlockedPool)
		return
	end

	if actionOrAbility == "UpdateLoadout" then
		local clientLoadoutTable = arg1
		if type(clientLoadoutTable) ~= "table" then return end

		local changed = false
		for slotKey, abilityName in pairs(clientLoadoutTable) do
			if type(slotKey) == "string" and type(abilityName) == "string" then
				if profile.ActiveLoadout[slotKey] ~= abilityName then
					AbilityServerManager.RequestLoadoutSwap(player, slotKey, abilityName)
					changed = true
				end
			end
		end
		if not changed then
			dispatchAuthoritativeClientSync(player)
		end

	elseif actionOrAbility == "ReplicateEnvironmentHitVFX" then
		local abilityName = arg1
		local hitPosition = arg2

		if type(abilityName) == "string" and typeof(hitPosition) == "Vector3" then
			if combatCache.LookupByName[abilityName] then
				replicateVFXRemote:FireAllClients(abilityName, "Impact", {
					Position = hitPosition
				})
			end
		end

	elseif type(actionOrAbility) == "string" then
		local abilityName = actionOrAbility :: string
		local targetData = arg1

		if AbilityServerManager.IsPlayerSilenced(player) then
			local instanceObj = combatCache.LookupByName[abilityName]
			local lastCast = instanceObj and instanceObj.LastCastTime or 0
			AbilityNetwork:FireClient(player, "SyncCooldown", abilityName, lastCast)
			return
		end

		local instanceObj = combatCache.LookupByName[abilityName]
		if not instanceObj then return end

		if instanceObj:CanCast() then
			instanceObj:ServerActivate(targetData)
		end

		AbilityNetwork:FireClient(player, "SyncCooldown", abilityName, instanceObj.LastCastTime)
	end
end)

-- Connections
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

return AbilityServerManager