--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.Silence
local Silence = {
	Name = "Silence",
	Cooldown = 18.0,
	EnergyCost = 25,
	IconAssetId = "rbxassetid://92429556428421",
	TargetType = "MousePosition", 
	IsMagic = true,
}

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configuration Parameters
local ZONE_RADIUS = 12 
local MAX_RANGE = 60   
local SILENCE_DURATION = 10.0 

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================
function Silence.ClientCast(caster: Model?, data: any, assetFolder: Folder?)
	if not RunService:IsClient() then return end
	if not assetFolder then return end

	local phase = typeof(data) == "table" and data.Phase or "Cast"

	-- ------------------------------------------
	-- PHASE A: INSTANT BLAST ZONE VISUAL
	-- ------------------------------------------
	if phase == "Cast" then
		local destination: Vector3? = data.TargetPosition
		if not destination then return end

		local zoneTemplate = assetFolder:FindFirstChild("SilenceZone") or assetFolder:FindFirstChild("Zone")
		if not zoneTemplate then return end

		local hexZone = zoneTemplate:Clone()

		if hexZone:IsA("Model") then
			hexZone:ScaleTo(ZONE_RADIUS * 2)
			hexZone:PivotTo(CFrame.new(destination))
		elseif hexZone:IsA("BasePart") then
			hexZone.CanCollide = false
			hexZone.CanQuery = false
			hexZone.CanTouch = false
			hexZone.Anchored = true
			hexZone.CFrame = CFrame.new(destination) * CFrame.Angles(0, 0, math.rad(90))
			hexZone.Size = Vector3.new(hexZone.Size.X, 0, 0)
		end

		hexZone.Parent = workspace

		for _, emitter in ipairs(hexZone:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = true
				emitter:Emit(30) 
			end
		end

		if hexZone:IsA("BasePart") then
			local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local tween = TweenService:Create(hexZone, info, {
				Size = Vector3.new(hexZone.Size.X, ZONE_RADIUS * 2, ZONE_RADIUS * 2),
				Transparency = 1
			})
			tween:Play()
			tween.Completed:Connect(function() hexZone:Destroy() end)
		else
			Debris:AddItem(hexZone, 0.4)
		end

		-- ------------------------------------------
		-- PHASE B: REPLICATE ATTACHMENTS & BEAMS ONTO VICTIM
		-- ------------------------------------------
	elseif phase == "ApplyDebuff" then
		local victim: Model? = data.Victim
		if not victim then return end

		-- Avoid duplicate replication if they are already affected
		if victim:GetAttribute("HasSilenceVisualDebuff") then return end
		victim:SetAttribute("HasSilenceVisualDebuff", true)

		local blueprintModel = assetFolder:FindFirstChild("VFX") or assetFolder:FindFirstChild("SilenceVisual")
		if not blueprintModel or not blueprintModel:IsA("Model") then return end

		-- Store a dictionary of mapped attachments to link Beams correctly later
		local attachmentMap: { [Attachment]: Attachment } = {}
		local replicatedObjects: { Instance } = {}

		-- 1. Replicate Attachments and nested ParticleEmitters
		for _, desc in ipairs(blueprintModel:GetDescendants()) do
			if desc:IsA("Attachment") then
				local blueprintPart = desc.Parent
				if blueprintPart and blueprintPart:IsA("BasePart") then
					-- Find the matching body part on the target player character model
					local targetPart = victim:FindFirstChild(blueprintPart.Name) :: BasePart?
					if targetPart then
						local newAttachment = desc:Clone()
						newAttachment.Name = "Silence_" .. desc.Name
						newAttachment.Parent = targetPart

						attachmentMap[desc] = newAttachment
						table.insert(replicatedObjects, newAttachment)

						-- Enable any particle emitters inside this attachment frame
						for _, emitter in ipairs(newAttachment:GetDescendants()) do
							if emitter:IsA("ParticleEmitter") then
								emitter.Enabled = true
							end
						end
					end
				end
			end
		end

		-- 2. Replicate Beams and attach them to our newly created target attachments
		for _, desc in ipairs(blueprintModel:GetDescendants()) do
			if desc:IsA("Beam") then
				local origAttachment0 = desc.Attachment0
				local origAttachment1 = desc.Attachment1

				-- Find the corresponding attachments we just created on the player
				local newAttachment0 = attachmentMap[origAttachment0]
				local newAttachment1 = attachmentMap[origAttachment1]

				if newAttachment0 and newAttachment1 then
					local newBeam = desc:Clone()
					newBeam.Attachment0 = newAttachment0
					newBeam.Attachment1 = newAttachment1
					newBeam.Enabled = true
					-- Parent it to the target part where Attachment0 lives
					newBeam.Parent = newAttachment0.Parent 
					table.insert(replicatedObjects, newBeam)
				end
			end
		end

		-- 3. Tag replicated items so Phase C can easily locate and wipe them out
		for _, obj in ipairs(replicatedObjects) do
			obj:SetAttribute("SilenceVFXInstance", true)
		end

		-- ------------------------------------------
		-- PHASE C: DEBUFF REMOVAL & CLEANUP
		-- ------------------------------------------
	elseif phase == "RemoveDebuff" then
		local victim: Model? = data.Victim
		if not victim then return end

		victim:SetAttribute("HasSilenceVisualDebuff", nil)

		-- Search the character's body parts and clean up our custom components
		for _, desc in ipairs(victim:GetDescendants()) do
			if desc:GetAttribute("SilenceVFXInstance") == true then
				if desc:IsA("Attachment") or desc:IsA("Beam") then
					-- Turn off particle emitters smoothly first
					for _, emitter in ipairs(desc:GetDescendants()) do
						if emitter:IsA("ParticleEmitter") then
							emitter.Enabled = false
						end
					end

					-- Clear the elements out of memory frame safely
					Debris:AddItem(desc, 1.5)
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
function Silence.ServerExecute(caster: Model, targetData: any)
	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local targetPosition: Vector3 = typeof(targetData) == "Vector3" and targetData 
		or rootPart.Position + (rootPart.CFrame.LookVector * 10)

	local currentPos = rootPart.Position
	if (targetPosition - currentPos).Magnitude > MAX_RANGE then
		targetPosition = currentPos + ((targetPosition - currentPos).Unit * MAX_RANGE)
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remoteEvents = remotes:WaitForChild("RemoteEvents")
	local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

	replicateVFXRemote:FireAllClients("Silence", "Cast", {
		Phase = "Cast",
		TargetPosition = targetPosition
	})

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {caster}

	local partsInRange = workspace:GetPartBoundsInRadius(targetPosition, ZONE_RADIUS, overlapParams)
	local affectedCharacters: { [Model]: boolean } = {}

	for _, part in ipairs(partsInRange) do
		local character = part.Parent
		if character and character:IsA("Model") and character:FindFirstChild("Humanoid") then
			local targetRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local targetHumanoid = character:FindFirstChildOfClass("Humanoid")

			if targetRoot and targetHumanoid and not affectedCharacters[character] then
				affectedCharacters[character] = true

				character:SetAttribute("IsSilenced", true)

				replicateVFXRemote:FireAllClients("Silence", "Cast", {
					Phase = "ApplyDebuff",
					Victim = character
				})

				task.delay(SILENCE_DURATION, function()
					if character and character.Parent then
						character:SetAttribute("IsSilenced", nil)

						replicateVFXRemote:FireAllClients("Silence", "Cast", {
							Phase = "RemoveDebuff",
							Victim = character
						})
					end
				end)
			end
		end
	end

	local casterPlayer = Players:GetPlayerFromCharacter(caster)
	if casterPlayer then
		local ServerScriptService = game:GetService("ServerScriptService")
		local AbilityServerModule = ServerScriptService:WaitForChild("AbilityServer", 5)
		local AbilityServerManagerModule = AbilityServerModule and AbilityServerModule:WaitForChild("AbilityServerManager", 5)

		if AbilityServerManagerModule and AbilityServerManagerModule:IsA("ModuleScript") then
			type ManagerContract = {
				CreateSilenceZone: (caster: Player, position: Vector3, radius: number, duration: number) -> ()
			}
			local AbilityServerManager = require(AbilityServerManagerModule) :: ManagerContract
			AbilityServerManager.CreateSilenceZone(casterPlayer, targetPosition, ZONE_RADIUS, SILENCE_DURATION)
		end
	end
end

return Silence