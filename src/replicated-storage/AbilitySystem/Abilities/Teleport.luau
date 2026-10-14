--!strict
-- ReplicatedStorage.AbilitySystem.Abilities.Teleport
local Teleport = {
	Name = "Teleport",
	Cooldown = 4.0,
	EnergyCost = 20,
	IconAssetId = "rbxassetid://104905649559944", 
	TargetType = "MovementDirection", 
	IsMobility = true,
	IsChanneled = true,
}

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- [[ TOP-LEVEL CACHED ENVIRONMENT CONSTANTS ]]
local LocalPlayer = RunService:IsClient() and Players.LocalPlayer or nil

-- Configuration Parameters
local TELEPORT_DISTANCE = 30       -- Fixed distance in studs the player flashes forward
local TELEPORT_CAST_WINDOW = 0.15   -- The post-teleport animation recovery lock window
local PORTAL_HEIGHT_OFFSET = 12    -- Height above ground the exit portal spawns
local DROP_VELOCITY = -35            -- Downward thrust when dropped out of exit portal
local PORTAL_LIFECYCLE = 1.2        -- Total duration portals remain active

-- ==========================================
-- [[ DECENTRALIZED CLIENT-SIDE VFX CONTRACT ]]
-- ==========================================
function Teleport.ClientCast(caster: Model?, data: any, assetFolder: Folder?)
	if not RunService:IsClient() then return end
	if not assetFolder or not caster then return end

	local phase = typeof(data) == "table" and data.Phase or "Cast"
	local CameraEffects = require(ReplicatedStorage.Modules.CameraEffects)

	-- Extract the base Portal asset template from your VisualSystem folder container
	local portalTemplate = assetFolder:FindFirstChild("Portal") 
		or assetFolder:FindFirstChild("PortalVFX") 
		or assetFolder:FindFirstChild("VFX")

	if not portalTemplate then
		warn(string.format("[Teleport VFX Error] Missing explicit asset template inside folder: %s", assetFolder.Name))
		return
	end

	-- ------------------------------------------
	-- PHASE A: SPAWN ENTRY PORTAL (At Origin Coordinates)
	-- ------------------------------------------
	if phase == "Cast" then
		local originPos: Vector3? = data.OriginPosition
		if not originPos then return end

		-- CAMERA SYSTEM: Vacuum Snap (Only if this local client is the one teleporting)
		if LocalPlayer and caster == LocalPlayer.Character then
			-- Compress view inward instantly to simulate vacuum suction
			CameraEffects.ZoomTo(50, 0.05, Enum.EasingStyle.Quad)
		end

		local entryPortal = portalTemplate:Clone()
		if entryPortal:IsA("BasePart") then
			entryPortal.Anchored = true
			entryPortal.CanCollide = false
			entryPortal.CanQuery = false
			entryPortal.CanTouch = false

			-- Orient horizontally flat on the ground surface
			entryPortal.CFrame = CFrame.new(originPos) * CFrame.Angles(0, 0, math.rad(90))
			entryPortal.Parent = workspace

			for _, emitter in ipairs(entryPortal:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then emitter.Enabled = true end
			end

			-- Open and close scaling sequence
			local originalSize = entryPortal.Size
			entryPortal.Size = Vector3.new(originalSize.X, 0, 0)

			local openTween = TweenService:Create(entryPortal, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = originalSize})
			openTween:Play()

			task.delay(PORTAL_LIFECYCLE - 0.3, function()
				for _, emitter in ipairs(entryPortal:GetDescendants()) do
					if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
				end
				local closeTween = TweenService:Create(entryPortal, TweenInfo.new(0.3), {Size = Vector3.new(originalSize.X, 0, 0)})
				closeTween:Play()
				closeTween.Completed:Connect(function() entryPortal:Destroy() end)
			end)
		end

		-- ------------------------------------------
		-- PHASE B: SPAWN EXIT PORTAL (Suspended in Air Over Destination)
		-- ------------------------------------------
	elseif phase == "Exit" then
		local dropPos: Vector3? = data.DropPosition
		if not dropPos then return end

		-- CAMERA SYSTEM: Exit Pop & Ground Impact Monitor
		if LocalPlayer and caster == LocalPlayer.Character then
			-- Explode the view outward to register the high drop speed, then transition back to normal over 0.35s
			CameraEffects.ZoomTo(85, 0.02, Enum.EasingStyle.Quad)
			task.delay(0.04, function()
				CameraEffects.ResetZoom(0.35)
			end)

			-- Track landing impact cleanly without structural update rumbles
			local humanoid = caster:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local landingConnection: RBXScriptConnection? = nil
				landingConnection = humanoid.StateChanged:Connect(function(oldState, newState)
					if newState == Enum.HumanoidStateType.Landed then
						-- Heavy physical compression down along the Y-axis recoil offset channel
						CameraEffects.ApplyOffsetRecoil(Vector3.new(0, -2, 0), 0.15)
						if landingConnection then
							landingConnection:Disconnect()
							landingConnection = nil
						end
					end
				end)
				-- Safety cleanup in case they never touch the floor
				task.delay(2.0, function()
					if landingConnection then landingConnection:Disconnect() end
				end)
			end
		end

		local exitPortal = portalTemplate:Clone()
		if exitPortal:IsA("BasePart") then
			exitPortal.Anchored = true
			exitPortal.CanCollide = false
			exitPortal.CanQuery = false
			exitPortal.CanTouch = false

			-- Position high up in the air facing straight DOWN
			exitPortal.CFrame = CFrame.new(dropPos) * CFrame.Angles(0, 0, math.rad(90))
			exitPortal.Parent = workspace

			for _, emitter in ipairs(exitPortal:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then 
					emitter.Enabled = true 
					emitter:Emit(25) -- Aggressive burst as the player is ejected
				end
			end

			local originalSize = exitPortal.Size
			exitPortal.Size = Vector3.new(originalSize.X, 0, 0)

			local openTween = TweenService:Create(exitPortal, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = originalSize})
			openTween:Play()

			task.delay(PORTAL_LIFECYCLE - 0.3, function()
				for _, emitter in ipairs(exitPortal:GetDescendants()) do
					if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
				end
				local closeTween = TweenService:Create(exitPortal, TweenInfo.new(0.3), {Size = Vector3.new(originalSize.X, 0, 0)})
				closeTween:Play()
				closeTween.Completed:Connect(function() exitPortal:Destroy() end)
			end)
		end
	end
