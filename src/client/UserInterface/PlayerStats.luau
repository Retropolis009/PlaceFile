--!strict
local PlayerStats = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LocalPlayer = Players.LocalPlayer
end

-- [[ TWEEN STYLING CONFIGURATION ]]
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

-- [[ PERSISTENT STATIC UI CACHE ]]
local HPBar: Frame? = nil
local HPLabel: TextLabel? = nil
local EnergyBar: Frame? = nil
local EnergyLabel: TextLabel? = nil

-- Garbage collection tracker matrix to actively stop character/lifecycle connection leaks
local ConnectionCleanupStack: { RBXScriptConnection } = {}

-- [[ INLINE REUSABLE TWEEN HANDLE MATRIX ]]
local ActiveHPTween: Tween? = nil
local ActiveEnergyTween: Tween? = nil

-- [[ RUNTIME HUD RENDER UPDATES ]]

local function updateHealth(humanoid: Humanoid)
	if not HPBar or not HPLabel then return end

	local currentHealth = math.max(0, humanoid.Health)
	local maxHealth = humanoid.MaxHealth
	local healthRatio = math.clamp(currentHealth / (maxHealth > 0 and maxHealth or 1), 0, 1)

	if ActiveHPTween then ActiveHPTween:Cancel() end

	ActiveHPTween = TweenService:Create(HPBar, TWEEN_INFO, {
		Size = UDim2.new(healthRatio, 0, 1, 0)
	})
	ActiveHPTween:Play()

	HPLabel.Text = string.format("%d / %d", math.round(currentHealth), math.round(maxHealth))
end

local function updateEnergy(character: Model)
	if not EnergyBar or not EnergyLabel then return end

	local rawEnergy = character:GetAttribute("Energy")
	local currentEnergy = if typeof(rawEnergy) == "number" then rawEnergy else 100
	local maxEnergy = 100
	local energyRatio = math.clamp(currentEnergy / maxEnergy, 0, 1)

	if ActiveEnergyTween then ActiveEnergyTween:Cancel() end

	ActiveEnergyTween = TweenService:Create(EnergyBar, TWEEN_INFO, {
		Size = UDim2.new(energyRatio, 0, 1, 0)
	})
	ActiveEnergyTween:Play()

	EnergyLabel.Text = string.format("%d / %d", math.round(currentEnergy), maxEnergy)
end

-- Fetch and bind core layout dependencies once at game startup or mode switch
local function initializeHUDTargets(mainInterface: ScreenGui): boolean
	-- Matches exact layout requirement: MainInterface.Player.HP and Energy
	local playerFrame = mainInterface:WaitForChild("Player", 5) :: Frame?
	if not playerFrame then return false end

	local hpContainer = playerFrame:FindFirstChild("HP")
	local energyContainer = playerFrame:FindFirstChild("Energy")

	if hpContainer and energyContainer then
		HPBar = hpContainer:FindFirstChild("HPBar") :: Frame?
		HPLabel = hpContainer:FindFirstChild("HPLabel") :: TextLabel?
		EnergyBar = energyContainer:FindFirstChild("EnergyBar") :: Frame?
		EnergyLabel = energyContainer:FindFirstChild("EnergyLabel") :: TextLabel?

		return HPBar ~= nil and HPLabel ~= nil and EnergyBar ~= nil and EnergyLabel ~= nil
	end

	return false
end

local function setupCharacterHUD(character: Model, mainInterface: ScreenGui)
	-- 1. Purge older character bindings if setup runs back-to-back
	for i = 1, #ConnectionCleanupStack do
		if ConnectionCleanupStack[i] then
			ConnectionCleanupStack[i]:Disconnect()
		end
	end
	table.clear(ConnectionCleanupStack)

	-- 2. RESET CACHE INSTANCES - Wipes out old pointers
	HPBar = nil
	HPLabel = nil
	EnergyBar = nil
	EnergyLabel = nil

	-- 3. Query the playerGui hierarchy utilizing the bootstrapper's mainInterface reference
	if not initializeHUDTargets(mainInterface) then 
		warn("❌ [HUD System Error] Failed to locate fresh MainInterface elements on script setup!")
		return 
	end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid then
		table.insert(ConnectionCleanupStack, humanoid:GetPropertyChangedSignal("Health"):Connect(function()
			updateHealth(humanoid)
		end))
		table.insert(ConnectionCleanupStack, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			updateHealth(humanoid)
		end))

		updateHealth(humanoid)
	end

	table.insert(ConnectionCleanupStack, character:GetAttributeChangedSignal("Energy"):Connect(function()
		updateEnergy(character)
	end))

	updateEnergy(character)
end

-- [[ LIFECYCLE MANAGEMENT METHODS ]]

-- Activated by Bootstrapper when the game mode spins up
function PlayerStats.Init(mainInterface: ScreenGui)
	-- Handle character listening connection cycles through the active game mode
	local charAddedConn = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		if newCharacter:WaitForChild("Humanoid", 5) then
			task.defer(setupCharacterHUD, newCharacter, mainInterface)
		end
	end)
	table.insert(ConnectionCleanupStack, charAddedConn)

	-- Handle immediate loading if character already loaded
	if LocalPlayer.Character then
		local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid") :: Humanoid?
		if humanoid then
			task.spawn(setupCharacterHUD, LocalPlayer.Character, mainInterface)
		end
	end

	print("🛡️ PlayerStats HUD Module successfully initialized.")
end

-- Activated by Bootstrapper when a game mode shuts down or swaps
function PlayerStats.Clean()
	-- 1. Unbind and flush all lifecycle signals, stopping connection leaks across switches
	for i = 1, #ConnectionCleanupStack do
		if ConnectionCleanupStack[i] then
			ConnectionCleanupStack[i]:Disconnect()
		end
	end
	table.clear(ConnectionCleanupStack)

	-- 2. Kill running tweens safely
	if ActiveHPTween then ActiveHPTween:Cancel(); ActiveHPTween = nil end
	if ActiveEnergyTween then ActiveEnergyTween:Cancel(); ActiveEnergyTween = nil end

	-- 3. Nullify memory references 
	HPBar = nil
	HPLabel = nil
	EnergyBar = nil
	EnergyLabel = nil

	print("🚫 PlayerStats HUD Module successfully neutralized.")
end

return PlayerStats