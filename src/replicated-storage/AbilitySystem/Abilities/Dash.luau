--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.Dash
local Dash = {
	Name = "Dash",
	Cooldown = 3.0,
	EnergyCost = 15,
	IconAssetId = "rbxassetid://97141270066357",
	TargetType = "MovementDirection", -- Explicitly directs InputManager to calculate current locomotion paths
	IsMobility = true,
	IsChanneled = true,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = RunService:IsClient() and Players.LocalPlayer or nil

-- Configuration Constants
local DASH_PHYSICS_DURATION = 0.15 -- Match this exactly to the physics destruction timer

-- [[ FOV CONFIGURATIONS ]]
local DASH_FOV_TARGET = 95         -- The speed-stretch FOV angle during the dash
local FOV_TWEEN_OUT_SPEED = 0.1    -- How fast the camera stretches out
local FOV_TWEEN_IN_SPEED = 0.25    -- How fast the camera pulls back to normal defaults

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================
function Dash.ClientCast(caster: Model?, data: any, assetFolder: Folder?)
	if not RunService:IsClient() then return end
	if not caster then return end

	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	-- Unpack traveling data vector safely from structured network payload
	local travelDirection = typeof(data) == "table" and data.TravelDirection or Vector3.zero
	if travelDirection.Magnitude == 0 then return end

	-- Place cosmetic elements here (Trails, Particles, Sounds) so everyone can see them

	-- CRITICAL FIX: Only apply physical forces, turn locks, and FOV shifts to the local casting player
	if LocalPlayer and caster == LocalPlayer.Character then
		-- Lock rotation
		local originalAutoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false

		local attachment = Instance.new("Attachment")
		attachment.Name = "DashAttachment"
		attachment.Parent = rootPart

		local linearVelocity = Instance.new("LinearVelocity")
		linearVelocity.Name = "DashForce"
		linearVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis

		-- Max out forces to dominate walking velocities completely
		linearVelocity.MaxAxesForce = Vector3.new(400000, 0, 400000)
		linearVelocity.VectorVelocity = travelDirection * 95 -- Snappy burst speed
		linearVelocity.Attachment0 = attachment
		linearVelocity.Parent = rootPart

		-- ==========================================
		-- [[ CAMERA EFFECTS PIPELINE ]]
		-- ==========================================
		local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

		-- Instantly stretch out camera perspective using sharp cubic scaling
		CameraEffects.ZoomTo(DASH_FOV_TARGET, FOV_TWEEN_OUT_SPEED, Enum.EasingStyle.Cubic)

		-- Optional: Add a very micro structural jitter to amplify the speed sensation
		CameraEffects.Shake(0.4, DASH_PHYSICS_DURATION, 30)

		-- Cleanup physics constraints and restore baseline configurations quickly
		task.delay(DASH_PHYSICS_DURATION, function()
			linearVelocity:Destroy()
			attachment:Destroy()

			-- Smoothly retract the camera zoom envelope back down onto standard baseline settings
			CameraEffects.ResetZoom(FOV_TWEEN_IN_SPEED)

			-- Restore the player's control over character turning mechanics safely
			if humanoid and humanoid.Parent then
				humanoid.AutoRotate = originalAutoRotate
			end
		end)
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function Dash.ServerExecute(caster: Model, targetData: any)
	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	-- Apply the Casting state instantly on the server to prevent input buffering mid-dash
	caster:SetAttribute("IsCasting", true)

	-- Lift the state lock precisely when the local LinearVelocity forces expire
	task.delay(DASH_PHYSICS_DURATION, function()
		if caster and caster.Parent then
			caster:SetAttribute("IsCasting", nil)
		end
	end)

	-- Extract travel direction data cleanly 
	local travelDirection = targetData :: Vector3
	local flatDirection = Vector3.new(travelDirection.X, 0, travelDirection.Z)

	-- Fall back to character's facing vector if no active direction input is detected
	if flatDirection.Magnitude == 0 then
		local lookDirection = rootPart.CFrame.LookVector
		flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	end

	flatDirection = flatDirection.Magnitude == 0 and Vector3.new(0, 0, -1) or flatDirection.Unit

	-- Pipeline alignment: Broadcast structured data containing Travel Direction
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remoteEvents = remotes:WaitForChild("RemoteEvents")
	local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

	replicateVFXRemote:FireAllClients("Dash", "Cast", {
		TravelDirection = flatDirection
	})
end

return Dash