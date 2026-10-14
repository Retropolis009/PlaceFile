--!strict
-- StarterPlayer.StarterPlayerScripts.AbilityClient.FpsClient.RaycastVisualizer
local RaycastVisualizer = {}

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local TRACER_COLOR = Color3.fromRGB(255, 220, 100) -- Light neon yellow
local TRACER_DURATION = 0.12
local TWEEN_SETTINGS = TweenInfo.new(TRACER_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function RaycastVisualizer.DrawCosmeticTracer(origin: Vector3, destination: Vector3)
	local distance = (destination - origin).Magnitude
	if distance <= 0.5 then return end

	local tracerPart = Instance.new("Part")
	tracerPart.Name = "BulletTracerEffect"
	tracerPart.Material = Enum.Material.Neon
	tracerPart.Color = TRACER_COLOR
	tracerPart.Transparency = 0.05
	tracerPart.Anchored = true
	tracerPart.CanCollide = false
	tracerPart.CanTouch = false
	tracerPart.CanQuery = false

	-- Shape the cylinder container along the bullet flight path vector
	tracerPart.Size = Vector3.new(0.08, 0.08, distance)
	tracerPart.CFrame = CFrame.lookAt(origin, destination) * CFrame.new(0, 0, -distance / 2)
	tracerPart.Parent = workspace

	-- Quickly fade out and shrink the tracer block to simulate bullet speed
	local visualTween = TweenService:Create(tracerPart, TWEEN_SETTINGS, {
		Transparency = 1,
		Size = Vector3.new(0, 0, distance)
	})

	visualTween:Play()
	Debris:AddItem(tracerPart, TRACER_DURATION)
end

return RaycastVisualizer