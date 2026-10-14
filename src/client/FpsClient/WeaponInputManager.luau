--!strict
-- StarterPlayer.StarterPlayerScripts.AbilityClient.FpsClient.WeaponInputManager
local WeaponInputManager = {}

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local StarterPlayerScript = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local FpsInterface = require(StarterPlayerScript:WaitForChild("UserInterface"):WaitForChild("FpsInterface")) :: any
local FpsSystem = ReplicatedStorage:WaitForChild("FpsSystem")
local WeaponsFolder = FpsSystem:WaitForChild("Weapons")

local WeaponConfig = require(WeaponsFolder:WaitForChild("WeaponConfig")) :: any
local ImpactFXManager = require(WeaponsFolder:WaitForChild("ImpactFXManager")) :: any
local RecoilManager = require(script.Parent:WaitForChild("RecoilManager")) :: any
local CameraShakeManager = require(script.Parent:WaitForChild("CameraShakeManager")) :: any

-- [[ NETWORK INFRASTRUCTURE ]]
local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local WeaponFireEvent = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
local WeaponReloadEvent = Remotes:WaitForChild("WeaponReload") :: RemoteEvent
local WeaponFireReplicated = Remotes:WaitForChild("WeaponFireReplicated") :: RemoteEvent
local UpdateAmmoEvent = Remotes:WaitForChild("UpdateAmmo") :: RemoteEvent

-- [[ CORE SYSTEM PROPERTIES ]]
local LocalPlayer = Players.LocalPlayer or (Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: any) :: Player
local Camera = workspace.CurrentCamera or (workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: any) :: Camera

-- [[ ANIMATION IDs CONFIGURATION ]]
local ANIMATIONS = {
	Pistol = {
		Hold = "rbxassetid://113700215210998",
		Reload = "rbxassetid://98792407282371",
	},
	Default = {
		Hold = "rbxassetid://112223111680709",
		Reload = "rbxassetid://103765621218275",
	},
}

-- [[ INPUT & STATE MANAGEMENT ]]
local IsActive = false
local IsShootingIntent = false
local IsAimingIntent = false
local IsFreeCamActive = false

local CurrentWeaponName: string? = nil
local CurrentWeaponConfig: any = nil
local CurrentTool: Tool? = nil

local LastFireTime = 0
local CurrentBloom = 0
local CurrentReloadToken = 0

type AmmoState = {
	CurrentAmmo: number,
	ReserveAmmo: number,
	IsReloading: boolean,
}

-- Dictionary mapping weapon names to their respective persisted ammo state
local AmmoTrackerByWeapon: { [string]: AmmoState } = {}

-- [[ ANIMATION TRACK STATE ]]
local ActiveHoldTrack: AnimationTrack? = nil
local ActiveReloadTrack: AnimationTrack? = nil

-- [[ CAMERA FOV CONSTANTS ]]
local TARGET_ADS_FOV = 40
local DEFAULT_FOV = 70
local FOV_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ActiveFovTween: Tween? = nil

-- [[ CONNECTION STORAGE ]]
local Connections: { [string]: RBXScriptConnection } = {}
local TransparencyConnections: { [string]: RBXScriptConnection } = {}

-- [[ UTILITY & ANIMATION HELPER FUNCTIONS ]]

local function getOrCreateAmmoState(weaponName: string, config: any): AmmoState
	if not AmmoTrackerByWeapon[weaponName] then
		local magSize = config.MagazineSize or config.ClipSize or 30
		local reserveSize = config.MaxReserveAmmo or (magSize * 3)
		AmmoTrackerByWeapon[weaponName] = {
			CurrentAmmo = magSize,
			ReserveAmmo = reserveSize,
			IsReloading = false,
		}
	end
	return AmmoTrackerByWeapon[weaponName]
end

local function stopAllWeaponAnimations()
	if ActiveHoldTrack then
		ActiveHoldTrack:Stop(0.1)
		ActiveHoldTrack:Destroy()
		ActiveHoldTrack = nil
	end
	if ActiveReloadTrack then
		ActiveReloadTrack:Stop(0.1)
		ActiveReloadTrack:Destroy()
		ActiveReloadTrack = nil
	end
