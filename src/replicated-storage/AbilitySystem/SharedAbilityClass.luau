--!strict
-- ReplicatedStorage.AbilitySystem.SharedAbilityClass
local SharedAbilityClass = {}
SharedAbilityClass.__index = SharedAbilityClass

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- [[ STRICT DATA TYPE STRUCTURES ]]
export type AbilityData = {
	Name: string,
	Cooldown: number,
	EnergyCost: number,

	IsMagic: boolean?,
	IsChanneled: boolean?,
	IsMobility: boolean?,

	ClientCast: (caster: Model, targetData: any) -> (),
	ServerExecute: (caster: Model, targetData: any) -> (),
}

export type AbilityInstanceFields = {
	Caster: Model,
	Data: AbilityData,
	LastCastTime: number,
}

-- Safe type-intersection for strict Metatable-OOP modeling
export type AbilityInstance = typeof(setmetatable({} :: AbilityInstanceFields, SharedAbilityClass))

-- Static immutable cache of raw configurations
local AbilityCache: { [string]: AbilityData } = {}
local AbilitiesFolder = ReplicatedStorage:WaitForChild("AbilitySystem"):WaitForChild("Abilities") :: Folder

-- [[ DEPENDENCY INJECTION MATRIX ]]
-- Solves circular dependencies cleanly by providing a setter pointer framework
local ServerSilenceCheckHandler: ((player: Player) -> boolean)? = nil
local ClientSilenceZonesFolder: Folder? = nil

if RunService:IsClient() then
	-- Pre-allocate or locate dedicated folder to avoid workspace:GetChildren() linear sweeps
	task.spawn(function()
		ClientSilenceZonesFolder = workspace:WaitForChild("ActiveSilenceFields", 10) :: Folder?
	end)
end

function SharedAbilityClass.RegisterServerSilenceHandler(handler: (player: Player) -> boolean)
	if RunService:IsServer() then
		ServerSilenceCheckHandler = handler
	end
end

-- [[ PRIVATE CONFIGURATION PARSER ]]
local function getAbilityData(abilityName: string): AbilityData?
	local cached = AbilityCache[abilityName]
	if cached then return cached end

	local module = AbilitiesFolder:FindFirstChild(abilityName)
	if module and module:IsA("ModuleScript") then
		local data = require(module) :: any

		if type(data) == "table" then
			data.Name = data.Name or abilityName
			data.Cooldown = tonumber(data.Cooldown) or 2.0
			data.EnergyCost = tonumber(data.EnergyCost) or 0

			table.freeze(data)

			local cleanData = data :: AbilityData
			AbilityCache[abilityName] = cleanData
			return cleanData
		end
	end
	return nil
end

-- [[ CONSTRUCTOR ]]
function SharedAbilityClass.new(caster: Model, abilityName: string): AbilityInstance?
	local data = getAbilityData(abilityName)
	if not data then return nil end

	local self = setmetatable({
		Caster = caster,
		Data = data,
		LastCastTime = 0
	}, SharedAbilityClass)

	return self
end

-- [[ CORE UTILITIES ]]

function SharedAbilityClass.GetRemainingCooldown(self: AbilityInstance): number
	local elapsed = workspace:GetServerTimeNow() - self.LastCastTime
	return math.max(0, self.Data.Cooldown - elapsed)
end

function SharedAbilityClass.CanCast(self: AbilityInstance): boolean
	local character = self.Caster
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	-- Cooldown Tolerance Guard
	if SharedAbilityClass.GetRemainingCooldown(self) > 0.05 then return false end

	local data = self.Data
	local currentEnergy = character:GetAttribute("Energy")
	local energyVal = if typeof(currentEnergy) == "number" then currentEnergy else 100
	if energyVal < data.EnergyCost then return false end

	-- State Matrix Attributes Checks
	if character:GetAttribute("IsStunned") == true then return false end
	if data.IsChanneled and character:GetAttribute("IsCasting") == true then return false end
	if data.IsMobility and character:GetAttribute("IsRooted") == true then return false end

	if data.IsMagic then
		local isSilenced = false

		if RunService:IsServer() then
			if ServerSilenceCheckHandler then
				local player = game:GetService("Players"):GetPlayerFromCharacter(character)
				if player then
					isSilenced = ServerSilenceCheckHandler(player)
				end
			end
		else
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp and ClientSilenceZonesFolder then
				local playerPos = hrp.Position
				local activeZones = ClientSilenceZonesFolder:GetChildren()

				for i = 1, #activeZones do
					local part = activeZones[i]
					if part:IsA("BasePart") then
						-- Power-of-two radius check optimization removes square root math performance spikes
						local radius = part.Size.Y * 0.5
						local deltaX = playerPos.X - part.Position.X
						local deltaY = playerPos.Y - part.Position.Y
						local deltaZ = playerPos.Z - part.Position.Z
						local sqrDistance = (deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ)

						if sqrDistance <= (radius * radius) then
							isSilenced = true
							break
						end
					end
				end
			end
		end

		if isSilenced then return false end
	end

	return true
end

-- [[ FRAMEWORK ROUTERS ]]

function SharedAbilityClass.LocalActivate(self: AbilityInstance, targetData: any)
	if not RunService:IsClient() then return end

	self.LastCastTime = workspace:GetServerTimeNow()
	local data = self.Data
	if data.ClientCast then
		data.ClientCast(self.Caster, targetData)
	end
end

function SharedAbilityClass.ServerActivate(self: AbilityInstance, targetData: any)
	if not RunService:IsServer() then return end
	if not SharedAbilityClass.CanCast(self) then return end

	local data = self.Data
	local currentEnergy = self.Caster:GetAttribute("Energy")
	local energyVal = if typeof(currentEnergy) == "number" then currentEnergy else 100

	self.Caster:SetAttribute("Energy", energyVal - data.EnergyCost)
	self.LastCastTime = workspace:GetServerTimeNow()

	if data.ServerExecute then
		data.ServerExecute(self.Caster, targetData)
	end
end

return SharedAbilityClass