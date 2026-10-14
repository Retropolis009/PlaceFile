--!strict
-- ReplicatedStorage.Modules.CameraEffects
local CameraEffects = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- [[ TYPE DEFINITIONS ]]
export type CameraEffectsModule = {
	Shake: (intensity: number, duration: number, frequency: number?) -> (),
	ZoomTo: (targetFov: number, duration: number, easingStyle: Enum.EasingStyle?) -> (),
	ResetZoom: (duration: number) -> (),
	FlashColor: (color: Color3, duration: number, maxOpacity: number?) -> (),
	Tilt: (angleDegrees: number, duration: number) -> (),
	ApplyOffsetRecoil: (offsetVector: Vector3, duration: number) -> (),
}

-- [[ PRIVATE STATE VARIABLES ]]
local Camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() and workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

local defaultFov: number = Camera and Camera.FieldOfView or 70

-- Shake Context Tracking
local shakeIntensity: number = 0
local shakeEndTime: number = 0
local shakeFrequency: number = 10

-- Tilt Context Tracking
local currentTiltAngle: number = 0
local targetTiltAngle: number = 0
local tiltLerpSpeed: number = 14 -- Slightly optimized speed step

-- Recoil Offset Tracking
local currentOffset: Vector3 = Vector3.zero
local targetOffset: Vector3 = Vector3.zero
local offsetRecoverySpeed: number = 8

-- Pipeline Active Token Tracker
local isPipelineActive = false

-- Monitor local camera changes safely
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
	if Camera then defaultFov = Camera.FieldOfView end
end)

-- [[ INTERNAL RENDER LOOP COMPOSER ]]
local function updateCameraEffects(deltaTime: number)
	if not Camera then return end

	local currentTime = os.clock()
	local shakeCFrame = CFrame.new()
	local tiltCFrame = CFrame.new()

	-- 1. Calculate Perlin Noise Shake Vector
	if currentTime < shakeEndTime then
		local seed = currentTime * shakeFrequency
		local xNoise = math.noise(seed, 0, 0) * shakeIntensity
		local yNoise = math.noise(0, seed, 0) * shakeIntensity
		local zNoise = math.noise(0, 0, seed) * shakeIntensity

		shakeCFrame = CFrame.new(xNoise, yNoise, zNoise) 
			* CFrame.Angles(yNoise * 0.03, xNoise * 0.03, zNoise * 0.01)
	end

	-- 2. Smoothly Interpolate Camera Tilt Roll Matrix
	if targetTiltAngle ~= 0 then
		currentTiltAngle = currentTiltAngle + (math.rad(targetTiltAngle) - currentTiltAngle) * math.clamp(deltaTime * tiltLerpSpeed, 0, 1)
	else
		-- Decelerate back to structural baseline
		currentTiltAngle = currentTiltAngle * math.max(0, 1 - (deltaTime * 12))
	end
	tiltCFrame = CFrame.Angles(0, 0, currentTiltAngle)

	-- 3. Interpolate Positional Recoil Offsets
	currentOffset = currentOffset:Lerp(targetOffset, math.clamp(deltaTime * 25, 0, 1))
	targetOffset = targetOffset:Lerp(Vector3.zero, math.clamp(deltaTime * offsetRecoverySpeed, 0, 1))

	local recoilCFrame = CFrame.new(currentOffset)

	-- [[ CRITICAL FIX ]]: Apply transformations ADDITIVELY relative to what Roblox already processed
	Camera.CFrame = Camera.CFrame * shakeCFrame * tiltCFrame * recoilCFrame
end

-- Safely hooks into the Roblox Render Pipeline without tearing down player mouse movement control
local function verifyRenderPipeline()
	if not isPipelineActive then
		isPipelineActive = true
		RunService:BindToRenderStep(
			"CameraEffectsPipeline",
			Enum.RenderPriority.Camera.Value + 1, -- Runs directly AFTER Roblox scripts handle mouse inputs
			updateCameraEffects
		)
	end
end

-- [[ PUBLIC API METHODS ]]

-- Trigger a Perlin-noise based camera shake instance
function CameraEffects.Shake(intensity: number, duration: number, frequency: number?)
	shakeIntensity = intensity
	shakeEndTime = os.clock() + duration
	shakeFrequency = frequency or 15
	verifyRenderPipeline()
end

-- Smoothly adjust camera Field Of View (Zoom Sequences)
function CameraEffects.ZoomTo(targetFov: number, duration: number, easingStyle: Enum.EasingStyle?)
	if not Camera then return end

	local tweenInfo = TweenInfo.new(
		duration,
		easingStyle or Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(Camera, tweenInfo, { FieldOfView = targetFov })
	tween:Play()
end

-- Revert Zoom back to normal configurations
function CameraEffects.ResetZoom(duration: number)
	CameraEffects.ZoomTo(defaultFov, duration)
end

-- Creates a full screen color flash tint
function CameraEffects.FlashColor(color: Color3, duration: number, maxOpacity: number?)
	if not LocalPlayer then return end
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 3) :: PlayerGui?
	if not playerGui then return end

	local flashGui = Instance.new("ScreenGui")
	flashGui.Name = "CamFlashEffect"
	flashGui.IgnoreGuiInset = true

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = maxOpacity or 0.4
	frame.Parent = flashGui

	flashGui.Parent = playerGui

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local tween = TweenService:Create(frame, tweenInfo, { BackgroundTransparency = 1 })

	tween.Completed:Connect(function()
		flashGui:Destroy()
	end)
	tween:Play()
end

-- Applies a smooth roll angle to the camera viewpoint
function CameraEffects.Tilt(angleDegrees: number, duration: number)
	targetTiltAngle = angleDegrees
	task.delay(duration, function()
		if targetTiltAngle == angleDegrees then
			targetTiltAngle = 0
		end
	end)
	verifyRenderPipeline()
end

-- Drives an immediate directional recoil vector shift (e.g. Teleport landing thud)
function CameraEffects.ApplyOffsetRecoil(offsetVector: Vector3, duration: number)
	targetOffset = offsetVector
	offsetRecoverySpeed = math.clamp(1 / duration, 1, 30)
	verifyRenderPipeline()
end

return CameraEffects :: CameraEffectsModule