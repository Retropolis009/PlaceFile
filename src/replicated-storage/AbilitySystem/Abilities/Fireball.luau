--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.Fireball
local Fireball = {
	Name = "Fireball",
	Cooldown = 3.0,
	EnergyCost = 25,

	-- ENGINE CONFIGURATION KEYS
	IconAssetId = "rbxassetid://76698859141069",
	TargetType = "MouseDirection",

	-- Category Flags for high-performance O(1) state verification
	IsMagic = true,
	IsChanneled = true,
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
local CAST_DURATION = 0.4   -- How long the caster is locked in the casting state animation frame
local PROJECTILE_SPEED = 80 -- Studs per second
local PROJECTILE_RANGE = 120 -- Max distance in studs
local FIREBALL_DAMAGE = 25
local EXPLOSION_RADIUS = 8  -- Radius of the explosion splash when it intersects

local CAST_ANIMATION_ID = "rbxassetid://0" 

-- ==========================================
-- [[ LOCAL HIGH-PERFORMANCE VFX UTILITY ]]
-- ==========================================
local function createImpactExplosionVFX(position: Vector3, assetFolder: Folder?)
	if not RunService:IsClient() then return end

	if not assetFolder then
		warn(" [Fireball VFX Error] Asset folder is NIL during impact execution!")
		return
	end

	local explosionTemplate = assetFolder:FindFirstChild("Explosion") or assetFolder:FindFirstChild("VFX")
	if not explosionTemplate then return end

	local blastZone = explosionTemplate:Clone()

	if blastZone:IsA("Model") then
		blastZone:PivotTo(CFrame.new(position))
	elseif blastZone:IsA("BasePart") then
		blastZone.Position = position
		blastZone.CanCollide = false
		blastZone.Anchored = true
	end

	blastZone.Parent = workspace

	for _, descendant in ipairs(blastZone:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			descendant.LockedToPart = false 
			descendant:Emit(descendant:GetAttribute("EmitCount") or 20) 
		end
	end

	-- ==========================================
	-- [[ CAMERA IMPACT PIPELINE ]]
	-- ==========================================
	local myCharacter = LocalPlayer and LocalPlayer.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if myRoot then
		local distance = (myRoot.Position - position).Magnitude
		-- Only shake and flash if the player is within visual range of the explosion
		if distance <= EXPLOSION_RADIUS * 4 then
			local distanceScale = math.clamp(1 - (distance / (EXPLOSION_RADIUS * 4)), 0.1, 1)
			local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

			-- Heavy impact explosion rattle
			CameraEffects.Shake(2.2 * distanceScale, 0.4, 25)

			-- Bright white/yellow heat blast flash
			CameraEffects.FlashColor(Color3.fromRGB(255, 230, 180), 0.35, 0.4 * distanceScale)
		end
	end

	task.delay(0.5, function()
		if not blastZone or not blastZone.Parent then return end
		for _, descendant in ipairs(blastZone:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			end
		end
		Debris:AddItem(blastZone, 2)
	end)
end

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================

function Fireball.OnClientCast(caster: Model, data: { [string]: any }, assetFolder: Folder?)
	if not assetFolder then return end

	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	local travelDirection = data.TargetDirection :: Vector3
	if not travelDirection or travelDirection.Magnitude == 0 then return end
	local normalDirection = travelDirection.Unit

	-- Animation Execution
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animInstance = Instance.new("Animation")
		animInstance.AnimationId = CAST_ANIMATION_ID
		local success, track = pcall(function() return animator:LoadAnimation(animInstance) end)
		if success and track then
			track:Play()
			task.delay(CAST_DURATION, function()
				track:Stop()
				animInstance:Destroy()
			end)
		else
			animInstance:Destroy()
		end
	end

	-- ==========================================
	-- [[ CAMERA CASTING KICKBACK ]]
	-- ==========================================
	if LocalPlayer and caster == LocalPlayer.Character then
		local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

		-- 1. Minor lens punch back
		CameraEffects.ZoomTo(74, 0.05, Enum.EasingStyle.Quad)
		task.delay(0.05, function()
			CameraEffects.ResetZoom(0.15)
		end)

		-- 2. Clean muzzle flash: High transparency (0.75), ultra-fast fade (0.1s)
		CameraEffects.FlashColor(Color3.fromRGB(255, 120, 30), 0.1, 0.75)

		-- 3. Sharp recoil vibration
		CameraEffects.Shake(0.6, 0.1, 35)
	end

	local ballTemplate = assetFolder:FindFirstChild("Ball") or assetFolder:FindFirstChild("Projectile")
	if not ballTemplate then return end

	local ball = ballTemplate:Clone()
	local spawnPosition = rootPart.Position + (normalDirection * 5)

	if ball:IsA("Model") then
		local primary = ball.PrimaryPart or ball:FindFirstChildWhichIsA("BasePart")
		if primary then primary.CanCollide = false end
		ball:PivotTo(CFrame.lookAt(spawnPosition, spawnPosition + normalDirection))
	elseif ball:IsA("BasePart") then
		ball.CanCollide = false        
		ball.Massless = true           
		ball.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + normalDirection)
	end

	local physicsRoot = (ball:IsA("Model") and ball.PrimaryPart) or (ball:IsA("BasePart") and ball) :: BasePart?
	if not physicsRoot then return end

	local targetVelocity = normalDirection * PROJECTILE_SPEED
	physicsRoot.AssemblyLinearVelocity = targetVelocity 

	local attachment = Instance.new("Attachment")
	attachment.Parent = physicsRoot

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = targetVelocity
	linearVelocity.MaxForce = math.huge 
	linearVelocity.Parent = physicsRoot

	for _, descendant in ipairs(ball:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			descendant.LockedToPart = false
		end
	end

	ball.Parent = workspace

	local finalImpactPos = data.ImpactPosition :: Vector3?
	local flightDuration = PROJECTILE_RANGE / PROJECTILE_SPEED

	if finalImpactPos then
		flightDuration = (finalImpactPos - spawnPosition).Magnitude / PROJECTILE_SPEED
	end

	Debris:AddItem(ball, flightDuration)

	task.delay(flightDuration, function()
		if not ball or not ball.Parent then return end

		if ball:IsA("BasePart") then
			ball.Transparency = 1
		else
			for _, child in ipairs(ball:GetDescendants()) do
				if child:IsA("BasePart") then child.Transparency = 1 end
			end
		end

		local velocityConstraint = physicsRoot:FindFirstChildOfClass("LinearVelocity")
		if velocityConstraint then velocityConstraint:Destroy() end
		physicsRoot.AssemblyLinearVelocity = Vector3.zero

		for _, descendant in ipairs(ball:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then descendant.Enabled = false end
		end
		Debris:AddItem(ball, 0.05)
	end)
end

function Fireball.OnImpactReceived(data: { [string]: any }, assetFolder: Folder?)
	local position = data.Position :: Vector3
	if position then createImpactExplosionVFX(position, assetFolder) end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function Fireball.ServerExecute(caster: Model, targetData: any)
	local travelDirection: Vector3? = nil

	if typeof(targetData) == "Vector3" then
		travelDirection = targetData.Unit
	elseif type(targetData) == "table" then
		local extractedVector = targetData.TargetDirection or targetData.Direction
		if typeof(extractedVector) == "Vector3" then travelDirection = extractedVector.Unit end
	end

	if not travelDirection or travelDirection.Magnitude == 0 then return end

	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	caster:SetAttribute("IsCasting", true)
	task.delay(CAST_DURATION, function()
		if caster and caster.Parent then caster:SetAttribute("IsCasting", nil) end
	end)

	local spawnPosition = rootPart.Position + (travelDirection * 5)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { caster }

	local raycastResult = workspace:Raycast(spawnPosition, travelDirection * PROJECTILE_RANGE, raycastParams)
	local absoluteImpactPos = raycastResult and raycastResult.Position or (spawnPosition + (travelDirection * PROJECTILE_RANGE))

	local castPayload = {
		Caster = caster,
		TargetDirection = travelDirection,
		ImpactPosition = absoluteImpactPos
	}
	replicateVFXRemote:FireAllClients("Fireball", "Cast", castPayload)

	local flightDistance = (absoluteImpactPos - spawnPosition).Magnitude
	local travelTime = flightDistance / PROJECTILE_SPEED

	task.delay(travelTime, function()
		if not workspace then return end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { caster }

		local partsInExplosion = workspace:GetPartBoundsInRadius(absoluteImpactPos, EXPLOSION_RADIUS, overlapParams)
		local hitHumanoids: { [Humanoid]: boolean } = {}

		for i = 1, #partsInExplosion do
			local part = partsInExplosion[i]
			local targetModel = part.Parent

			if targetModel and targetModel:IsA("Model") then
				local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and not hitHumanoids[humanoid] then
					hitHumanoids[humanoid] = true

					humanoid:TakeDamage(FIREBALL_DAMAGE)
					print(string.format(" [Fireball Hit] Inflicted %d damage to %s", FIREBALL_DAMAGE, targetModel.Name))
				end
			end
		end

		local impactPayload = { Position = absoluteImpactPos }
		replicateVFXRemote:FireAllClients("Fireball", "Impact", impactPayload)
	end)
end

function Fireball:ServerActivate(targetData: any)
	local characterInstance = nil
	if type(self) == "table" then
		characterInstance = self.Character or self.instance
	end

	if characterInstance and typeof(characterInstance) == "Instance" and characterInstance:IsA("Model") then
		Fireball.ServerExecute(characterInstance, targetData)
	end
end

function Fireball:GetEnergyCost(): number
	return Fireball.EnergyCost
end

function Fireball:GetCooldownDuration(): number
	return Fireball.Cooldown
end

function Fireball:CanCast(): boolean
	return true
end

return Fireball