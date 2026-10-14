--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.KineticBarrier
local KineticBarrier = {
	Name = "KineticBarrier",
	Cooldown = 6.0,
	EnergyCost = 30,
	IconAssetId = "rbxassetid://99311421053167", 
	TargetType = "Self", 
	IsMagic = true,
}

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RADIUS = 20 
local DURATION = 0.5 
local FORCE_POWER = 65 


function KineticBarrier.ClientCast(caster: Model, _targetData: any, assetFolder: Folder?)
	if not RunService:IsClient() then return end

	-- Drop out silently if this is the local prediction frame
	if not assetFolder then
		return
	end

	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Identify the base 'Barrier' template part
	local vfxTemplate = assetFolder:FindFirstChild("Barrier") 
		or assetFolder:FindFirstChild("VFX") 
		or assetFolder:FindFirstChild("KineticBarrier")

	if not vfxTemplate then
		warn(string.format("[Kinetic Barrier VFX Error] Could not find asset template inside folder: %s", assetFolder.Name))
		return
	end

	-- Clone the template part
	local barrierVFX = vfxTemplate:Clone()

	-- TUNING PARAMETERS FOR VISIBILITY
	local VISUAL_SCALE_MULTIPLIER = 2.5 -- Increase this if you want it even larger!
	local totalDiameter = RADIUS * 2 * VISUAL_SCALE_MULTIPLIER

	-- Calculate an offset CFrame centered exactly on the player, raised up by 1.5 studs 
	-- so the bottom half of the shield sphere isn't clipped through the floor plate.
	local targetCFrame = rootPart.CFrame * CFrame.new(0, 1.5, 0)

	-- Handle sizing and positioning calculations safely
	if barrierVFX:IsA("Model") then
		barrierVFX:ScaleTo(totalDiameter)
		barrierVFX:PivotTo(targetCFrame)
	elseif barrierVFX:IsA("BasePart") then
		barrierVFX.Size = Vector3.new(totalDiameter, totalDiameter, totalDiameter)
		barrierVFX.CFrame = targetCFrame
		barrierVFX.Anchored = true
		barrierVFX.CanCollide = false
		barrierVFX.CastShadow = false -- Prevents the visual mesh from blocking lighting layers
	end

	-- Crucial safety check: Ensure transparency or properties aren't completely hiding it
	if barrierVFX:IsA("BasePart") then
		if barrierVFX.Transparency >= 1 and #barrierVFX:GetChildren() == 0 then
			warn("[VFX Visibility Warning] The Barrier part is completely transparent and contains no sub-particles!")
		end
	end

	barrierVFX.Parent = workspace
	print(string.format("[Kinetic Barrier VFX] Spawned & Centered! Size: %.1f studs.", totalDiameter))

	-- Access and spark all nested particle systems inside the Barrier part hierarchy
	for _, descendant in ipairs(barrierVFX:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			descendant.LockedToPart = false 
			-- Force particles to instantly emit a burst so there's no wind-up delay
			descendant:Emit(15) 
		end
	end

	-- Clean up lifecycle sequence
	task.delay(DURATION, function()
		for _, descendant in ipairs(barrierVFX:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then 
				descendant.Enabled = false 
			end
		end
		Debris:AddItem(barrierVFX, 2)
	end)
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function KineticBarrier.ServerExecute(caster: Model, targetData: any)
	print(string.format("[Server Execute] Shockwave push active for caster: %s", caster.Name))

	-- [[ PIPELINE FIX: Tell the VFXManager to render this for everyone ]]
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remoteEvents = remotes:WaitForChild("RemoteEvents")
	local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

	replicateVFXRemote:FireAllClients("KineticBarrier", "Cast", { Caster = caster })

	local humanoidRootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then return end
	local originPosition = humanoidRootPart.Position

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {caster}

	local partsInRange = workspace:GetPartBoundsInRadius(originPosition, RADIUS, overlapParams)
	local processedMechanics: { [Instance]: boolean } = {}

	for _, part in ipairs(partsInRange) do
		local character = part.Parent
		if character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
			local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local targetHumanoid = character:FindFirstChildOfClass("Humanoid")

			if targetRoot and targetHumanoid and not processedMechanics[character] then
				processedMechanics[character] = true

				character:SetAttribute("IsCasting", nil)
				character:SetAttribute("IsStunned", true)
				character:SetAttribute("IsRooted", true)

				task.delay(DURATION, function()
					if character and character.Parent then
						character:SetAttribute("IsStunned", nil)
						character:SetAttribute("IsRooted", nil)
					end
				end)

				local direction = (targetRoot.Position - originPosition)
				local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
				horizontalDirection = horizontalDirection.Magnitude == 0 and humanoidRootPart.CFrame.LookVector or horizontalDirection.Unit

				targetHumanoid:ChangeState(Enum.HumanoidStateType.Physics)

				local attachment = Instance.new("Attachment")
				attachment.Name = "KineticPushAttachment"
				attachment.Parent = targetRoot

				local linearVelocity = Instance.new("LinearVelocity")
				linearVelocity.Name = "KineticVelocityMover"
				linearVelocity.MaxForce = 999999
				linearVelocity.VectorVelocity = (horizontalDirection * FORCE_POWER) + Vector3.new(0, 15, 0)
				linearVelocity.Attachment0 = attachment
				linearVelocity.Parent = targetRoot 

				Debris:AddItem(attachment, DURATION)
				Debris:AddItem(linearVelocity, DURATION)
			end
		elseif part:IsA("BasePart") and not part.Anchored then
			local assemblyRoot = part.AssemblyRootPart
			if assemblyRoot and not assemblyRoot.Anchored and not processedMechanics[assemblyRoot] then
				processedMechanics[assemblyRoot] = true
				local objectDirection = (assemblyRoot.Position - originPosition)
				local cleanDirection = objectDirection.Magnitude > 0 and objectDirection.Unit or Vector3.new(0, 1, 0)
				assemblyRoot:ApplyImpulse((cleanDirection * FORCE_POWER) * assemblyRoot:GetMass())
			end
		end
	end
end

return KineticBarrier