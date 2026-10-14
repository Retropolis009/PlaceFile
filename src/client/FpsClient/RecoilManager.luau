--!strict
-- ReplicatedStorage.FpsSystem.Weapons.RecoilManager
local RecoilManager = {}

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Camera = Workspace.CurrentCamera or Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: Camera

-- [[ RECOIL STATE ]]
local TargetRecoil = Vector3.zero
local CurrentRecoil = Vector3.zero

local ShotCount = 0
local LastFireTime = 0

local IS_BOUND = false
local BIND_NAME = "FPS_RecoilManager_Render"

-- [[ RECOIL TUNING CONFIGURATION ]]
local RECOIL_SPRING_SPEED = 28.0   -- How fast current recoil snaps to target (Higher = punchier kick)
local RECOVERY_SPEED = 12.0        -- How fast target recoil decays back to zero when not firing
local AUTO_SPRAY_GROWTH = 0.12     -- Extra kick multiplier per consecutive shot in full-auto

local MAX_PITCH_CAP = 12.0         -- Max cumulative degrees camera can climb UP
local MAX_YAW_CAP = 4.0            -- Max degrees camera can drift horizontally
local MAX_ROLL_CAP = 1.5           -- Max degrees visual camera tilt

-- [[ RENDER LOOP ]]
local function onCameraRenderUpdate(dt: number)
	-- Reset shot counter if trigger was released for more than 0.25 seconds
	if os.clock() - LastFireTime > 0.25 then
		ShotCount = 0
	end

	-- Smoothly spring current recoil toward target recoil
	local springFactor = math.clamp(dt * RECOIL_SPRING_SPEED, 0, 1)
	local nextRecoil = CurrentRecoil:Lerp(TargetRecoil, springFactor)

	-- Calculate frame delta to apply as relative CFrame rotation
	local delta = nextRecoil - CurrentRecoil
	CurrentRecoil = nextRecoil

	-- ROBLOX CFRAME DIRECTION CORRECTIONS:
	-- -X pitch = Camera UP
	-- +Y yaw   = Camera LEFT / -Y = RIGHT
	-- +Z roll  = Camera TILT
	local pitchAngle = -math.rad(delta.X)
	local yawAngle = math.rad(delta.Y)
	local rollAngle = math.rad(delta.Z)

	Camera.CFrame = Camera.CFrame * CFrame.Angles(pitchAngle, yawAngle, rollAngle)

	-- Exponential decay recovery pulling TargetRecoil back to zero
	local decayFactor = math.exp(-RECOVERY_SPEED * dt)
	TargetRecoil = TargetRecoil * decayFactor
end

-- [[ PUBLIC METHODS ]]

function RecoilManager.FireRecoil(recoilUp: number, recoilSide: number, isAiming: boolean)
	local now = os.clock()

	-- Track continuous full-auto fire sequence
	if now - LastFireTime < 0.25 then
		ShotCount += 1
	else
		ShotCount = 1
	end
	LastFireTime = now

	local adsMultiplier = isAiming and 0.45 or 1.0
	local sprayMultiplier = 1.0 + (ShotCount * AUTO_SPRAY_GROWTH)

	local pitchKick = (recoilUp * 0.75) * adsMultiplier * sprayMultiplier
	local yawKick = ((math.random() - 0.5) * 2.0 * (recoilSide * 0.4)) * adsMultiplier * sprayMultiplier
	local rollKick = ((math.random() - 0.5) * 2.0 * (recoilSide * 0.2)) * adsMultiplier

	local newPitch = math.clamp(TargetRecoil.X + pitchKick, 0, MAX_PITCH_CAP)
	local newYaw = math.clamp(TargetRecoil.Y + yawKick, -MAX_YAW_CAP, MAX_YAW_CAP)
	local newRoll = math.clamp(TargetRecoil.Z + rollKick, -MAX_ROLL_CAP, MAX_ROLL_CAP)

	TargetRecoil = Vector3.new(newPitch, newYaw, newRoll)
end

function RecoilManager.Init()
	if IS_BOUND then return end

	TargetRecoil = Vector3.zero
	CurrentRecoil = Vector3.zero
	ShotCount = 0
	LastFireTime = 0
	IS_BOUND = true

	RunService:BindToRenderStep(
		BIND_NAME,
		Enum.RenderPriority.Camera.Value + 100,
		onCameraRenderUpdate
	)
end

function RecoilManager.Clean()
	if IS_BOUND then
		RunService:UnbindFromRenderStep(BIND_NAME)
		IS_BOUND = false
	end

	TargetRecoil = Vector3.zero
	CurrentRecoil = Vector3.zero
	ShotCount = 0
	LastFireTime = 0
end

return RecoilManager