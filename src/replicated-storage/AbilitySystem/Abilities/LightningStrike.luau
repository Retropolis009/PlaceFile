--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.LightningStrike
local LightningStrike = {
	Name = "LightningStrike",
	Cooldown = 5.0,
	EnergyCost = 35,

	-- ENGINE CONFIGURATION KEYS
	IconAssetId = "rbxassetid://889150171",
	TargetType = "MousePosition",

	-- Category Flags for high-performance O(1) state verification
	IsMagic = true,
	IsChanneled = false,
}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Infrastructure Cache
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("RemoteEvents")
local networkHandler = remoteEvents:WaitForChild("NetworkHandler") :: RemoteEvent
local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

-- [[ TOP-LEVEL CACHED ENVIRONMENT CONSTANTS ]]
local LocalPlayer = RunService:IsClient() and Players.LocalPlayer or nil

-- Configuration Constants
local CAST_DURATION = 0.25   -- Caster animation frame lock duration
local MAX_RANGE = 80         -- Max operational casting distance in studs
local LIGHTNING_DAMAGE = 30
local HITBOX_RADIUS = 4      -- Radius of the splash hitbox at the strike location

local CAST_ANIMATION_ID = "rbxassetid://0" 

-- ==========================================
-- [[ LOCAL HIGH-PERFORMANCE VFX UTILITY ]]
-- ==========================================
local function createLightningBoltVFX(originPos: Vector3, targetPos: Vector3, assetFolder: Folder?)
	if not RunService:IsClient() then return end

	if not assetFolder then
		warn("[Lightning VFX Error] Asset folder is NIL during effect generation!")
		return
	end

	local vfxTemplate = assetFolder:FindFirstChild("VFX") :: BasePart?
	if not vfxTemplate then
		warn(string.format("[VFX System Error] Missing standardized 'VFX' template part inside folder: %s", assetFolder.Name))
		return
	end

	local vfxHolder = vfxTemplate:Clone()
	vfxHolder.Name = "ActiveVFXHolder"
	vfxHolder.CanCollide = false
	vfxHolder.CanTouch = false
	vfxHolder.CanQuery = false
	vfxHolder.Anchored = true
	vfxHolder.Transparency = 1 

	vfxHolder.CFrame = CFrame.new((originPos + targetPos) / 2)
	vfxHolder.Parent = workspace

	local lightningAttachment = vfxHolder:FindFirstChild("Lightning") :: Attachment?
	local mainAttachment = vfxHolder:FindFirstChild("Main") :: Attachment?

	if lightningAttachment then lightningAttachment.WorldPosition = originPos end
	if mainAttachment then mainAttachment.WorldPosition = targetPos end

	local beam = vfxHolder:FindFirstChildOfClass("Beam")
	if beam and lightningAttachment and mainAttachment then
		beam.Attachment0 = lightningAttachment
		beam.Attachment1 = mainAttachment
		beam.Enabled = true
	end

	for _, descendant in ipairs(vfxHolder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			local emitCount = descendant:GetAttribute("EmitCount") or 25
			descendant:Emit(emitCount)
		end
	end

	-- ==========================================
	-- [[ PROXIMITY SHOCKWAVE & IMPACT FRAME ]]
	-- ==========================================
	local myCharacter = LocalPlayer and LocalPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if myRoot then
		local distance = (myRoot.Position - targetPos).Magnitude
		-- Proximity limit: 4x the hitbox radius
		if distance <= HITBOX_RADIUS * 10 then
			local distanceScale = math.clamp(1 - (distance / (HITBOX_RADIUS * 4)), 0.1, 1)
			local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects) 

			-- 1. Blinding Impact Frame: Pure stark white flash, ultra-low opacity backdrop, evaporates instantly (0.08s)
			CameraEffects.FlashColor(Color3.fromRGB(255, 255, 255), 0.08, 0.9 * distanceScale)

			-- 2. Kinetic Shockwave: High intensity (3.5), ultra-high frequency (45), short duration (0.12s)
			-- This creates an instant "crack" sensation instead of a loose rumble
			CameraEffects.Shake(3.5 * distanceScale, 0.12, 45)
		end
	end

	task.delay(0.3, function()
		if not vfxHolder or not vfxHolder.Parent then return end
		if beam then beam.Enabled = false end

		for _, descendant in ipairs(vfxHolder:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then descendant.Enabled = false end
		end

		Debris:AddItem(vfxHolder, 2.0)
	end)
end

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================

function LightningStrike.OnClientCast(caster: Model, data: any, assetFolder: Folder?)
	local liveCaster = caster or (data and type(data) == "table" and data.Caster)
	if not liveCaster then return end

	local rootPart = liveCaster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = liveCaster:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	-- Animation Execution Frame
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animInstance = Instance.new("Animation")
		animInstance.AnimationId = CAST_ANIMATION_ID
		local success, track = pcall(function() return animator:LoadAnimation(animInstance) end)
		if success and track then
			track:Play()
			task.delay(CAST_DURATION, function() track:Stop() animInstance:Destroy() end)
		else
			animInstance:Destroy()
		end
	end

	-- Pick up positions directly from server calculation variables
	local targetPosition = data and type(data) == "table" and data.TargetPosition :: Vector3
	if not targetPosition then return end

	local originPos = rootPart.Position + Vector3.new(0, 5, 0)
	createLightningBoltVFX(originPos, targetPosition, assetFolder)
end

function LightningStrike.OnImpactReceived(data: any, assetFolder: Folder?)
	local target: Vector3? = nil
	local origin: Vector3? = nil

	if type(data) == "table" then
		target = data.TargetPosition or data.Position or data.TargetData
		origin = data.OriginPosition or (data.Caster and data.Caster:FindFirstChild("HumanoidRootPart") and data.Caster.HumanoidRootPart.Position + Vector3.new(0,5,0))
	elseif typeof(data) == "Vector3" then
		target = data
	end

	if target then
		local trueOrigin = origin or (target + Vector3.new(0, 50, 0))
		createLightningBoltVFX(trueOrigin, target, assetFolder)
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function LightningStrike.ServerExecute(caster: Model, targetData: any)
	local inputTargetPos: Vector3? = nil

	if typeof(targetData) == "Vector3" then
		inputTargetPos = targetData
	elseif type(targetData) == "table" then
		inputTargetPos = targetData.TargetPosition or targetData.Position or targetData.TargetData
	end

	if not inputTargetPos then return end

	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	caster:SetAttribute("IsCasting", true)
	task.delay(CAST_DURATION, function()
		if caster and caster.Parent then caster:SetAttribute("IsCasting", nil) end
	end)

	local originPos = rootPart.Position + Vector3.new(0, 5, 0)

	-- Step 1: Raycast hits something or reaches max range to define hit location
	local rawRayDirection = (inputTargetPos - originPos)
	local clampedLength = math.min(rawRayDirection.Magnitude, MAX_RANGE)
	local realRayDirection = rawRayDirection.Unit * clampedLength

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { caster }

	local initialResult = workspace:Raycast(originPos, realRayDirection, raycastParams)
	local rawHitPos = initialResult and initialResult.Position or (originPos + realRayDirection)

	-- Terrain Tracking / Dropdown Map Snapping
	local absoluteImpactPos = rawHitPos
	if not initialResult then
		local groundResult = workspace:Raycast(rawHitPos + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), raycastParams)
		if groundResult then
			absoluteImpactPos = groundResult.Position
		end
	end

	-- Step 2: Replicate cast visual instructions directly to all rendering engines
	local networkPayload = {
		Caster = caster,
		TargetPosition = absoluteImpactPos
	}
	replicateVFXRemote:FireAllClients("LightningStrike", "Cast", networkPayload)

	-- Steps 3 & 4: Hitbox created -> Damage dealt -> Hitbox removed instantly
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { caster }

	local partsInExplosion = workspace:GetPartBoundsInRadius(absoluteImpactPos, HITBOX_RADIUS, overlapParams)
	local hitHumanoids: { [Humanoid]: boolean } = {}

	for i = 1, #partsInExplosion do
		local part = partsInExplosion[i]
		local targetModel = part.Parent

		if targetModel and targetModel:IsA("Model") then
			local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not hitHumanoids[humanoid] then
				hitHumanoids[humanoid] = true

				humanoid:TakeDamage(LIGHTNING_DAMAGE)
				print(string.format("⚡ [Lightning Hit] Inflicted %d damage to %s", LIGHTNING_DAMAGE, targetModel.Name))
			end
		end
	end

	-- Dispatch impact payload assets immediately
	local impactPayload = {
		OriginPosition = originPos,
		TargetPosition = absoluteImpactPos
	}
	replicateVFXRemote:FireAllClients("LightningStrike", "Impact", impactPayload)
end

function LightningStrike:ServerActivate(targetData: any)
	local characterInstance = nil
	if type(self) == "table" then
		characterInstance = self.Character or self.instance
	end

	if characterInstance and typeof(characterInstance) == "Instance" and characterInstance:IsA("Model") then
		LightningStrike.ServerExecute(characterInstance, targetData)
	end
end

function LightningStrike:GetEnergyCost(): number
	return LightningStrike.EnergyCost
end

function LightningStrike:GetCooldownDuration(): number
	return LightningStrike.Cooldown
end

function LightningStrike:CanCast(): boolean
	return true
end

return LightningStrike