end

local function getAnimationSet(weaponName: string, config: any)
	local isPistol = (config and config.WeaponType == "Pistol") 
		or string.find(string.lower(weaponName), "pistol") ~= nil
		or string.find(string.lower(weaponName), "sidearm") ~= nil

	return isPistol and ANIMATIONS.Pistol or ANIMATIONS.Default
end

local function playHoldAnimation()
	if not CurrentWeaponName then return end

	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	stopAllWeaponAnimations()

	local animSet = getAnimationSet(CurrentWeaponName, CurrentWeaponConfig)
	local animObj = Instance.new("Animation")
	animObj.AnimationId = animSet.Hold

	ActiveHoldTrack = animator:LoadAnimation(animObj)
	if ActiveHoldTrack then
		ActiveHoldTrack.Priority = Enum.AnimationPriority.Action
		ActiveHoldTrack.Looped = true
		ActiveHoldTrack:Play(0.1)
	end
end

local function playReloadAnimation()
	if not CurrentWeaponName then return end

	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end

	if ActiveReloadTrack then
		ActiveReloadTrack:Stop()
		ActiveReloadTrack:Destroy()
		ActiveReloadTrack = nil
	end

	local animSet = getAnimationSet(CurrentWeaponName, CurrentWeaponConfig)
	local animObj = Instance.new("Animation")
	animObj.AnimationId = animSet.Reload

	ActiveReloadTrack = animator:LoadAnimation(animObj)
	if ActiveReloadTrack then
		ActiveReloadTrack.Priority = Enum.AnimationPriority.Action2
		ActiveReloadTrack.Looped = false
		ActiveReloadTrack:Play(0.05)
	end
end

local function updateCameraFieldOfView(targetFov: number)
	local tween = ActiveFovTween
	if tween then tween:Cancel() end
	ActiveFovTween = TweenService:Create(Camera, FOV_TWEEN_INFO, { FieldOfView = targetFov })
	local newTween = ActiveFovTween
	if newTween then newTween:Play() end
end

local function getMuzzlePart(): BasePart?
	if not CurrentTool then return nil end
	local muzzle = CurrentTool:FindFirstChild("Muzzle", true) or CurrentTool:FindFirstChild("Handle", true)
	if muzzle and muzzle:IsA("BasePart") then
		return muzzle
	end
	return CurrentTool:FindFirstChildWhichIsA("BasePart", true)
end

local function getMuzzleAttachment(): Attachment?
	if not CurrentTool then return nil end
	local muzzle = CurrentTool:FindFirstChild("Muzzle", true) or CurrentTool:FindFirstChild("Handle", true)
	if muzzle then
		if muzzle:IsA("Attachment") then return muzzle end
		if muzzle:IsA("BasePart") then
			local att = muzzle:FindFirstChildOfClass("Attachment") 
				or muzzle:FindFirstChild("MuzzleAttachment") :: Attachment?
			if att then return att end

			local newAtt = Instance.new("Attachment")
			newAtt.Name = "MuzzleAttachment"
			newAtt.Parent = muzzle
			return newAtt
		end
	end
	return nil
end

local function getEjectorAttachment(): Attachment?
	if not CurrentTool then return nil end
	local ejector = CurrentTool:FindFirstChild("Ejector", true) 
		or CurrentTool:FindFirstChild("EjectionPort", true) 
		or CurrentTool:FindFirstChild("Handle", true)

	if ejector then
		if ejector:IsA("Attachment") then
			return ejector
		elseif ejector:IsA("BasePart") then
			local att = ejector:FindFirstChild("EjectorAttachment") :: Attachment? 
				or ejector:FindFirstChildOfClass("Attachment")
			if att then return att end

			local newAtt = Instance.new("Attachment")
			newAtt.Name = "EjectorAttachment"
			newAtt.CFrame = CFrame.new(0.2, 0.2, 0)
			newAtt.Parent = ejector
			return newAtt
		end
	end
	return nil
end

