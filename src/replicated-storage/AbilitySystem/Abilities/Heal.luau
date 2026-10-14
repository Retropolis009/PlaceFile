--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.Heal
local Heal = {
	Name = "Heal",
	Cooldown = 12.0,
	EnergyCost = 35,
	IconAssetId = "rbxassetid://78311453963149",
	TargetType = "Self", -- Directly informs the InputManager to skip mouse calculations and return Vector3.zero
	IsMagic = true,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

-- Configuration Parameters
local HEAL_AMOUNT = 25
local AURA_DURATION = 1.0 -- How long the buff particles linger on the character model

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================
function Heal.ClientCast(caster: Model?, data: any, assetFolder: Folder?)
	if not RunService:IsClient() then return end
	if not caster or not assetFolder then return end

	local phase = typeof(data) == "table" and data.Phase or "Apply"

	-- ------------------------------------------
	-- PHASE A: APPLY ATTACHMENT & PARTICLE VFX BLANKET
	-- ------------------------------------------
	if phase == "Apply" then
		-- Avoid stacking visual overlaps if they are rapidly healed
		if caster:GetAttribute("HasHealVisualActive") then return end
		caster:SetAttribute("HasHealVisualActive", true)

		local blueprintModel = assetFolder:FindFirstChild("VFX") or assetFolder:FindFirstChild("HealVisual")
		if not blueprintModel or not blueprintModel:IsA("Model") then
			warn(string.format(" [Heal VFX Error] Missing reference blueprint VFX model inside asset folder: %s", assetFolder.Name))
			return
		end

		local attachmentMap: { [Attachment]: Attachment } = {}
		local replicatedObjects: { Instance } = {}

		-- 1. Scan and copy all custom Attachments and nested ParticleEmitters from the blueprint
		for _, desc in ipairs(blueprintModel:GetDescendants()) do
			if desc:IsA("Attachment") then
				local blueprintPart = desc.Parent
				if blueprintPart and blueprintPart:IsA("BasePart") then
					-- Find the mirror limb part on the actual target player
					local targetPart = caster:FindFirstChild(blueprintPart.Name) :: BasePart?
					if targetPart then
						local newAttachment = desc:Clone()
						newAttachment.Name = "Heal_" .. desc.Name
						newAttachment.Parent = targetPart

						attachmentMap[desc] = newAttachment
						table.insert(replicatedObjects, newAttachment)

						-- Ignite the emerald particle emitter components
						for _, emitter in ipairs(newAttachment:GetDescendants()) do
							if emitter:IsA("ParticleEmitter") then
								emitter.Enabled = true
							end
						end
					end
				end
			end
		end

		-- 2. Link any custom Beams tracking across those attachments
		for _, desc in ipairs(blueprintModel:GetDescendants()) do
			if desc:IsA("Beam") then
				local origAttachment0 = desc.Attachment0
				local origAttachment1 = desc.Attachment1

				local newAttachment0 = attachmentMap[origAttachment0]
				local newAttachment1 = attachmentMap[origAttachment1]

				if newAttachment0 and newAttachment1 then
					local newBeam = desc:Clone()
					newBeam.Attachment0 = newAttachment0
					newBeam.Attachment1 = newAttachment1
					newBeam.Enabled = true
					newBeam.Parent = newAttachment0.Parent 
					table.insert(replicatedObjects, newBeam)
				end
			end
		end

		-- 3. Mark the items with a tracking attribute so Phase B can clean them up safely
		for _, obj in ipairs(replicatedObjects) do
			obj:SetAttribute("HealVFXInstance", true)
		end

		-- ------------------------------------------
		-- PHASE B: VISUAL REMOVAL & CLEANUP DECAY
		-- ------------------------------------------
	elseif phase == "Remove" then
		caster:SetAttribute("HasHealVisualActive", nil)

		-- Search and destroy instances safely, letting particles fade out naturally
		for _, desc in ipairs(caster:GetDescendants()) do
			if desc:GetAttribute("HealVFXInstance") == true then
				if desc:IsA("Attachment") or desc:IsA("Beam") then
					for _, emitter in ipairs(desc:GetDescendants()) do
						if emitter:IsA("ParticleEmitter") then
							emitter.Enabled = false
						end
					end
					Debris:AddItem(desc, 1.5) -- Leave buffer window for lingering particles to vanish
				else
					desc:Destroy()
				end
			end
		end
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function Heal.ServerExecute(caster: Model, _targetData: any)
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- [[ STATE MACHINE INTERACTION: THE CLEANSE ]]
	caster:SetAttribute("IsRooted", nil)
	caster:SetAttribute("IsCasting", nil)

	-- [[ HEALTH CALCULATION LAYER ]]
	local maxHealth = humanoid.MaxHealth
	local currentHealth = humanoid.Health
	humanoid.Health = math.min(maxHealth, currentHealth + HEAL_AMOUNT)

	-- [[ PIPELINE REWORK: Network Broadcast Routing via VFXManager channels ]]
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remoteEvents = remotes:WaitForChild("RemoteEvents")
	local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

	-- 1. Tell all clients to anchor the attachment framework onto the caster
	replicateVFXRemote:FireAllClients("Heal", "Cast", {
		Phase = "Apply"
	})

	-- 2. Time-lock visual lifespan for exactly one second before firing removal cycle
	task.delay(AURA_DURATION, function()
		if caster and caster.Parent then
			replicateVFXRemote:FireAllClients("Heal", "Cast", {
				Phase = "Remove"
			})
		end
	end)
end

return Heal