--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.EarthShaker
local EarthShaker = {
	Name = "EarthShaker",
	Cooldown = 8.0,
	EnergyCost = 50,

	-- ENGINE CONFIGURATION KEYS
	IconAssetId = "rbxassetid://16435644296", 
	TargetType = "Self",

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
local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

-- Configuration Constants
local TOTAL_DURATION = 4.0      -- Complete channel freeze lock window
local EFFECT_RADIUS = 30        -- Radial distance of ground blast area
local BASE_DAMAGE = 25          -- Damage dealt per single pulse
local LAUNCH_VELOCITY = 45      -- Vertical force strength applied to targets

local ANIMATION_ID = "rbxassetid://0" -- Assign channeling pose animation asset

-- ==========================================
-- [[ LOCAL HIGH-PERFORMANCE VFX UTILITY ]]
-- ==========================================
local function createEarthQuakeVFX(centerCFrame: CFrame, assetFolder: Folder?)
	if not RunService:IsClient() then return end

	if not assetFolder then
		warn("[EarthShaker VFX Error] Asset folder is NIL during effect generation!")
		return
	end

	local vfxTemplate = assetFolder:FindFirstChild("VFX") :: BasePart?
	if not vfxTemplate then
		warn(string.format("[VFX System Error] Missing standardized 'VFX' template part inside folder: %s", assetFolder.Name))
		return
	end

	-- 1. Clone the structural template
	local vfxHolder = vfxTemplate:Clone()
	vfxHolder.Name = "ActiveEarthShakerVFX"
	vfxHolder.CanCollide = false
	vfxHolder.CanTouch = false
	vfxHolder.CanQuery = false
	vfxHolder.Anchored = true
	vfxHolder.Transparency = 1 

	local originPosition = centerCFrame.Position
	local floorLevelY = originPosition.Y - 3 
	local groundedPosition = Vector3.new(originPosition.X, floorLevelY, originPosition.Z)

	vfxHolder.CFrame = CFrame.new(groundedPosition)
	vfxHolder.Parent = workspace

	for _, child in ipairs(vfxHolder:GetChildren()) do
		if child:IsA("Attachment") then
			child.WorldPosition = groundedPosition
		end
	end

	for _, descendant in ipairs(vfxHolder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			local emitCount = descendant:GetAttribute("EmitCount") or 35
			descendant:Emit(emitCount)
		end
	end

	-- ==========================================
	-- [[ FIXED: ROUTING DIRECTLY VIA MODULE ]]
	-- ==========================================
	if CameraEffects then
		-- 1. Invoke the Camera Shake API pattern directly from your module wrapper
		CameraEffects.Shake(1.8, 0.6, 22)

		-- 2. Invoke the color tint overlay screen effect natively through your module
		CameraEffects.FlashColor(Color3.fromRGB(230, 140, 70), 0.5, 0.3)

		-- 3. Invoke a heavy structural camera tilt roll to sell the impact depth
		CameraEffects.Tilt(4, 0.2)
	end

	-- Lifecycle sweep management
	task.delay(0.5, function()
		if not vfxHolder or not vfxHolder.Parent then return end

		for _, descendant in ipairs(vfxHolder:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			end
		end
		Debris:AddItem(vfxHolder, 2.5)
	end)
end

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================

function EarthShaker.OnClientCast(caster: Model, data: any, assetFolder: Folder?)
	local liveCaster = caster or (data and type(data) == "table" and data.Caster)
	if not liveCaster then return end

	local rootPart = liveCaster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = liveCaster:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	local blastCFrame = (data and type(data) == "table" and data.OriginCFrame) or rootPart.CFrame

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		local animInstance = Instance.new("Animation")
		animInstance.AnimationId = ANIMATION_ID
		local success, track = pcall(function() return animator:LoadAnimation(animInstance) end)
		if success and track then
			track:Play()
			task.delay(TOTAL_DURATION, function() 
				track:Stop() 
				animInstance:Destroy() 
			end)
		else
			animInstance:Destroy()
		end
	end

	print(string.format("[Client VFX] Running Grounded EarthShaker Wave at position: %s", tostring(blastCFrame.Position)))
	createEarthQuakeVFX(blastCFrame, assetFolder)
end

function EarthShaker.OnImpactReceived(data: any, assetFolder: Folder?)
	if data and data.OriginCFrame then
		createEarthQuakeVFX(data.OriginCFrame, assetFolder)
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================

local function executeServerBlastPulse(caster: Model, blastPosition: Vector3)
	local casterPlayer = Players:GetPlayerFromCharacter(caster)

	for _, player in ipairs(Players:GetPlayers()) do
		if player == casterPlayer then continue end 

		local targetChar = player.Character
		local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart") :: Part?
		local targetHumanoid = targetChar and targetChar:FindFirstChildOfClass("Humanoid")

		if targetHrp and targetHumanoid and targetHumanoid.Health > 0 then
			local flatDistance = (Vector3.new(targetHrp.Position.X, blastPosition.Y, targetHrp.Position.Z) - blastPosition).Magnitude

			if flatDistance <= EFFECT_RADIUS then
				targetHumanoid:TakeDamage(BASE_DAMAGE)
				targetHrp.AssemblyLinearVelocity = Vector3.new(targetHrp.AssemblyLinearVelocity.X, LAUNCH_VELOCITY, targetHrp.AssemblyLinearVelocity.Z)
				print(string.format("[Combat Server] EarthShaker hit target: %s | Distance: %.2f studs", player.Name, flatDistance))
			end
		end
	end
end

function EarthShaker.ServerExecute(caster: Model, targetData: any)
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: Part?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	caster:SetAttribute("IsCasting", true)

	local originalWalkSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	local fixedCFrame = rootPart.CFrame
	local fixedPosition = rootPart.Position

	local networkPayload = {
		Caster = caster,
		OriginCFrame = fixedCFrame
	}

	replicateVFXRemote:FireAllClients("EarthShaker", "Cast", networkPayload)
	executeServerBlastPulse(caster, fixedPosition)

	task.delay(TOTAL_DURATION / 2, function()
		if caster and caster.Parent and humanoid and humanoid.Health > 0 then
			print(" [Combat Server] Dispensing second EarthShaker pulse sequence...")
			replicateVFXRemote:FireAllClients("EarthShaker", "Cast", networkPayload)
			executeServerBlastPulse(caster, fixedPosition)
		end
	end)

	task.delay(TOTAL_DURATION, function()
		if caster and caster.Parent and humanoid then
			caster:SetAttribute("IsCasting", nil)
			humanoid.WalkSpeed = originalWalkSpeed
			print(" [Combat Server] EarthShaker channel sequence completed successfully.")
		end
	end)
end

function EarthShaker.VerifyServerHit(casterPlayer: Player, targetPlayer: Player, claimedHitPos: Vector3)
	-- Hits generated directly and evaluated authoritatively on the server.
end

return EarthShaker