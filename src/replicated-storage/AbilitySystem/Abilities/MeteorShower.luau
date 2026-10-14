--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.MeteorShower
local MeteorShower = {
	Name = "MeteorShower",
	Cooldown = 12.0,
	EnergyCost = 60,

	-- ENGINE CONFIGURATION KEYS
	IconAssetId = "rbxassetid://8601202264",
	TargetType = "Self",

	-- Category Flags for high-performance O(1) state verification
	IsMagic = true,
	IsChanneled = true,
}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Infrastructure Cache
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("RemoteEvents")
local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

-- [[ TOP-LEVEL CACHED ENVIRONMENT CONSTANTS ]]
local LocalPlayer = RunService:IsClient() and Players.LocalPlayer or nil

-- Configuration Constants
local CHANNEL_DURATION = 5.0    -- How long the player is locked channeling
local TOTAL_METEORS = 12        -- Amount of meteors dropped during the channel
local FORWARD_DISTANCE = 35     -- Center point distance of the zone in front of player
local ZONE_RADIUS = 50          -- Scale of the randomized spread zone area
local EXPLOSION_RADIUS = 12     -- Damage radius per meteor impact
local METEOR_DAMAGE = 20        -- Damage per single meteor hit
local METEOR_FALL_SPEED = 0.5   -- Time in seconds it takes a meteor to fall from sky

local ANIMATION_ID = "rbxassetid://0" -- Assign channeling loop animation

-- ==========================================
-- [[ LOCAL HIGH-PERFORMANCE VFX UTILITY ]]
-- ==========================================

