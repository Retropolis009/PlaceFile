local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local MainInterface = PlayerGui:WaitForChild("MainInterface")

-- Module References
local UserInterface = script.Parent:WaitForChild("UserInterface")
local Abilities = script.Parent:WaitForChild("Abilities")
local FpsClient = script.Parent:WaitForChild("FpsClient")

local PlayerStats = require(UserInterface:WaitForChild("PlayerStats"))
local HotbarController = require(UserInterface:WaitForChild("HotbarController"))
local AbilityInputManager = require(Abilities:WaitForChild("AbilityInputManager"))
local WeaponInputManager = require(FpsClient:WaitForChild("WeaponInputManager"))
local FpsInterface = require(UserInterface:WaitForChild("FpsInterface"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local ToggleGameModeEvent = Remotes:WaitForChild("ToggleGameMode")
local RequestSwapModeEvent = Remotes:WaitForChild("RequestSwapMode")

local MouseLockConnection: RBXScriptConnection? = nil
local BodyRenderConnection: RBXScriptConnection? = nil

-- [[ CAMERA PITCH LIMIT CONFIGURATION ]]
local MIN_LOOK_DOWN_ANGLE = math.rad(-50) -- Max downward look angle (-50 degrees)
local MAX_LOOK_UP_ANGLE = math.rad(80)    -- Max upward look angle (+80 degrees)

-- Whitelisted arm parts for R15 & R6
local ARM_PARTS = {
	"LeftHand", "LeftLowerArm", "LeftUpperArm",
	"RightHand", "RightLowerArm", "RightUpperArm",
	"Left Arm", "Right Arm"
}

--- Hard-stops camera pitch at boundary limits (no bounce, no snapping)
local function enableCameraPitchLimit()
	RunService:UnbindFromRenderStep("FPS_CameraPitchLimit")
	RunService:BindToRenderStep("FPS_CameraPitchLimit", Enum.RenderPriority.Camera.Value + 1, function()
		if LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then return end
		local camera = workspace.CurrentCamera
		if not camera then return end

		-- Use YXZ Euler angles to match Roblox's native camera rotation math
		local rx, ry, rz = camera.CFrame:ToEulerAnglesYXZ()

		if rx < MIN_LOOK_DOWN_ANGLE or rx > MAX_LOOK_UP_ANGLE then
			local clampedX = math.clamp(rx, MIN_LOOK_DOWN_ANGLE, MAX_LOOK_UP_ANGLE)
			camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromEulerAnglesYXZ(clampedX, ry, rz)
		end
	end)
end

--- Disables camera pitch limiting
local function disableCameraPitchLimit()
	RunService:UnbindFromRenderStep("FPS_CameraPitchLimit")
end

--- Keeps ONLY character arms visible in First Person (Hides Head, Torso, and Legs)
local function enableFirstPersonBodyRendering()
	if BodyRenderConnection then
		BodyRenderConnection:Disconnect()
		BodyRenderConnection = nil
	end

	BodyRenderConnection = RunService.RenderStepped:Connect(function()
		local character = LocalPlayer.Character
		if not character then return end

		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") then
				if table.find(ARM_PARTS, part.Name) then
					part.LocalTransparencyModifier = 0 -- Keep Arms visible
				else
					part.LocalTransparencyModifier = 1 -- Hide Head, Torso, and Legs
				end
			elseif part:IsA("Accessory") then
				local handle = part:FindFirstChild("Handle") :: BasePart?
				if handle then
					handle.LocalTransparencyModifier = 1 -- Hide accessories
				end
			end
		end
	end)
end

--- Resets character body rendering back to default engine mechanics
local function disableFirstPersonBodyRendering()
	if BodyRenderConnection then
		BodyRenderConnection:Disconnect()
		BodyRenderConnection = nil
	end

	local character = LocalPlayer.Character
	if character then
		for _, part in ipairs(character:GetChildren()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			elseif part:IsA("Accessory") then
				local handle = part:FindFirstChild("Handle") :: BasePart?
				if handle then
					handle.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

-- Core systemic initialization branching check
local function startSystems(gameModeName: string)
	print("📡 Client Bootstrapper: Loading system assets for -> " .. gameModeName)

	local fpsScreenGui = PlayerGui:WaitForChild("FpsInterface", 5) :: ScreenGui?
	local ammoFrame = fpsScreenGui and fpsScreenGui:FindFirstChild("Ammo", true) :: Frame?
	local crosshairFrame = fpsScreenGui and fpsScreenGui:FindFirstChild("Crosshair", true) :: Frame?

	if gameModeName == "ArenaMode" then
		-- 🟥 ARENA MODE (FPS) SETUP
		print("🎯 ArenaMode selected. Activating FPS firearm systems...")

		-- 1. Enforce First-Person Camera & Center-Lock Hardware Cursor
		LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false

		if MouseLockConnection then MouseLockConnection:Disconnect() end
		MouseLockConnection = RunService.RenderStepped:Connect(function()
			if LocalPlayer and LocalPlayer.CameraMode == Enum.CameraMode.LockFirstPerson then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				UserInputService.MouseIconEnabled = false
			end
		end)

		-- 2. Render Arms & Enable Camera Pitch Limits
		enableFirstPersonBodyRendering()
		enableCameraPitchLimit()

		-- 3. Toggle UI States
		MainInterface.Hotbar.Visible = false
		MainInterface.SpellbookMenu.Visible = false
		MainInterface.Player.Visible = false

		if fpsScreenGui then
			fpsScreenGui.Enabled = true
		end
		if ammoFrame then ammoFrame.Visible = true end
		if crosshairFrame then crosshairFrame.Visible = true end

		FpsInterface.Init()

		if WeaponInputManager.Init then
			WeaponInputManager.Init()
		end

	elseif gameModeName == "DungeonMode" then
		-- 🟦 DUNGEON MODE (RPG) SETUP
		print("🔮 DungeonMode selected. Constructing spell layouts...")

		if MouseLockConnection then
			MouseLockConnection:Disconnect()
			MouseLockConnection = nil
		end

		disableFirstPersonBodyRendering()
		disableCameraPitchLimit()

		LocalPlayer.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		if fpsScreenGui then
			fpsScreenGui.Enabled = false
		end
		if ammoFrame then ammoFrame.Visible = false end
		if crosshairFrame then crosshairFrame.Visible = false end

		FpsInterface.Clean()

		MainInterface.Hotbar.Visible = true
		MainInterface.Player.Visible = true

		PlayerStats.Init(MainInterface)
		HotbarController.Init(MainInterface)

		if AbilityInputManager.Init then
			AbilityInputManager.Init()
		end
	end
end

-- Systematic module teardown
local function stopSystems()
	print("🧹 Client Bootstrapper: Clearing old combat system parameters.")

	if MouseLockConnection then
		MouseLockConnection:Disconnect()
		MouseLockConnection = nil
	end

	disableFirstPersonBodyRendering()
	disableCameraPitchLimit()

	LocalPlayer.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	local fpsScreenGui = PlayerGui:FindFirstChild("FpsInterface") :: ScreenGui?
	local ammoFrame = fpsScreenGui and fpsScreenGui:FindFirstChild("Ammo", true) :: Frame?
	local crosshairFrame = fpsScreenGui and fpsScreenGui:FindFirstChild("Crosshair", true) :: Frame?

	if fpsScreenGui then
		fpsScreenGui.Enabled = false
	end
	if ammoFrame then ammoFrame.Visible = false end
	if crosshairFrame then crosshairFrame.Visible = false end

	pcall(function() FpsInterface.Clean() end)
	pcall(function() PlayerStats.Clean() end)
	pcall(function() HotbarController.Clean() end)

	if AbilityInputManager.Clean then pcall(AbilityInputManager.Clean) end
	if WeaponInputManager.Clean then pcall(WeaponInputManager.Clean) end
end

-- Network Interception
ToggleGameModeEvent.OnClientEvent:Connect(function(state, gameModeName)
	if state == "Start" then
		startSystems(gameModeName)
	elseif state == "Stop" then
		stopSystems()
	end
end)

-- Initialize Switcher Panel
local function initializeSwitcherMenu()
	local switcherUI = MainInterface:WaitForChild("GameModeSwitcher", 5) :: Frame?
	if not switcherUI then
		warn("❌ GameModeSwitcher Frame was not found inside MainInterface!")
		return
	end

	switcherUI.Visible = true

	for _, button in ipairs(switcherUI:GetChildren()) do
		if button:IsA("TextButton") or button:IsA("ImageButton") then
			button.MouseButton1Click:Connect(function()
				local targetedMode = button.Name
				print("📥 Local click captured! Requesting mode swap to: " .. targetedMode)
				RequestSwapModeEvent:FireServer(targetedMode)
			end)
		end
	end
end

initializeSwitcherMenu()