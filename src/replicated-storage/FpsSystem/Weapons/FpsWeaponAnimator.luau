--!strict
-- StarterPlayer.StarterPlayerScripts.AbilityClient.FpsClient.Modules.FpsWeaponAnimator
local FpsWeaponAnimator = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer or (Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: any) :: Player

local rightMotor: Motor6D? = nil
local leftMotor: Motor6D? = nil
local renderConnection: RBXScriptConnection? = nil

-- Destroys Roblox's automatic C++ RightGrip Weld
local function destroyDefaultGrip(character: Model)
	local rightArm = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if rightArm then
		local grip = rightArm:FindFirstChild("RightGrip")
		if grip then
			grip:Destroy()
		end
	end
end

function FpsWeaponAnimator.EquipTwoHanded(weaponModel: Model)
	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local rightArm = (isR15 and character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	local leftArm = (isR15 and character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")) :: BasePart?

	if not rightArm or not leftArm then return end

	local handle = weaponModel:FindFirstChild("Handle", true) :: BasePart?
	if not handle or not handle:IsA("BasePart") then return end

	handle.Anchored = false
	handle.CanCollide = false

	-- 1. Kill standard grip
	destroyDefaultGrip(character)

	-- 2. Create Right Arm -> Weapon Motor6D
	rightMotor = Instance.new("Motor6D")
	rightMotor.Name = "RightToolMotor"
	rightMotor.Part0 = rightArm
	rightMotor.Part1 = handle
	rightMotor.C0 = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	rightMotor.C1 = CFrame.new()
	rightMotor.Parent = rightArm

	-- 3. Create Left Arm -> Weapon Motor6D
	local leftGripAtt = handle:FindFirstChild("LeftGrip", true) :: Attachment?

	leftMotor = Instance.new("Motor6D")
	leftMotor.Name = "LeftToolMotor"
	leftMotor.Part0 = leftArm
	leftMotor.Part1 = handle
	leftMotor.C0 = CFrame.new()

	if leftGripAtt then
		leftMotor.C1 = leftGripAtt.CFrame
	else
		-- Default forward position for left hand on barrel
		leftMotor.C1 = CFrame.new(-0.5, 0, -1.2) * CFrame.Angles(0, math.rad(20), 0)
	end
	leftMotor.Parent = leftArm

	-- 4. Continuous RenderStepped listener to prevent engine weld re-creation
	if renderConnection then renderConnection:Disconnect() end
	renderConnection = RunService.RenderStepped:Connect(function()
		destroyDefaultGrip(character)
	end)
end

function FpsWeaponAnimator.Unequip()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	if rightMotor then
		rightMotor:Destroy()
		rightMotor = nil
	end

	if leftMotor then
		leftMotor:Destroy()
		leftMotor = nil
	end
end

return FpsWeaponAnimator