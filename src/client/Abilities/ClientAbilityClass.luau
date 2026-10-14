 --!strict
-- ReplicatedStorage.AbilitySystem.ClientAbilityClass
local ClientAbilityClass = {}
ClientAbilityClass.__index = ClientAbilityClass

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Framework Modules
local AbilitySystem = ReplicatedStorage:WaitForChild("AbilitySystem")
local SharedAbilityClass = require(AbilitySystem:WaitForChild("SharedAbilityClass")) :: any

-- Network / Bindables
local AbilityNetwork = ReplicatedStorage.Remotes.RemoteEvents.NetworkHandler
local RequestAbilityUse = ReplicatedStorage.Remotes.BindableEvents:WaitForChild("RequestAbilityUse") :: BindableEvent
local ForceSyncInput = ReplicatedStorage.Remotes.BindableEvents:WaitForChild("ForceSyncInput") :: BindableEvent

type SharedAbilityInstance = {
	CanCast: (self: any) -> boolean,
	LocalActivate: (self: any, targetData: any) -> (),
	GetRemainingCooldown: (self: any) -> number,
	Destroy: (self: any) -> (), -- Added explicitly to prevent memory leaks across characters
	LastCastTime: number,
}

local LocalPlayer = (Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()) :: Player

-- [[ SINGLETON STORAGE POINTER MATRIX ]]
local SharedStorage = shared :: any
if not SharedStorage.__AbilityClassMemoryBridge then
	SharedStorage.__AbilityClassMemoryBridge = {
		EquippedNames = {},
		ActiveInstances = {},
		ListenerBound = false
	}
end

local MemoryBridge = SharedStorage.__AbilityClassMemoryBridge
local EquippedNames: { [string]: boolean } = MemoryBridge.EquippedNames
local ActiveInstances: { [string]: SharedAbilityInstance } = MemoryBridge.ActiveInstances

function ClientAbilityClass.UpdateCharacterReference(character: Model)
	-- Cleanly dispose of old character state configurations to clear memory properly
	for abilityName, instance in pairs(ActiveInstances) do
		if type(instance.Destroy) == "function" then
			instance:Destroy()
		end
		ActiveInstances[abilityName] = nil
	end

	for abilityName, isEquipped in pairs(EquippedNames) do
		if isEquipped then
			local abilityInstance = SharedAbilityClass.new(character, abilityName)
			if abilityInstance then
				ActiveInstances[abilityName] = abilityInstance
			else
				warn(string.format("SharedAbilityClass failed to construct an instance for: %s", abilityName))
			end
		end
	end
	ForceSyncInput:Fire()
end

function ClientAbilityClass.EquipAbility(abilityName: string)
	EquippedNames[abilityName] = true

	local character = LocalPlayer.Character
	if character then
		-- Cleanup existing copy first if double equipping happens edge-case
		local existing = ActiveInstances[abilityName]
		if existing and type(existing.Destroy) == "function" then
			existing:Destroy()
		end

		local abilityInstance = SharedAbilityClass.new(character, abilityName)
		if abilityInstance then
			ActiveInstances[abilityName] = abilityInstance
		else
			warn(string.format("Could not dynamically instantiate physical state link for: %s", abilityName))
		end
	end
end

function ClientAbilityClass.UnequipAbility(abilityName: string)
	EquippedNames[abilityName] = nil

	local existing = ActiveInstances[abilityName]
	if existing then
		if type(existing.Destroy) == "function" then
			existing:Destroy()
		end
		ActiveInstances[abilityName] = nil
	end
end

function ClientAbilityClass.UseAbility(abilityName: string, targetData: any)
	local ability = ActiveInstances[abilityName]

	if not ability then
		warn(string.format("You do not have %s equipped inside ActiveInstances memory array!", abilityName))
		return
	end

	if ability:CanCast() then
		ability.LastCastTime = workspace:GetServerTimeNow()

		-- Prediction framework local run
		ability:LocalActivate(targetData)

		-- Authoritative execution request dispatched to server infrastructure
		AbilityNetwork:FireServer(abilityName, targetData)
	else
		warn(string.format("%s is on cooldown! (%fs left)", abilityName, ability:GetRemainingCooldown()))
	end
end

-- [[ SINGLETON LIFECYCLE GUARD ]]
if not MemoryBridge.ListenerBound then
	MemoryBridge.ListenerBound = true

	RequestAbilityUse.Event:Connect(function(abilityName: string, targetData: any)
		ClientAbilityClass.UseAbility(abilityName, targetData)
	end)

	AbilityNetwork.OnClientEvent:Connect(function(action: any, abilityName: any, serverTimestamp: any)
		if action == "SyncCooldown" then
			local targetAbility = ActiveInstances[abilityName :: string]
			if targetAbility then
				targetAbility.LastCastTime = serverTimestamp :: number
			else
				warn(string.format("Received cooldown sync for %s, but no active tracking instance exists!", tostring(abilityName)))
			end
		end
	end)

	LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		if newCharacter:WaitForChild("Humanoid", 5) then
			task.defer(ClientAbilityClass.UpdateCharacterReference, newCharacter)
		end
	end)
end

return ClientAbilityClass