local function calculateActiveSpreadAngle(): number
	if not CurrentWeaponConfig then return 0 end

	local baseAngle = IsAimingIntent and (CurrentWeaponConfig.AdsSpread or 0) or (CurrentWeaponConfig.BaseSpread or 0.02)
	local moveMult = 1.0

	local character = LocalPlayer.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if rootPart and humanoid then
			if Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude > 1.5 then
				moveMult *= (CurrentWeaponConfig.MovementSpreadMult or 1.5)
			end
			local state = humanoid:GetState()
			if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
				moveMult *= 1.5
			end
		end
	end

	return (baseAngle * moveMult) + CurrentBloom
end

local function getMouseWorldDestination(totalSpreadAngle: number?): Vector3
	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = Camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local filterList: { Instance } = {}
	local char = LocalPlayer.Character
	if char then
		table.insert(filterList, char)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterList

	local maxRange = CurrentWeaponConfig and CurrentWeaponConfig.Range or 400
	local baseDirection = unitRay.Direction

	if totalSpreadAngle and totalSpreadAngle > 0 then
		local randomAngle = math.rad(math.random(0, 360))
		local spreadRadius = math.tan(totalSpreadAngle) * math.sqrt(math.random())
		local camCFrame = Camera.CFrame
		local offset = (camCFrame.RightVector * math.cos(randomAngle) + camCFrame.UpVector * math.sin(randomAngle)) * spreadRadius
		baseDirection = (baseDirection + offset).Unit
	end

	local raycastResult = workspace:Raycast(unitRay.Origin, baseDirection * maxRange, raycastParams)
	return raycastResult and raycastResult.Position or (unitRay.Origin + (baseDirection * maxRange))
end

local function trackArmsToCamera()
	if IsFreeCamActive or not IsActive or not CurrentTool then return end

	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local pitchAngle = math.asin(math.clamp(Camera.CFrame.LookVector.Y, -0.99, 0.99))
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15

	if isR15 then
		local upperTorso = character:FindFirstChild("UpperTorso")
		if upperTorso then
			local waist = upperTorso:FindFirstChild("Waist") :: Motor6D?
			if waist then
				waist.Transform = CFrame.Angles(pitchAngle, 0, 0)
			end
		end
	else
		local torso = character:FindFirstChild("Torso")
		if torso then
			local rightShoulder = torso:FindFirstChild("Right Shoulder") :: Motor6D?
			local leftShoulder = torso:FindFirstChild("Left Shoulder") :: Motor6D?

			local head = character:FindFirstChild("Head")
			local neck = head and head:FindFirstChild("Neck") :: Motor6D?

			if rightShoulder and leftShoulder then
				rightShoulder.Transform = CFrame.Angles(-pitchAngle, 0, 0)
				leftShoulder.Transform = CFrame.Angles(pitchAngle, 0, 0)
			end
			if neck then
				neck.Transform = CFrame.Angles(-pitchAngle, 0, 0)
			end
		end
	end
end

-- [[ CORE WEAPON LOGIC ]]

local function triggerReloadSequence()
	if not CurrentWeaponName or not CurrentWeaponConfig then return end

	local ammoState = getOrCreateAmmoState(CurrentWeaponName, CurrentWeaponConfig)
	if ammoState.IsReloading then return end

	local maxMag = CurrentWeaponConfig.MagazineSize or CurrentWeaponConfig.ClipSize or 30
	if ammoState.CurrentAmmo >= maxMag or ammoState.ReserveAmmo <= 0 then return end

	ammoState.IsReloading = true
	IsShootingIntent = false

	CurrentReloadToken += 1
	local thisToken = CurrentReloadToken

	FpsInterface.UpdateAmmo("--", ammoState.ReserveAmmo)

	local muzzlePart = getMuzzlePart()
	ImpactFXManager.PlayReloadSound(muzzlePart and muzzlePart.Position or Vector3.zero, CurrentWeaponName)
	WeaponReloadEvent:FireServer(CurrentWeaponName)

	playReloadAnimation()

	local reloadDuration = CurrentWeaponConfig.ReloadDuration or CurrentWeaponConfig.ReloadTime or 2.0
	task.delay(reloadDuration, function()
		if CurrentReloadToken == thisToken then
			ammoState.IsReloading = false
		end
	end)
