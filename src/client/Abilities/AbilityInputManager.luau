--!strict
-- StarterPlayer.StarterPlayerScripts.AbilityClient.AbilityInputManager

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- [[ STATIC PERFORMANCE CONSTANTS ]]
local ZERO_VECTOR = Vector3.zero
local ACTIVE_SLOT_KEYS = { "Slot1", "Slot2", "Slot3", "Slot4" }
local MIN_SYNC_INTERVAL = 0.05
local MAX_RAY_DISTANCE = 500

-- [[ VISUALIZER CONFIGURATION ]]
local BEAM_COLOR = Color3.fromRGB(255, 0, 0)
local LENS_PERSIST_DURATION = 7.5
local TWEEN_INFO = TweenInfo.new(LENS_PERSIST_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)

-- [[ NETWORK / BINDABLES ]]
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BindableEvents = Remotes:WaitForChild("BindableEvents")

-- PRESERVED: Left as BindableEvent to talk directly to your ClientAbilityClass prediction framework
local RequestAbilityUse = BindableEvents:WaitForChild("RequestAbilityUse") :: BindableEvent
local ForceSyncInput = BindableEvents:WaitForChild("ForceSyncInput") :: BindableEvent

local SettingsManager = require(ReplicatedStorage.Modules:WaitForChild("SettingsManager")) :: any
local AbilitiesFolder = ReplicatedStorage:WaitForChild("AbilitySystem"):WaitForChild("Abilities") :: Folder

-- Cache LocalPlayer once at top-level
local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: Player
local Hotbar: Frame? = nil

local TargetTypeCache: { [string]: string } = {}
local CharacterAddedConnection: RBXScriptConnection? = nil
local ForceSyncConnection: RBXScriptConnection? = nil
local IsActive = false

type SpellModuleMetadata = {
	Name: string,
	TargetType: string?,
	[string]: any
}

local function drawVisualBeam(origin: Vector3, destination: Vector3)
	local distance = (destination - origin).Magnitude
	if distance <= 0.1 then return end

	local laser = Instance.new("Part")
	laser.Name = "DebugRaycastBeam"
	laser.Shape = Enum.PartType.Block
	laser.Material = Enum.Material.Neon
	laser.Color = BEAM_COLOR
	laser.Transparency = 0.1
	laser.Anchored = true
	laser.CanCollide = false
	laser.CanTouch = false
	laser.CanQuery = false

	laser.Size = Vector3.new(0.05, 0.05, distance)
	laser.CFrame = CFrame.lookAt(origin, destination) * CFrame.new(0, 0, -distance / 2)
	laser.Parent = workspace

	local fadeTween = TweenService:Create(laser, TWEEN_INFO, {
		Transparency = 1,
		Size = Vector3.new(0, 0, distance)
	})

	fadeTween:Play()
	Debris:AddItem(laser, LENS_PERSIST_DURATION)
end

local function getLiveCharacterElements(): (Model?, Humanoid?, BasePart?)
	local character = LocalPlayer.Character
	if not character then return nil, nil, nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function getMovementDirection(): Vector3
	local _, humanoid, rootPart = getLiveCharacterElements()
	if not humanoid or not rootPart then return ZERO_VECTOR end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude > 0 then
		return Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
	end
	return rootPart.CFrame.LookVector
end

local function getMouseWorldPosition(): Vector3
	local activeCamera = workspace.CurrentCamera :: Camera?
	if not activeCamera then return ZERO_VECTOR end

	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = activeCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local character = LocalPlayer.Character
	if character then 
		raycastParams.FilterDescendantsInstances = { character } 
	end

	local raycastResult = workspace:Raycast(unitRay.Origin, unitRay.Direction * MAX_RAY_DISTANCE, raycastParams)

	if raycastResult then
		return raycastResult.Position
	else
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local floorLevelY = rootPart and (rootPart.Position.Y - 3) or 0 

		if math.abs(unitRay.Direction.Y) > 0.001 then
			local t = (floorLevelY - unitRay.Origin.Y) / unitRay.Direction.Y
			if t > 0 and t < MAX_RAY_DISTANCE then
				return unitRay.Origin + (unitRay.Direction * t)
			end
		end

		return unitRay.Origin + (unitRay.Direction * MAX_RAY_DISTANCE)
	end
end

local function calculateTargetData(abilityName: string): Vector3
	local targetType = TargetTypeCache[abilityName]

	if not targetType then
		targetType = "MovementDirection" 
		local moduleScript = AbilitiesFolder:FindFirstChild(abilityName)
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local success, spellData = pcall(function()
				return require(moduleScript) :: SpellModuleMetadata
			end)

			if success and type(spellData) == "table" and spellData.TargetType then
				targetType = spellData.TargetType
			end
		end
		TargetTypeCache[abilityName] = targetType
	end

	local _, _, rootPart = getLiveCharacterElements()
	local visualOrigin = rootPart and rootPart.Position or ZERO_VECTOR

	if targetType == "MouseDirection" then
		if not rootPart then return ZERO_VECTOR end
		local targetPos = getMouseWorldPosition()
		local direction3D = (targetPos - rootPart.Position)
		local finalDir = if direction3D.Magnitude == 0 then rootPart.CFrame.LookVector else direction3D.Unit

		if visualOrigin ~= ZERO_VECTOR then
			drawVisualBeam(visualOrigin, visualOrigin + (finalDir * MAX_RAY_DISTANCE))
		end
		return finalDir

	elseif targetType == "MousePosition" or targetType == "Point" or targetType == "AOE" then
		local targetPos = getMouseWorldPosition()
		if visualOrigin ~= ZERO_VECTOR then
			drawVisualBeam(visualOrigin, targetPos)
		end
		return targetPos

	elseif targetType == "Self" then
		return ZERO_VECTOR
	else
		local moveDir = getMovementDirection()
		if visualOrigin ~= ZERO_VECTOR then
			drawVisualBeam(visualOrigin, visualOrigin + (moveDir * 15))
		end
		return moveDir
	end
