--!strict
-- StarterPlayer.StarterPlayerScripts.VFXManager
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Infrastructure Access & Network Channels
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("RemoteEvents")
local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

-- Asset Hierarchy Discovery Pointers
local AbilitySystem = ReplicatedStorage:WaitForChild("AbilitySystem")
local AbilitiesFolder = AbilitySystem:WaitForChild("Abilities") :: Folder
local VisualSystem = AbilitySystem:WaitForChild("VisualSystem") :: Folder

-- Cache LocalPlayer at top-level (Guaranteed to exist inside StarterPlayerScripts)
local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: Player

-- [[ HIGH-PERFORMANCE STATIC CACHE MATRIX ]]
type CachedVFXModule = {
	CastMethod: ((caster: Model, data: any, assetFolder: Folder?) -> ())?,
	ImpactMethod: ((data: any, assetFolder: Folder?) -> ())?,
	AssetFolder: Folder?,
	IsValid: boolean
}
local ModuleCacheMatrix: { [string]: CachedVFXModule } = {}

-- Helper to safely resolve and cache script objects and asset folders once
local function getOrCacheModule(abilityName: string): CachedVFXModule
	local cached = ModuleCacheMatrix[abilityName]
	if cached then return cached end

	local record: CachedVFXModule = {
		CastMethod = nil,
		ImpactMethod = nil,
		AssetFolder = VisualSystem:FindFirstChild(abilityName) :: Folder?,
		IsValid = false
	}

	local spellScript = AbilitiesFolder:FindFirstChild(abilityName)
	if spellScript and spellScript:IsA("ModuleScript") then
		local success, rawModule = pcall(require, spellScript)
		if success and typeof(rawModule) == "table" then
			record.CastMethod = rawModule["OnClientCast"] or rawModule["ClientCast"]
			record.ImpactMethod = rawModule["OnImpactReceived"] or rawModule["OnImpact"]
			record.IsValid = true
		end
	end

	ModuleCacheMatrix[abilityName] = record
	return record
end

-- [[ CENTRAL NETWORK TRAFFIC ROUTER ]]
replicateVFXRemote.OnClientEvent:Connect(function(abilityName: string, phaseType: string, data: any)
	if not abilityName or not phaseType then return end

	local vfxRecord = getOrCacheModule(abilityName)
	if not vfxRecord.IsValid then return end

	-- [[ ROUTING AND EXECUTION LAYER ]]
	if phaseType == "Cast" then
		local castMethod = vfxRecord.CastMethod
		if castMethod then
			local casterModel: Model? = if typeof(data) == "table" then data.Caster else nil
			if not casterModel then
				casterModel = LocalPlayer.Character
			end

			if casterModel then
				task.spawn(castMethod, casterModel, data, vfxRecord.AssetFolder)
			end
		end

	elseif phaseType == "Impact" then
		local impactMethod = vfxRecord.ImpactMethod
		if impactMethod then
			task.spawn(impactMethod, data, vfxRecord.AssetFolder)
		end
	end
end)