end

local function executeLocalWeaponDischarge()
	if IsFreeCamActive or not CurrentWeaponConfig or not CurrentWeaponName then return end

	local ammoState = getOrCreateAmmoState(CurrentWeaponName, CurrentWeaponConfig)
	if ammoState.IsReloading then return end

	local currentTime = os.clock()
	if (currentTime - LastFireTime) < (CurrentWeaponConfig.FireRate or 0.1) then return end

	if ammoState.CurrentAmmo <= 0 then
		IsShootingIntent = false
		if ammoState.ReserveAmmo > 0 then triggerReloadSequence() end
		return
	end

	LastFireTime = currentTime
	ammoState.CurrentAmmo -= 1
	FpsInterface.UpdateAmmo(ammoState.CurrentAmmo, ammoState.ReserveAmmo)

	local activeSpread = calculateActiveSpreadAngle()
	CurrentBloom = math.clamp(CurrentBloom + (CurrentWeaponConfig.BloomPerShot or 0.004), 0, CurrentWeaponConfig.MaxBloom or 0.08)

	local muzzlePart = getMuzzlePart()
	local startPos = muzzlePart and muzzlePart.Position or Vector3.zero

	local muzzleAtt = getMuzzleAttachment()
	local ejectorAtt = getEjectorAttachment()
	ImpactFXManager.RenderMuzzleFX(muzzleAtt, ejectorAtt, CurrentWeaponName)

	local bulletsPerShot = CurrentWeaponConfig.BulletsPerShot or CurrentWeaponConfig.PelletsPerShot or 1
	local maxPierceCount = CurrentWeaponConfig.MaxPierceCount or CurrentWeaponConfig.PenetrationCount or 0
	local maxRange = CurrentWeaponConfig.Range or 400

	local allBulletHits: { { { Instance: Instance?, Position: Vector3, Normal: Vector3?, Material: Enum.Material? } } } = {}
	local didAnyBulletHit = false

	for _ = 1, bulletsPerShot do
		local initialTarget = getMouseWorldDestination(activeSpread)
		local rayDirection = (initialTarget - startPos).Unit
		local currentOrigin = startPos
		local remainingDistance = maxRange
		local piercesRemaining = maxPierceCount

		local filterList: { Instance } = {}
		local char = LocalPlayer.Character
		if char then table.insert(filterList, char) end

		local singleBulletHits: { { Instance: Instance?, Position: Vector3, Normal: Vector3?, Material: Enum.Material? } } = {}

		while remainingDistance > 0 do
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = filterList

			local rayResult = workspace:Raycast(currentOrigin, rayDirection * remainingDistance, raycastParams)

			if not rayResult then
				local endPoint = currentOrigin + (rayDirection * remainingDistance)
				ImpactFXManager.RenderTracer(currentOrigin, endPoint)

				table.insert(singleBulletHits, {
					Instance = nil,
					Position = endPoint,
					Normal = -rayDirection,
					Material = nil
				})
				break
			end

			didAnyBulletHit = true

			ImpactFXManager.RenderTracer(currentOrigin, rayResult.Position)
			ImpactFXManager.RenderImpact(rayResult, CurrentWeaponName, true)

			table.insert(singleBulletHits, {
				Instance = rayResult.Instance,
				Position = rayResult.Position,
				Normal = rayResult.Normal,
				Material = rayResult.Material
			})

			if piercesRemaining > 0 and rayResult.Instance:GetAttribute("CanPierce") ~= false then
				piercesRemaining -= 1
				table.insert(filterList, rayResult.Instance)
				remainingDistance -= (rayResult.Position - currentOrigin).Magnitude
				currentOrigin = rayResult.Position + (rayDirection * 0.15)
			else
				break
			end
		end

		table.insert(allBulletHits, singleBulletHits)
	end

	ImpactFXManager.PlayGunshotSound(startPos, CurrentWeaponName, didAnyBulletHit)

	RecoilManager.FireRecoil(CurrentWeaponConfig.RecoilUp or 2.5, CurrentWeaponConfig.RecoilSide or 1.0, IsAimingIntent)
	CameraShakeManager.AddTrauma(IsAimingIntent and 0.15 or 0.3)
	CameraShakeManager.ShoveWeaponKick(Vector3.new(0, 0, CurrentWeaponConfig.KickBack or 0.2))

	WeaponFireEvent:FireServer(CurrentWeaponName, allBulletHits)
