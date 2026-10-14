--!strict
-- ReplicatedStorage.FpsSystem.Weapons.CameraShakeManager
local CameraShakeManager = {}

local RunService = game:GetService("RunService")

-- [[ EXPORTED TYPES ]]
export type Spring = {
	Target: Vector3,
	Position: Vector3,
	Velocity: Vector3,
	Mass: number,
	Damping: number,
	Stiffness: number,
	Shove: (self: Spring, force: Vector3) -> (),
	Update: (self: Spring, dt: number) -> Vector3,
}

type SpringImpl = {
	__index: SpringImpl,
	new: (mass: number, damping: number, stiffness: number) -> Spring,
	Shove: (self: Spring, force: Vector3) -> (),
	Update: (self: Spring, dt: number) -> Vector3,
}

-- [[ SPRING CLASS IMPLEMENTATION ]]
local SpringClass = {} :: SpringImpl
SpringClass.__index = SpringClass

function SpringClass.new(mass: number, damping: number, stiffness: number): Spring
	local self = setmetatable({}, SpringClass)
	self.Target = Vector3.zero
	self.Position = Vector3.zero
	self.Velocity = Vector3.zero
	self.Mass = mass
	self.Damping = damping
	self.Stiffness = stiffness
	return (self :: any) :: Spring
end

function SpringClass.Shove(self: Spring, force: Vector3)
	self.Velocity += force
end

function SpringClass.Update(self: Spring, dt: number): Vector3
	local force = (self.Target - self.Position) * self.Stiffness
	local dampingForce = self.Velocity * self.Damping
	local acceleration = (force - dampingForce) / self.Mass

	self.Velocity += acceleration * dt
	self.Position += self.Velocity * dt
	return self.Position
end

-- [[ MODULE STATE ]]
local WeaponPosKickSpring: Spring = SpringClass.new(1, 28, 260)
local RenderConnection: RBXScriptConnection? = nil
local NoiseTrauma = 0
local Seed = math.random(1, 1000)

-- [[ PUBLIC METHODS ]]

-- Call this on weapon fire or explosions (intensity: 0.1 to 1.0)
function CameraShakeManager.AddTrauma(amount: number)
	NoiseTrauma = math.clamp(NoiseTrauma + amount, 0, 1)
end

-- Positional kick impulse for the weapon model (e.g., Vector3.new(0, 0, 0.15) for backward kick)
function CameraShakeManager.ShoveWeaponKick(kickVector: Vector3)
	WeaponPosKickSpring:Shove(kickVector)
end

-- Returns the current viewmodel positional recoil offset
function CameraShakeManager.GetWeaponOffset(): Vector3
	return WeaponPosKickSpring.Position
end

-- Returns the current camera shake rotation CFrame offset without mutating the camera
function CameraShakeManager.GetShakeOffset(): CFrame
	if NoiseTrauma <= 0 then
		return CFrame.identity
	end

	local shakeIntensity = NoiseTrauma * NoiseTrauma
	local timePoint = os.clock() * 20
	local pitch = (math.noise(Seed, timePoint, 0) * 2 - 1) * 3 * shakeIntensity
	local yaw = (math.noise(Seed + 1, timePoint, 0) * 2 - 1) * 3 * shakeIntensity
	local roll = (math.noise(Seed + 2, timePoint, 0) * 2 - 1) * 2 * shakeIntensity

	return CFrame.Angles(
		math.rad(pitch),
		math.rad(yaw),
		math.rad(roll)
	)
end

function CameraShakeManager.Init()
	if RenderConnection then return end

	RenderConnection = RunService.RenderStepped:Connect(function(dt: number)
		-- Update positional kick spring
		WeaponPosKickSpring:Update(dt)

		-- Decay trauma over time
		if NoiseTrauma > 0 then
			NoiseTrauma = math.clamp(NoiseTrauma - (dt * 1.5), 0, 1)
		end
	end)
end

function CameraShakeManager.Clean()
	if RenderConnection then
		RenderConnection:Disconnect()
		RenderConnection = nil
	end
	NoiseTrauma = 0
end

return CameraShakeManager