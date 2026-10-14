--!strict
-- ReplicatedStorage.FpsSystem.ImpactFXManager
local ImpactFXManager = {}

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FpsSystem = ReplicatedStorage:WaitForChild("FpsSystem")
local WeaponsFolder = FpsSystem:WaitForChild("Weapons")
local ShellCasingsFolder = FpsSystem:WaitForChild("ShellCasing")
local WeaponConfig = require(WeaponsFolder:WaitForChild("WeaponConfig")) :: any

local IMPACT_SOUNDS: { [Enum.Material]: string } = {
}

local function playSpatialSound(soundId: string, position: Vector3, volume: number, maxDistance: number, pitch: number?)
	if not soundId or soundId == "" then return end

	local soundPart = Instance.new("Part")
	soundPart.Name = "SpatialAudioNode"
	soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
	soundPart.Position = position
	soundPart.Anchored = true
	soundPart.Transparency = 1
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = maxDistance
	sound.PlaybackSpeed = pitch or 1.0
	sound.Parent = soundPart
	sound:Play()

	Debris:AddItem(soundPart, 3)
end

function ImpactFXManager.RenderTracer(startPos: Vector3, endPos: Vector3)
	local distance = (endPos - startPos).Magnitude
	if distance < 1 then return end

	local tracerPart = Instance.new("Part")
	tracerPart.Name = "BulletTracer"
	tracerPart.Anchored = true
	tracerPart.CanCollide = false
	tracerPart.CanQuery = false
	tracerPart.Size = Vector3.new(0.08, 0.08, distance)
	tracerPart.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -distance / 2)
	tracerPart.Color = Color3.fromRGB(255, 220, 140)
	tracerPart.Material = Enum.Material.Neon
	tracerPart.Transparency = 0.15
	tracerPart.Parent = Workspace

	local fadeTween = TweenService:Create(
		tracerPart,
		TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Size = Vector3.new(0.01, 0.01, distance) }
	)
	fadeTween:Play()
	Debris:AddItem(tracerPart, 0.07)
end

function ImpactFXManager.RenderImpact(hitResult: RaycastResult, _weaponName: string?, isProminent: boolean?)
	local hitPart = hitResult.Instance
	local hitPos = hitResult.Position
	local hitNormal = hitResult.Normal

	local hitModel = hitPart:FindFirstAncestorOfClass("Model")
	local hitHumanoid = hitModel and hitModel:FindFirstChildOfClass("Humanoid")

	if hitHumanoid then
		return
	end

	local bulletHole = Instance.new("Part")
	bulletHole.Name = "BulletHole"
	bulletHole.Size = Vector3.new(0.2, 0.2, 0.01)
	bulletHole.Color = Color3.fromRGB(30, 30, 30)
	bulletHole.Material = Enum.Material.SmoothPlastic
	bulletHole.Transparency = 0.1
	bulletHole.Anchored = true
	bulletHole.CanCollide = false
	bulletHole.CanQuery = false
	bulletHole.CFrame = CFrame.lookAt(hitPos, hitPos + hitNormal)
	bulletHole.Parent = Workspace

	Debris:AddItem(bulletHole, 8)

	local soundId = IMPACT_SOUNDS[hitResult.Material]
	if soundId and soundId ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = isProminent and 1.2 or 0.5
		sound.RollOffMaxDistance = isProminent and 200 or 150
		sound.PlaybackSpeed = math.random(94, 106) / 100
		sound.Parent = bulletHole
		sound:Play()
	end

	local attachment = Instance.new("Attachment")
	attachment.CFrame = CFrame.lookAt(Vector3.zero, hitNormal)
	attachment.Parent = bulletHole

	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxassetid://258129763"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 220, 130))
	particles.LightEmission = 1.0
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Lifetime = NumberRange.new(0.03, 0.06)
	particles.Rate = 0
	particles.Enabled = false
	particles.Speed = NumberRange.new(10, 24)
	particles.SpreadAngle = Vector2.new(30, 30)
	particles.Parent = attachment

	particles:Emit(5)