end

local function onInputFrameUpdate(deltaTime: number)
	if not IsActive or IsFreeCamActive or not CurrentWeaponConfig then return end

	if IsShootingIntent then
		executeLocalWeaponDischarge()
		if not CurrentWeaponConfig.IsAutomatic then
			IsShootingIntent = false
		end
	elseif CurrentBloom > 0 then
		CurrentBloom = math.clamp(CurrentBloom - ((CurrentWeaponConfig.BloomRecoveryRate or 0.2) * deltaTime), 0, CurrentWeaponConfig.MaxBloom or 0.08)
	end

	FpsInterface.UpdateCrosshair(calculateActiveSpreadAngle(), deltaTime)
end

-- [[ CONTEXT ACTIONS ]]

local function handleShootingAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not IsActive or IsFreeCamActive or not CurrentTool then return Enum.ContextActionResult.Pass end
	IsShootingIntent = (inputState == Enum.UserInputState.Begin)
	return Enum.ContextActionResult.Sink
end

local function handleAimingAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not IsActive or IsFreeCamActive or not CurrentTool then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin then
		IsAimingIntent = true
		updateCameraFieldOfView(TARGET_ADS_FOV)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		IsAimingIntent = false
		updateCameraFieldOfView(DEFAULT_FOV)
	end
	return Enum.ContextActionResult.Sink
end

local function handleReloadAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not IsActive or IsFreeCamActive or inputState ~= Enum.UserInputState.Begin or not CurrentTool then return Enum.ContextActionResult.Pass end
	triggerReloadSequence()
	return Enum.ContextActionResult.Sink
end

local function handleToggleFreeCamAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if not IsActive or inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	IsFreeCamActive = not IsFreeCamActive

	if IsFreeCamActive then
		LocalPlayer.CameraMode = Enum.CameraMode.Classic
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		IsShootingIntent = false
		IsAimingIntent = false
		updateCameraFieldOfView(DEFAULT_FOV)
	else
		LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
	return Enum.ContextActionResult.Sink
end

-- [[ SETUP & TEARDOWN ]]

local function onToolEquipped(tool: Tool)
	local config = WeaponConfig.GetWeaponData(tool.Name)
	if not config or config.WeaponType == "Melee" then return end

	CurrentTool = tool
	CurrentWeaponName = tool.Name
	CurrentWeaponConfig = config
	IsShootingIntent = false
	CurrentBloom = 0
	CurrentReloadToken += 1

	-- Retrieve existing ammo state or initialize new ammo tracking state for this weapon
	local ammoState = getOrCreateAmmoState(CurrentWeaponName, config)
	ammoState.IsReloading = false

	-- Immediately display the weapon's stored ammo count
	FpsInterface.UpdateAmmo(ammoState.CurrentAmmo, ammoState.ReserveAmmo)

	-- [[ PLAY HOLD ANIMATION ]]
	playHoldAnimation()
end

local function onToolUnequipped()
	stopAllWeaponAnimations()

	CurrentTool = nil
	CurrentWeaponName = nil
	CurrentWeaponConfig = nil
	IsShootingIntent = false
	IsAimingIntent = false
	CurrentBloom = 0
	CurrentReloadToken += 1
	updateCameraFieldOfView(DEFAULT_FOV)
end