end

-- ==========================================
-- [[ SERVER AUTHORITY / GAMEPLAY LOGIC ]]
-- ==========================================
function Teleport.ServerExecute(caster: Model, targetData: any)
	local rootPart = caster:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = caster:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end

	-- Block input actions immediately to avoid rapid movement-chaining bugs
	caster:SetAttribute("IsCasting", true)
	task.delay(TELEPORT_CAST_WINDOW, function()
		if caster and caster.Parent then
			caster:SetAttribute("IsCasting", nil)
		end
	end)

	-- Extract locomotion vector context from client layout payload
	local travelDirection = targetData :: Vector3
	local flatDirection = Vector3.new(travelDirection.X, 0, travelDirection.Z)

	if flatDirection.Magnitude == 0 then
		local lookDirection = rootPart.CFrame.LookVector
		flatDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	end

	flatDirection = flatDirection.Magnitude == 0 and Vector3.new(0, 0, -1) or flatDirection.Unit

	local startingPosition = rootPart.Position
	local finalDestination = startingPosition + (flatDirection * TELEPORT_DISTANCE)

	-- Fetch network routing channels
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remoteEvents = remotes:WaitForChild("RemoteEvents")
	local replicateVFXRemote = remoteEvents:WaitForChild("ReplicateVFX") :: RemoteEvent

	-- 1. Fire Entry Portal Visual right at the player's feet before moving them
	replicateVFXRemote:FireAllClients("Teleport", "Cast", {
		Phase = "Cast",
		Caster = caster,
		OriginPosition = startingPosition - Vector3.new(0, 3, 0)
	})

	-- 2. Calculate the dropping point coordinates suspended in mid-air
	local dropDestination = finalDestination + Vector3.new(0, PORTAL_HEIGHT_OFFSET, 0)

	-- 3. Instantly pivot and cancel current physical momentum vector profiles
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	caster:PivotTo(CFrame.new(dropDestination, dropDestination + flatDirection))
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	-- 4. Inject a downward impulse to shoot the player out of the overhead portal gracefully
	task.defer(function()
		if rootPart and rootPart.Parent then
			rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, DROP_VELOCITY, rootPart.AssemblyLinearVelocity.Z)
		end
	end)

	-- 5. Fire Exit Portal Visual to render suspended above the end zone
	replicateVFXRemote:FireAllClients("Teleport", "Cast", {
		Phase = "Exit",
		Caster = caster,
		DropPosition = dropDestination
	})
end

return Teleport