local function createMeteorFallingVFX(targetPos: Vector3, assetFolder: Folder?)
	if not RunService:IsClient() or not assetFolder then return end

	local meteorTemplate = assetFolder:FindFirstChild("VFX") :: BasePart?
	local explosionTemplate = assetFolder:FindFirstChild("Explosion") :: BasePart?

	if not meteorTemplate or not explosionTemplate then
		warn("[Meteor System Error] Missing 'Meteor' or 'Explosion' template base part inside asset folder!")
		return
	end

	-- 1. Setup Falling Meteor Object
	local meteor = meteorTemplate:Clone()
	meteor.CanCollide = false
	meteor.CanTouch = false
	meteor.CanQuery = false
	meteor.Anchored = true

	-- Spawn high above the target position with a slight horizontal drift offset
	local skySpawnPos = targetPos + Vector3.new(-10, 60, -10)
	meteor.CFrame = CFrame.lookAt(skySpawnPos, targetPos)
	meteor.Parent = workspace

	-- Turn on any ambient fire/trail particle systems inside the meteor asset
	for _, descendant in ipairs(meteor:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
		end
	end

	-- 2. Tween Meteor downwards to simulate a high-speed orbital drop
	local tweenInfo = TweenInfo.new(METEOR_FALL_SPEED, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tween = TweenService:Create(meteor, tweenInfo, {Position = targetPos})
	tween:Play()

	-- 3. Detonation Phase upon arrival
	tween.Completed:Connect(function()
		meteor:Destroy() -- Clean up projectile mesh asset

		-- Clone impact explosion template
		local explosionVFX = explosionTemplate:Clone()
		explosionVFX.CanCollide = false
		explosionVFX.CanTouch = false
		explosionVFX.CanQuery = false
		explosionVFX.Anchored = true
		explosionVFX.CFrame = CFrame.new(targetPos)
		explosionVFX.Parent = workspace

		-- Move internal attachments cleanly to ground level coordinates
		for _, child in ipairs(explosionVFX:GetChildren()) do
			if child:IsA("Attachment") then
				child.WorldPosition = targetPos
			end
		end

		-- Trigger all explosion wave particle systems
		for _, descendant in ipairs(explosionVFX:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = true
				local emitCount = descendant:GetAttribute("EmitCount") or 30
				descendant:Emit(emitCount)
			end
		end

		-- ==========================================
		-- [[ PROXIMITY METEOR IMPACT THUD ]]
		-- ==========================================
		local myCharacter = LocalPlayer and LocalPlayer.Character
		local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

		if myRoot then
			local distance = (myRoot.Position - targetPos).Magnitude
			local maxImpactRange = ZONE_RADIUS + 20 -- Visually responsive even at edge boundaries

			if distance <= maxImpactRange then
				local distanceScale = math.clamp(1 - (distance / maxImpactRange), 0.1, 1)
				local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

				-- Swift directional ground thump: Heavy intensity (4.0), short duration (0.15s), medium frequency
				CameraEffects.Shake(4.0 * distanceScale, 0.15, 22)
			end
		end

		-- Smooth decay cleanup cycle
		task.delay(0.4, function()
			if not explosionVFX or not explosionVFX.Parent then return end
			for _, descendant in ipairs(explosionVFX:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") then
					descendant.Enabled = false
				end
			end
			Debris:AddItem(explosionVFX, 2.0)
		end)
	end)
end

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================

function MeteorShower.OnClientCast(caster: Model, data: any, assetFolder: Folder?)
	local liveCaster = caster or (data and type(data) == "table" and data.Caster)
	if not liveCaster then return end

	local humanoid = liveCaster:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Trigger looped channeling body pose animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animInstance = Instance.new("Animation")
		animInstance.AnimationId = ANIMATION_ID
		local success, track = pcall(function() return animator:LoadAnimation(animInstance) end)
		if success and track then
			track:Play()
			task.delay(CHANNEL_DURATION, function() track:Stop() animInstance:Destroy() end)
		else
			animInstance:Destroy()
		end
	end

	-- ==========================================
	-- [[ CHANNEL CINEMATIC FOCUS TACTICAL VIEW ]]
	-- ==========================================
	if LocalPlayer and liveCaster == LocalPlayer.Character then
		local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

		-- 1. Tactical View: Expand FOV out to 82 smoothly over 0.5s to display entire sector grid
		CameraEffects.ZoomTo(82, 0.5, Enum.EasingStyle.Cubic)

		-- 2. Environmental Ambient Tremble: Continuous structural ground rumbling over 5 seconds
		-- Low intensity (0.65), ultra high frequency (50) to simulate geological strain
		CameraEffects.Shake(0.65, CHANNEL_DURATION, 50)

		-- 3. Snap viewport back down gracefully when the channel concludes
		task.delay(CHANNEL_DURATION, function()
			CameraEffects.ResetZoom(0.4)
		end)
	end
end

function MeteorShower.OnImpactReceived(data: any, assetFolder: Folder?)
	if data and data.TargetPosition then
		createMeteorFallingVFX(data.TargetPosition, assetFolder)
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================

local function executeServerMeteorStrike(caster: Model, targetPos: Vector3)
	local casterPlayer = Players:GetPlayerFromCharacter(caster)

	for _, player in ipairs(Players:GetPlayers()) do
		if player == casterPlayer then continue end

		local targetChar = player.Character
		local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: Part?
		local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")

		if targetHrp and targetHumanoid and targetHumanoid.Health > 0 then
			local distance = (Vector3.new(targetHrp.Position.X, targetPos.Y, targetHrp.Position.Z) - targetPos).Magnitude
			if distance <= EXPLOSION_RADIUS then
				targetHumanoid:TakeDamage(METEOR_DAMAGE)
				print(string.format("Meteor struck target: %s! Damage applied.", player.Name))
			end
		end
	end
end

function MeteorShower.ServerExecute(caster: Model, targetData: any)
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: Part?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	-- 1. Lock character movement states to completely paralyze them mid-channel
	caster:SetAttribute("IsCasting", true)
	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	-- 2. Broadcast Channel Start Visual Packet to all clients for animation cycles
	replicateVFXRemote:FireAllClients("MeteorShower", "Cast", { Caster = caster })

	-- Calculate the forward target focal point using the character's precise Face Look Direction
	local characterPosition = rootPart.Position
	local forwardLookVector = rootPart.CFrame.LookVector

	-- Forward target center coordinate box
	local zoneCenterPoint = characterPosition + (forwardLookVector * FORWARD_DISTANCE)

	-- Establish uniform pace intervals to execute drops evenly across the 5 seconds channel timeline
	local timeBetweenMeteors = CHANNEL_DURATION / TOTAL_METEORS

	-- 3. Launch chronological drop sequencer loop
	task.spawn(function()
		for i = 1, TOTAL_METEORS do
			task.wait(timeBetweenMeteors)

			-- Validation check to verify character safety conditions mid-loop execution
			if not caster or not caster.Parent or not rootPart or humanoid.Health <= 0 then break end

			-- Calculate randomized wide-spread coordinates within the forward sector ring circle
			local randomRadius = math.random() * ZONE_RADIUS
			local randomAngle = math.random() * (math.pi * 2)

			local offsetX = math.cos(randomAngle) * randomRadius
			local offsetZ = math.sin(randomAngle) * randomRadius

			-- Combine forward vectors with target noise offsets
			local meteorTargetPosition = Vector3.new(zoneCenterPoint.X + offsetX, characterPosition.Y - 3, zoneCenterPoint.Z + offsetZ)

			-- Handle surface elevation projection check to snap targets cleanly onto uneven geometry terrains
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {caster}

			local rayResult = workspace:Raycast(meteorTargetPosition + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0), raycastParams)
			if rayResult then
				meteorTargetPosition = rayResult.Position
			end

			-- Dispatch drop data down to replication streams across clients
			replicateVFXRemote:FireAllClients("MeteorShower", "Impact", { TargetPosition = meteorTargetPosition })

			-- Schedule server damage evaluation context matching the visual flight duration speeds
			task.delay(METEOR_FALL_SPEED, function()
				if caster and caster.Parent then
					executeServerMeteorStrike(caster, meteorTargetPosition)
				end
			end)
		end

		-- 4. Channel cycle complete: clean state flags and restore normal movement mechanics
		if caster and caster.Parent and humanoid then
			caster:SetAttribute("IsCasting", nil)
			humanoid.WalkSpeed = originalWalkSpeed
			print("[Server Combat] Meteor Shower channel sequence concluded cleanly.")
		end
	end)
end

function MeteorShower:ServerActivate(targetData: any)
	local characterInstance = nil
	if type(self) == "table" then
		characterInstance = self.Character or self.instance
	end

	if characterInstance and typeof(characterInstance) == "Instance" and characterInstance:IsA("Model") then
		MeteorShower.ServerExecute(characterInstance, targetData)
	end
end

return MeteorShower