local function setupCharacter(character: Model)
	for _, conn in TransparencyConnections do conn:Disconnect() end
	table.clear(TransparencyConnections)

	Connections.Equip = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolEquipped(child) end
	end)

	Connections.Unequip = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then onToolUnequipped() end
	end)

	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool then onToolEquipped(currentTool) end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	local whitelistedParts = (humanoid and humanoid.RigType == Enum.HumanoidRigType.R15)
		and {"LeftHand", "LeftLowerArm", "LeftUpperArm", "RightHand", "RightLowerArm", "RightUpperArm"}
		or {"Right Arm", "Left Arm"}

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and table.find(whitelistedParts, part.Name) then
			part.LocalTransparencyModifier = part.Transparency
			TransparencyConnections[part.Name] = part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
				part.LocalTransparencyModifier = part.Transparency
			end)
		end
	end

	RunService:UnbindFromRenderStep("FPS_ArmTracking")
	RunService:BindToRenderStep("FPS_ArmTracking", Enum.RenderPriority.Character.Value + 1, trackArmsToCamera)
end

-- [[ PUBLIC INTERFACE ]]

function WeaponInputManager.Init()
	if IsActive then return end
	IsActive = true
	IsFreeCamActive = false

	FpsInterface.Init()
	RecoilManager.Init()
	CameraShakeManager.Init()

	Camera = workspace.CurrentCamera or (workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: any) :: Camera
	Camera.FieldOfView = DEFAULT_FOV

	LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local char = LocalPlayer.Character
	if char then setupCharacter(char) end
	Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(setupCharacter)

	ContextActionService:BindActionAtPriority("FPS_PrimaryShoot", handleShootingAction, false, 2000, Enum.UserInputType.MouseButton1)
	ContextActionService:BindActionAtPriority("FPS_SecondaryAim", handleAimingAction, false, 2000, Enum.UserInputType.MouseButton2)
	ContextActionService:BindActionAtPriority("FPS_Reload", handleReloadAction, false, 2000, Enum.KeyCode.R)
	ContextActionService:BindActionAtPriority("FPS_ToggleFreeCam", handleToggleFreeCamAction, false, 2000, Enum.KeyCode.LeftAlt)

	Connections.AmmoSync = UpdateAmmoEvent.OnClientEvent:Connect(function(clipAmmo: number, totalAmmo: number)
		if not CurrentWeaponName or not CurrentWeaponConfig then return end

		local ammoState = getOrCreateAmmoState(CurrentWeaponName, CurrentWeaponConfig)
		ammoState.CurrentAmmo = clipAmmo
		ammoState.ReserveAmmo = totalAmmo

		if not ammoState.IsReloading then
			FpsInterface.UpdateAmmo(clipAmmo, totalAmmo)
		end
	end)

	Connections.PeerReplication = WeaponFireReplicated.OnClientEvent:Connect(function(firingPlayer: Player, weaponName: string, origin: Vector3, targetData: any)
		if firingPlayer == LocalPlayer then return end

		ImpactFXManager.PlayGunshotSound(origin, weaponName)

		if typeof(targetData) == "table" then
			for _, bulletHits in ipairs(targetData) do
				if typeof(bulletHits) == "table" then
					local prevPos = origin
					for _, hitData in ipairs(bulletHits) do
						local targetPos = typeof(hitData) == "table" and hitData.Position or hitData
						ImpactFXManager.RenderTracer(prevPos, targetPos)
						prevPos = targetPos
					end
				end
			end
		end
	end)

	Connections.Heartbeat = RunService.RenderStepped:Connect(onInputFrameUpdate)
end

function WeaponInputManager.Clean()
	IsActive = false
	IsShootingIntent = false
	IsAimingIntent = false
	IsFreeCamActive = false
	CurrentReloadToken += 1

	stopAllWeaponAnimations()
	RunService:UnbindFromRenderStep("FPS_ArmTracking")

	for _, conn in Connections do conn:Disconnect() end
	table.clear(Connections)

	for _, conn in TransparencyConnections do conn:Disconnect() end
	table.clear(TransparencyConnections)

	ContextActionService:UnbindAction("FPS_PrimaryShoot")
	ContextActionService:UnbindAction("FPS_SecondaryAim")
	ContextActionService:UnbindAction("FPS_Reload")
	ContextActionService:UnbindAction("FPS_ToggleFreeCam")

	updateCameraFieldOfView(DEFAULT_FOV)
	FpsInterface.Clean()
	RecoilManager.Clean()
	CameraShakeManager.Clean()

	LocalPlayer.CameraMode = Enum.CameraMode.Classic
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

return WeaponInputManager