end

function ImpactFXManager.PlayGunshotSound(origin: Vector3, weaponName: string, isDampened: boolean?)
	local config = WeaponConfig.GetWeaponData(weaponName)
	if not config or not config.Sounds or not config.Sounds.Gunshot or config.Sounds.Gunshot == "" then return end

	local volume = isDampened and 0.35 or 0.8
	local pitch = isDampened and 0.88 or 1.0

	playSpatialSound(config.Sounds.Gunshot, origin, volume, 300, pitch)
end

function ImpactFXManager.PlayReloadSound(origin: Vector3, weaponName: string)
	local config = WeaponConfig.GetWeaponData(weaponName)
	if not config or not config.Sounds or not config.Sounds.Reload or config.Sounds.Reload == "" then return end

	playSpatialSound(config.Sounds.Reload, origin, 0.7, 100)
end

function ImpactFXManager.RenderMuzzleFlash(target: Instance?, _weaponName: string?)
	if not target then return end

	local attachment: Attachment? = nil
	if target:IsA("Attachment") then
		attachment = target
	elseif target:IsA("BasePart") then
		attachment = target:FindFirstChildOfClass("Attachment") 
			or target:FindFirstChild("MuzzleAttachment") :: Attachment?
	end

	if not attachment then return end

	local emitter = attachment:FindFirstChild("FlashEmitter") :: ParticleEmitter
	if not emitter then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "FlashEmitter"
		emitter.Texture = "rbxassetid://258129763"
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 120)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 50, 0))
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.0),
			NumberSequenceKeypoint.new(1, 0)
		})
		emitter.LightEmission = 1.0
		emitter.LightInfluence = 0.0
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Speed = NumberRange.new(0.01)
		emitter.Lifetime = NumberRange.new(0.03, 0.05)
		emitter.LockedToPart = true
		emitter.Orientation = Enum.ParticleOrientation.FacingCamera
		emitter.Parent = attachment
	end

	emitter:Emit(1)

	local flashLight = attachment:FindFirstChildOfClass("PointLight")
	if flashLight then
		flashLight.Enabled = true
		task.delay(0.02, function()
			if flashLight and flashLight.Parent then
				flashLight.Enabled = false
			end
		end)
	end
end

function ImpactFXManager.EjectCasing(ejectorAttachment: Attachment, casingType: string?)
	if not ejectorAttachment or not casingType then return end

	local template = ShellCasingsFolder:FindFirstChild(casingType)
	if not template or not template:IsA("BasePart") then return end

	local casing = template:Clone()
	casing.Name = "BulletCasing"
	casing.CanCollide = true
	casing.CanQuery = false
	casing.CFrame = ejectorAttachment.WorldCFrame
	casing.Parent = Workspace

	local ejectVector = (ejectorAttachment.WorldCFrame.RightVector * 10)
		+ (ejectorAttachment.WorldCFrame.UpVector * 5)
		+ (ejectorAttachment.WorldCFrame.LookVector * -2)
		+ Vector3.new(math.random(-1, 1), math.random(1, 2), math.random(-1, 1))

	casing.AssemblyLinearVelocity = ejectVector
	casing.AssemblyAngularVelocity = Vector3.new(
		math.random(-40, 40),
		math.random(-40, 40),
		math.random(-40, 40)
	)

	Debris:AddItem(casing, 2)
end

function ImpactFXManager.RenderMuzzleFX(muzzleAttachment: Attachment?, ejectorAttachment: Attachment?, weaponName: string?)
	if muzzleAttachment then
		ImpactFXManager.RenderMuzzleFlash(muzzleAttachment, weaponName)
	end
	if ejectorAttachment and weaponName then
		local config = WeaponConfig.GetWeaponData(weaponName)
		if config and config.CasingType then
			ImpactFXManager.EjectCasing(ejectorAttachment, config.CasingType)
		end
	end
end

return ImpactFXManager