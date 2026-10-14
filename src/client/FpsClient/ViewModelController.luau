--!strict
-- StarterPlayer.StarterPlayerScripts.AbilityClient.FpsClient.ViewModelController
local ViewModelController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FpsSystem = ReplicatedStorage:WaitForChild("FpsSystem")
local ViewModelsFolder = FpsSystem:WaitForChild("ViewModels")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: Player
local Camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: Camera

local CurrentModelInstance: Model? = nil
local RenderConnection: RBXScriptConnection? = nil
local IsActive = false

-- Sway configuration settings
local SWAY_SMOOTHNESS = 0.15
local MAX_SWAY_BOUNDS = 0.1

local accumulatedSwayX = 0
local accumulatedSwayY = 0

local function onRenderFrameUpdate(deltaTime: number)
	if not IsActive or not CurrentModelInstance or not CurrentModelInstance.PrimaryPart then 
		return 
	end

	-- 1. Track raw mouse changes for camera sway calculations
	local mouseDelta = UserInputService:GetMouseDelta()

	accumulatedSwayX = math.clamp(math.lerp(accumulatedSwayX, -mouseDelta.X * 0.01, SWAY_SMOOTHNESS), -MAX_SWAY_BOUNDS, MAX_SWAY_BOUNDS)
	accumulatedSwayY = math.clamp(math.lerp(accumulatedSwayY, -mouseDelta.Y * 0.01, SWAY_SMOOTHNESS), -MAX_SWAY_BOUNDS, MAX_SWAY_BOUNDS)

	-- 2. Build the final viewmodel orientation relative to the camera position
	local cameraCFrame = Camera.CFrame
	local targetSwayOffset = CFrame.new(accumulatedSwayX, accumulatedSwayY, 0)

	-- Keep the viewmodel locked in front of the camera face matrix boundary
	CurrentModelInstance:PivotTo(cameraCFrame * targetSwayOffset)
end

function ViewModelController.EquipWeaponViewModel(weaponName: string)
	ViewModelController.ClearViewModel() -- Wipe any existing rigs first

	local blueprint = ViewModelsFolder:FindFirstChild(weaponName) :: Model?
	if not blueprint then
		warn(string.format("⚠️ [ViewModelController] No visual template found for weapon: %s", weaponName))
		return
	end

	local modelClone = blueprint:Clone()
	-- Force tracking optimization parameters
	for _, desc in ipairs(modelClone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.CastShadow = false
		end
	end

	modelClone.Parent = Camera
	CurrentModelInstance = modelClone
	print(string.format("👁️ [ViewModelController] Render rig built for %s", weaponName))
end

function ViewModelController.ClearViewModel()
	if CurrentModelInstance then
		CurrentModelInstance:Destroy()
		CurrentModelInstance = nil
	end
end

function ViewModelController.Init()
	if IsActive then return end
	IsActive = true
	Camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: Camera

	-- Monitor when the character changes tools to dynamically swap weapon meshes
	local function hookToolSignals(character: Model)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and IsActive then
				ViewModelController.EquipWeaponViewModel(child.Name)
			end
		end)

		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				ViewModelController.ClearViewModel()
			end
		end)
	end

	if LocalPlayer.Character then hookToolSignals(LocalPlayer.Character) end
	LocalPlayer.CharacterAdded:Connect(hookToolSignals)

	RenderConnection = RunService.RenderStepped:Connect(onRenderFrameUpdate)
end

function ViewModelController.Clean()
	IsActive = false
	if RenderConnection then
		RenderConnection:Disconnect()
		RenderConnection = nil
	end
	ViewModelController.ClearViewModel()
	print("🚫 [ViewModelController] Teardown complete.")
end

return ViewModelController