end

local function handleAbilityInput(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	-- Absolute safety kill-switch if client is swapped out of DungeonMode
	if not IsActive then return end

	if inputState ~= Enum.UserInputState.Begin then 
		return 
	end

	local character = getLiveCharacterElements()
	if not character or not Hotbar then return end

	local hudFrame = Hotbar:FindFirstChild(actionName) :: Frame?
	local activeAbility = hudFrame and hudFrame:GetAttribute("AssignedAbility") :: string?

	if not activeAbility or activeAbility == "Empty" then 
		return 
	end

	local targetData = calculateTargetData(activeAbility)

	print(string.format("🔌 [InputManager] Ability: %s | Fired Vector: X: %.2f, Y: %.2f, Z: %.2f", 
		activeAbility, targetData.X, targetData.Y, targetData.Z))

	RequestAbilityUse:Fire(activeAbility, targetData)
end

local AbilityInputManager = {}

function AbilityInputManager.BindSlot(slotName: string, key: Enum.KeyCode)
	if not Hotbar or not IsActive then return end

	ContextActionService:UnbindAction(slotName)
	ContextActionService:BindAction(slotName, handleAbilityInput, true, key)

	local hudFrame = Hotbar:FindFirstChild(slotName) :: Frame?
	local rawAttribute = hudFrame and hudFrame:GetAttribute("AssignedAbility")
	local activeAbilityName: string = if type(rawAttribute) == "string" and rawAttribute ~= "" 
		then rawAttribute 
		else slotName

	ContextActionService:SetTitle(slotName, activeAbilityName)

	if hudFrame then
		local keybindTextLabel = hudFrame:FindFirstChild("KeybindText") :: TextLabel?
		if keybindTextLabel then
			keybindTextLabel.Text = key.Name
		end
	end
end

function AbilityInputManager.RefreshInputBinds()
	if not IsActive then return end

	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local mainInterface = playerGui and playerGui:FindFirstChild("MainInterface")
	Hotbar = mainInterface and mainInterface:FindFirstChild("Hotbar") :: Frame?

	if not Hotbar then 
		return 
	end

	for i = 1, #ACTIVE_SLOT_KEYS do
		local slotName = ACTIVE_SLOT_KEYS[i]
		local activeRemappedKey = SettingsManager.GetKeyForSlot(slotName)
		if activeRemappedKey and activeRemappedKey ~= Enum.KeyCode.Unknown then
			AbilityInputManager.BindSlot(slotName, activeRemappedKey)
		end
	end
end

local isSyncing = false
local LAST_SYNC_TIME = 0

local function queueThrottledSync()
	if not IsActive then return end

	local currentTime = os.clock()
	if isSyncing or (currentTime - LAST_SYNC_TIME) < MIN_SYNC_INTERVAL then
		return
	end

	isSyncing = true

	task.defer(function()
		if IsActive then
			AbilityInputManager.RefreshInputBinds()
		end
		LAST_SYNC_TIME = os.clock()
		isSyncing = false
	end)
end

-- [[ SYSTEM CONTROL OVERRIDES ]]

function AbilityInputManager.Init()
	if IsActive then return end
	IsActive = true
	print("⌨️ AbilityInputManager: Initializing Spell Input Matrices...")

	-- Hook up background sync events
	ForceSyncConnection = ForceSyncInput.Event:Connect(queueThrottledSync)

	CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function(char)
		if char:WaitForChild("Humanoid", 5) then
			queueThrottledSync()
		end
	end)

	-- Discover layout and bind instantly
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local mainInterface = playerGui and playerGui:FindFirstChild("MainInterface")
	Hotbar = mainInterface and mainInterface:FindFirstChild("Hotbar") :: Frame?

	AbilityInputManager.RefreshInputBinds()
end

function AbilityInputManager.Clean()
	print("🚫 AbilityInputManager: Running systematic clean sequence.")
	IsActive = false

	-- 1. Sever engine signals
	if ForceSyncConnection then
		ForceSyncConnection:Disconnect()
		ForceSyncConnection = nil
	end

	if CharacterAddedConnection then
		CharacterAddedConnection:Disconnect()
		CharacterAddedConnection = nil
	end

	-- 2. Clear ContextActionService bindings from engine
	for i = 1, #ACTIVE_SLOT_KEYS do
		ContextActionService:UnbindAction(ACTIVE_SLOT_KEYS[i])
	end

	Hotbar = nil
end

return AbilityInputManager