--!strict
local HotbarController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("RemoteEvents")
local networkHandler = remoteEvents:WaitForChild("NetworkHandler") :: RemoteEvent
local forceSyncInput = remotes:WaitForChild("BindableEvents"):WaitForChild("ForceSyncInput") :: BindableEvent

-- Framework Access
local LocalPlayer = (Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()) :: Player
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local AbilityClient = StarterPlayerScripts:WaitForChild("Abilities")
local ClientAbilityClass = require(AbilityClient:WaitForChild("ClientAbilityClass") :: ModuleScript) :: any

-- Dynamic Asset Discovery Folders
local AbilitySystemFolder = ReplicatedStorage:WaitForChild("AbilitySystem")
local AbilitiesFolder = AbilitySystemFolder:WaitForChild("Abilities") :: Folder

-- [[ TYPE DEFINITIONS ]]
type CachedUiElements = { Overlay: Frame, TextLabel: TextLabel, LastTextValue: string }
type SpellModuleMetadata = { Name: string, IconAssetId: string?, [string]: any }
type UIControllerContract = { bindButton: (GuiButton, Frame?) -> (), toggleSlider: (Frame, boolean) -> (), [string]: any }
type AbilityInstance = { GetRemainingCooldown: (AbilityInstance) -> number, LastCastTime: number?, CooldownDuration: number?, [string]: any }
type ActiveInstancesMap = { [string]: AbilityInstance }

local EMPTY_ICON_FALLBACK: string = "rbxassetid://0"
local SLOTS = { "Slot1", "Slot2", "Slot3", "Slot4" }

-- Live state data buffers
local CurrentLoadout: { [string]: string } = {}
local AvailableSpellsPool: { [string]: string } = {}
local SelectedSourceSkill: string? = nil

-- Dynamic memory cache slots
local HUD_SLOTS_LIVE: { [string]: Frame } = {}
local MENU_SLOTS_LIVE: { [string]: Frame } = {}
local UI_CACHE_LIVE: { [string]: CachedUiElements } = {}

local isInteractionBound = false
local frameworkConnectionsBound = false 
local loopHaltWarningIssued = false

-- Garbage Collection Stacks
local LifecycleConnections: { RBXScriptConnection } = {}
local gridConnections: { [Instance]: RBXScriptConnection } = {}
local menuConnections: { [string]: RBXScriptConnection } = {} 
local RenderSteppedConnection: RBXScriptConnection? = nil

-- Forward reference declaration
local refreshInterfaceVisuals: (mainInterface: ScreenGui) -> ()

-- [[ LIVE ASSET MANIFEST LOOKUP CALCULATOR ]]
local function getAbilityIcon(abilityName: string): string
	if abilityName == "Empty" or abilityName == "" then return EMPTY_ICON_FALLBACK end

	local moduleScript = AbilitiesFolder:FindFirstChild(abilityName)
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local success, spellData = pcall(require, moduleScript)
		if success and typeof(spellData) == "table" then
			local metadata = spellData :: SpellModuleMetadata
			if typeof(metadata.IconAssetId) == "string" then
				return metadata.IconAssetId :: string
			else
				warn(string.format("[UI Icon Error] Missing or invalid IconAssetId for: %s", abilityName))
			end
		else
			warn(string.format("[UI Icon Error] Failed to require metadata for: %s", abilityName))
		end
	else
		warn(string.format("[UI Icon Warning] Module script not found in ReplicatedStorage for ability: %s", abilityName))
	end
	return EMPTY_ICON_FALLBACK
end

-- Dynamic connection handler for elements added to the AvailableGrid
local function bindGridChildElement(child: Instance, mainInterface: ScreenGui)
	if not child:IsA("Frame") then return end

	if gridConnections[child] then
		gridConnections[child]:Disconnect()
		gridConnections[child] = nil
	end

	local imageButton = child:WaitForChild("ImageButton", 5) :: ImageButton?
	if not imageButton then 
		warn(string.format("[Grid Binder Error] Timed out searching for 'ImageButton' inside frame slot: %s", child.Name))
		return 
	end

	local poolAbilityName = child:GetAttribute("AbilityName")
	if typeof(poolAbilityName) == "string" then
		AvailableSpellsPool[child.Name] = poolAbilityName :: string
		imageButton.Image = getAbilityIcon(poolAbilityName :: string)
	end

	local attrConnection = child:GetAttributeChangedSignal("AbilityName"):Connect(function()
		local updatedName = child:GetAttribute("AbilityName")
		if typeof(updatedName) == "string" then
			AvailableSpellsPool[child.Name] = updatedName
			imageButton.Image = getAbilityIcon(updatedName)
		end
	end)
	table.insert(LifecycleConnections, attrConnection)

	gridConnections[child] = imageButton.MouseButton1Click:Connect(function()
		local assignedAbility = child:GetAttribute("AbilityName")
		if typeof(assignedAbility) == "string" and assignedAbility ~= "" then
			SelectedSourceSkill = assignedAbility :: string
			print(string.format("[BINDING] Selected book skill: %s on client: %s", SelectedSourceSkill, LocalPlayer.Name))

			local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
			local availableGrid = spellbookMenu and spellbookMenu:WaitForChild("AvailableGrid", 5) :: Frame?

			if availableGrid then
				for _, element in ipairs(availableGrid:GetChildren()) do
					if element:IsA("Frame") then
						local btn = element:FindFirstChildOfClass("ImageButton") :: ImageButton?
						if btn then
							btn.ImageColor3 = (element.Name == child.Name) and Color3.fromRGB(0, 160, 255) or Color3.fromRGB(255, 255, 255)
						end
					end
				end
			end
		end
	end)
end

-- [[ MULTIPLAYER-SAFE GEOMETRY DISCOVERY ENGINE ]]
local function reacquireUiLayoutPointers(mainInterface: ScreenGui)
	print(string.format("[DISCOVERY] Clearing core frame lookup dictionaries for client: %s", LocalPlayer.Name))
	table.clear(HUD_SLOTS_LIVE)
	table.clear(MENU_SLOTS_LIVE)
	table.clear(UI_CACHE_LIVE)

	local hotbar = mainInterface:WaitForChild("Hotbar", 5) :: Frame?
	local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
	if not hotbar or not spellbookMenu then 
		warn(string.format("[UI Discovery Error] Hotbar or SpellbookMenu layout missing for client: %s", LocalPlayer.Name))
		return 
	end

	local equippedPanel = spellbookMenu:WaitForChild("EquippedPanel", 5) :: Frame?
	local availableGrid = spellbookMenu:WaitForChild("AvailableGrid", 5) :: ScrollingFrame?
	if not equippedPanel or not availableGrid then 
		warn(string.format("[UI Discovery Error] EquippedPanel or AvailableGrid missing for client: %s", LocalPlayer.Name))
		return 
	end

	for _, slotKey in ipairs(SLOTS) do
		local slotAttr = hotbar:GetAttribute(slotKey)
		CurrentLoadout[slotKey] = if typeof(CurrentLoadout[slotKey]) == "string" and CurrentLoadout[slotKey] ~= "" then CurrentLoadout[slotKey] else (if typeof(slotAttr) == "string" then (slotAttr :: string) else "Empty")
	end

	print(string.format("[DISCOVERY] Mapping unlocked inventory skills grid for client: %s", LocalPlayer.Name))
	for _, child in ipairs(availableGrid:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "TemplateSlot" then
			bindGridChildElement(child, mainInterface)
		end
	end

	for _, slotKey in ipairs(SLOTS) do
		local hudFrame = hotbar:WaitForChild(slotKey, 5) :: Frame?
		local menuFrame = equippedPanel:WaitForChild(slotKey, 5) :: Frame?

		if hudFrame then
			HUD_SLOTS_LIVE[slotKey] = hudFrame
			local overlay = hudFrame:WaitForChild("CooldownOverlay", 5) :: Frame?
			local textLabel = hudFrame:WaitForChild("CooldownText", 5) :: TextLabel?

			if overlay and textLabel then
				overlay.AnchorPoint = Vector2.new(0, 0)
				overlay.Size = UDim2.new(1, 0, 1, 0)
				UI_CACHE_LIVE[slotKey] = { Overlay = overlay, TextLabel = textLabel, LastTextValue = "" }
			else
				warn(string.format("[UI Scraper Critical] Missing CooldownOverlay or CooldownText in HUD %s!", slotKey))
			end
		else
			warn(string.format("[UI Scraper Critical] Could not locate Hotbar HUD Frame named: %s", slotKey))
		end

		if menuFrame then
			MENU_SLOTS_LIVE[slotKey] = menuFrame
		else
			warn(string.format("[UI Scraper Critical] Could not locate Spellbook Inventory Frame named: %s", slotKey))
		end
	end
	print(string.format("[DISCOVERY] Successfully re-cached layout boundaries for client: %s", LocalPlayer.Name))
end

-- [[ CORE REFRESH LOGIC ]]
function refreshInterfaceVisuals(mainInterface: ScreenGui)
	type AbilityMemoryBridgeContract = { ActiveInstances: { [string]: any }?, EquippedNames: { [string]: boolean }?, ListenerBound: boolean? }

	local Bridge = shared.__AbilityClassMemoryBridge :: AbilityMemoryBridgeContract?
	if Bridge and Bridge.ActiveInstances then table.clear(Bridge.ActiveInstances) end

	for slotKey, hudFrame in pairs(HUD_SLOTS_LIVE) do
		local abilityName = CurrentLoadout[slotKey] or "Empty"
		hudFrame:SetAttribute("AssignedAbility", abilityName)

		local iconLabel = hudFrame:WaitForChild("Icon", 2) :: ImageLabel?
		if iconLabel then
			iconLabel.Image = getAbilityIcon(abilityName)
		end

		local menuFrame = MENU_SLOTS_LIVE[slotKey]
		local menuButton = menuFrame and menuFrame:WaitForChild("ImageButton", 2) :: ImageButton?
		if menuButton then menuButton.Image = getAbilityIcon(abilityName) end

		if abilityName ~= "Empty" then
			local class = ClientAbilityClass :: any
			if class and typeof(class.EquipAbility) == "function" then
				local equipMethod = class.EquipAbility :: (string) -> ...any
				pcall(equipMethod, abilityName)
			end
		end
	end

	local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
	local availableGrid = spellbookMenu and spellbookMenu:WaitForChild("AvailableGrid", 5) :: Frame?

	if availableGrid then
		for slotKey, abilityName in pairs(AvailableSpellsPool) do
			local gridFrame = availableGrid:FindFirstChild(slotKey) :: Frame?
			if gridFrame then
				gridFrame:SetAttribute("AbilityName", abilityName)
				local gridButton = gridFrame:WaitForChild("ImageButton", 2) :: ImageButton?
				if gridButton then gridButton.Image = getAbilityIcon(abilityName) end
			end
		end
	end

	local liveCharacter = LocalPlayer.Character
	if liveCharacter then
		local class = ClientAbilityClass :: any
		if class and typeof(class.UpdateCharacterReference) == "function" then
			local syncMethod = class.UpdateCharacterReference :: (Instance) -> ...any
			pcall(syncMethod, liveCharacter)
		end
	end

	forceSyncInput:Fire()
end

local function highlightGridSelection(mainInterface: ScreenGui, selectedButtonName: string?)
	local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
	local availableGrid = spellbookMenu and spellbookMenu:WaitForChild("AvailableGrid", 5) :: Frame?

	if availableGrid then
		for _, child in ipairs(availableGrid:GetChildren()) do
			if child:IsA("Frame") then
				local btn = child:FindFirstChildOfClass("ImageButton") :: ImageButton?
				if btn then
					btn.ImageColor3 = (child.Name == selectedButtonName) and Color3.fromRGB(0, 160, 255) or Color3.fromRGB(255, 255, 255)
				end
			end
		end
	end
end

local function commitLoadoutSwap(mainInterface: ScreenGui, targetSlotKey: string, abilityName: string)
	print(string.format("[LIFECYCLE] Requesting hotbar loadout change on %s: [%s -> %s]", LocalPlayer.Name, targetSlotKey, abilityName))
	local previousOccupant = CurrentLoadout[targetSlotKey] or "Empty"

	for otherSlotKey, preEquippedSkill in pairs(CurrentLoadout) do
		if preEquippedSkill == abilityName then
			CurrentLoadout[otherSlotKey] = previousOccupant
			break
		end
	end

	if previousOccupant ~= "Empty" and previousOccupant ~= abilityName then
		local stillEquippedSomewhere = false
		for _, skill in pairs(CurrentLoadout) do
			if skill == previousOccupant then
				stillEquippedSomewhere = true
				break
			end
		end
		if not stillEquippedSomewhere then
			local class = ClientAbilityClass :: any
			if class and typeof(class.UnequipAbility) == "function" then
				local unequipMethod = class.UnequipAbility :: (string) -> ...any
				pcall(unequipMethod, previousOccupant)
			end
		end
	end
	CurrentLoadout[targetSlotKey] = abilityName
	refreshInterfaceVisuals(mainInterface)

	networkHandler:FireServer("UpdateLoadout", CurrentLoadout)
end

local function initUiInteractions(mainInterface: ScreenGui)
	if isInteractionBound then 
		print(string.format("[BINDING] Intercepted setup: Interaction clicks already bound for: %s", LocalPlayer.Name))
		return 
	end

	print(string.format("[BINDING] Constructing spellbook click interactions for client: %s", LocalPlayer.Name))
	local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
	if not spellbookMenu then 
		warn(string.format("[UI Interaction Critical Fail] Missing SpellbookMenu frame on client: %s", LocalPlayer.Name))
		return 
	end

	local visibilityFrame = spellbookMenu:WaitForChild("VisibilityFrame", 5) :: Frame?
	local toggleButton = visibilityFrame and visibilityFrame:WaitForChild("TextButton", 5) :: TextButton?
	if not toggleButton then 
		warn(string.format("[UI Interaction Critical Fail] Missing toggle TextButton on client: %s", LocalPlayer.Name))
		return 
	end

	-- Setup static slot selection listeners
	for slotKey, menuFrame in pairs(MENU_SLOTS_LIVE) do
		if menuConnections[slotKey] then menuConnections[slotKey]:Disconnect() end

		local imageButton = menuFrame:WaitForChild("ImageButton", 5) :: ImageButton?
		if imageButton then
			menuConnections[slotKey] = imageButton.MouseButton1Click:Connect(function()
				local currentSelection = SelectedSourceSkill
				if typeof(currentSelection) == "string" and currentSelection ~= "" then
					commitLoadoutSwap(mainInterface, slotKey, currentSelection :: string)
					SelectedSourceSkill = nil
					highlightGridSelection(mainInterface, nil)
				end
			end)
		end
	end

	-- Bind the external UI framework toggles once
	if not frameworkConnectionsBound then
		local success, UIController = pcall(require, ReplicatedStorage.Modules:WaitForChild("UIController", 5) :: ModuleScript)
		if success and typeof(UIController) == "table" then
			local controller = UIController :: UIControllerContract
			if typeof(controller.bindButton) == "function" and typeof(controller.toggleSlider) == "function" then
				controller.bindButton(toggleButton, spellbookMenu)
				controller.toggleSlider(spellbookMenu, false)
				frameworkConnectionsBound = true
				print(string.format("[BINDING] Loaded shared UIController module bindings successfully for client: %s", LocalPlayer.Name))
			else
				warn("[UI Interaction Critical Fail] UIController layout is missing required parameters!")
			end
		else
			warn(string.format("[UI Interaction Init Error] Shared ModuleScript 'UIController' could not be loaded!"))
		end
	end

	isInteractionBound = true
end

local function executeCompleteLifecycleReset(mainInterface: ScreenGui)
	print(string.format("[LIFECYCLE] Executing respawn recovery sequence for: %s", LocalPlayer.Name))

	isInteractionBound = false 
	SelectedSourceSkill = nil
	highlightGridSelection(mainInterface, nil)

	reacquireUiLayoutPointers(mainInterface)
	initUiInteractions(mainInterface)
	refreshInterfaceVisuals(mainInterface)
end

-- [[ LIFECYCLE MANAGEMENT METHODS ]]

function HotbarController.Init(mainInterface: ScreenGui)
	-- Start Cooldown Frame Stepped Calculation Render Process
	RenderSteppedConnection = RunService.RenderStepped:Connect(function()
		local Bridge = shared.__AbilityClassMemoryBridge
		local ActiveInstances: ActiveInstancesMap? = nil

		local class = ClientAbilityClass :: any
		if class and typeof(class.GetActiveInstances) == "function" then
			local data = class.GetActiveInstances()
			if typeof(data) == "table" then ActiveInstances = data :: ActiveInstancesMap end
		end

		if not ActiveInstances and Bridge and typeof(Bridge) == "table" and Bridge.ActiveInstances then
			ActiveInstances = Bridge.ActiveInstances :: ActiveInstancesMap
		end

		if not ActiveInstances then 
			if not loopHaltWarningIssued then
				warn(string.format("[Render Loop Warning] Missing frame lookup matrix. Cooldowns idling on client: %s", LocalPlayer.Name))
				loopHaltWarningIssued = true
			end
			return 
		end
		loopHaltWarningIssued = false
		local serverTime = workspace:GetServerTimeNow()

		for slotKey, frame in pairs(HUD_SLOTS_LIVE) do
			local assignedAbility = frame:GetAttribute("AssignedAbility")
			local cache = UI_CACHE_LIVE[slotKey]

			if not cache then continue end

				if typeof(assignedAbility) ~= "string" or assignedAbility == "Empty" then
					if cache.Overlay.BackgroundTransparency ~= 1 then
						cache.Overlay.Position = UDim2.new(0, 0, 1, 0)
						cache.Overlay.BackgroundTransparency = 1
						cache.TextLabel.Visible = false
						cache.LastTextValue = ""
					end
					continue
				end

				local currentAbilityName = assignedAbility :: string
				local abilityInstance = ActiveInstances[currentAbilityName]

				if abilityInstance then
					local remaining = 0
					local method = abilityInstance.GetRemainingCooldown

					if typeof(method) == "function" then
						local cdSuccess, cdVal = pcall(method :: (any) -> number, abilityInstance)
						remaining = if cdSuccess then cdVal else 0
					elseif abilityInstance.LastCastTime and abilityInstance.CooldownDuration then
						remaining = (abilityInstance.LastCastTime + abilityInstance.CooldownDuration) - serverTime
					end

					if remaining > 0 then
						local totalDuration = abilityInstance.CooldownDuration or 10
						local fillAmount = math.clamp(remaining / totalDuration, 0, 1)
						cache.Overlay.Position = UDim2.new(0, 0, 1 - fillAmount, 0)

						if cache.Overlay.BackgroundTransparency ~= 0.4 then
							cache.Overlay.BackgroundTransparency = 0.4
							cache.TextLabel.Visible = true
						end

						local formattedText = string.format("%.1fs", remaining)
						if cache.LastTextValue ~= formattedText then
							cache.LastTextValue = formattedText
							cache.TextLabel.Text = formattedText
						end
					else
						if cache.Overlay.BackgroundTransparency ~= 1 then
							cache.TextLabel.Visible = false
							cache.Overlay.BackgroundTransparency = 1
							cache.Overlay.Position = UDim2.new(0, 0, 1, 0)
							cache.LastTextValue = ""
						end
					end
				else
					if cache.Overlay.BackgroundTransparency ~= 1 then
						cache.TextLabel.Visible = false
						cache.Overlay.BackgroundTransparency = 1
						cache.Overlay.Position = UDim2.new(0, 0, 1, 0)
						cache.LastTextValue = ""
					end
				end
			end
		end)

	-- Safe Character Respawn Lifecycles Connection Tracking
	local charAddedConn = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
		print(string.format("[BOOTSTRAP] Character respawn cycle initiated for client: %s", LocalPlayer.Name))

		local humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
		local rootPart = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart?

		if humanoid and rootPart then
			task.wait(0.4) 
			task.defer(executeCompleteLifecycleReset, mainInterface)
		else
			warn(string.format("[Lifecycle Pipeline Error] Critical character components missing on respawn for: %s", LocalPlayer.Name))
		end
	end)
	table.insert(LifecycleConnections, charAddedConn)

	-- Server Inbound Replication Handshake Interceptor Setup
	local networkConn = networkHandler.OnClientEvent:Connect(function(actionHeader: any, arg1: any, arg2: any)
		if actionHeader == "SyncLoadoutPayload" and type(arg1) == "table" then
			print(string.format("[NET EVENT] Inbound loadout sync caught from server on client: %s", LocalPlayer.Name))
			local loadoutPayload = arg1 :: { [string]: string }
			local unlockedPool = arg2 :: { [string]: boolean }?

			for _, slotKey in ipairs(SLOTS) do
				local pVal = loadoutPayload[slotKey]
				CurrentLoadout[slotKey] = if typeof(pVal) == "string" then (pVal :: string) else "Empty"
			end

			local hotbar = mainInterface:WaitForChild("Hotbar", 5) :: Frame?
			if hotbar then
				for _, slotKey in ipairs(SLOTS) do
					hotbar:SetAttribute(slotKey, CurrentLoadout[slotKey])
				end
			end

			if unlockedPool and type(unlockedPool) == "table" then
				local spellbookMenu = mainInterface:WaitForChild("SpellbookMenu", 5) :: Frame?
				local availableGrid = spellbookMenu and spellbookMenu:WaitForChild("AvailableGrid", 5) :: Frame?
				local templateSlot = availableGrid and availableGrid:WaitForChild("TemplateSlot", 5) :: Frame?

				if availableGrid and templateSlot then
					for child, connection in pairs(gridConnections) do
						if connection then connection:Disconnect() end
						gridConnections[child] = nil
					end
					table.clear(AvailableSpellsPool) 

					for _, child in ipairs(availableGrid:GetChildren()) do
						if child:IsA("Frame") and child.Name ~= "TemplateSlot" then
							child:Destroy()
						end
					end

					for abilityName, isUnlocked in pairs(unlockedPool) do
						if isUnlocked and abilityName ~= "Empty" then
							local slotClone = templateSlot:Clone()
							slotClone.Name = abilityName 
							slotClone:SetAttribute("AbilityName", abilityName)
							slotClone.Visible = true
							slotClone.Parent = availableGrid

							bindGridChildElement(slotClone, mainInterface)
						end
					end
				end
			end
			reacquireUiLayoutPointers(mainInterface)
			initUiInteractions(mainInterface)
			refreshInterfaceVisuals(mainInterface)
		end
	end)
	table.insert(LifecycleConnections, networkConn)

	-- Immediate Execution Seed
	executeCompleteLifecycleReset(mainInterface)

	print(string.format("[NET EVENT] Dispatching 'RequestLoadoutSync' handshake to server from: %s", LocalPlayer.Name))
	networkHandler:FireServer("RequestLoadoutSync")
end

function HotbarController.Clean()
	-- 1. Sever Core Lifecycle Events
	if RenderSteppedConnection then
		RenderSteppedConnection:Disconnect()
		RenderSteppedConnection = nil
	end

	for i = 1, #LifecycleConnections do
		if LifecycleConnections[i] then LifecycleConnections[i]:Disconnect() end
	end
	table.clear(LifecycleConnections)

	-- 2. Sever Dynamic Interface Interception Matrices
	for child, connection in pairs(gridConnections) do
		if connection then connection:Disconnect() end
	end
	table.clear(gridConnections)

	for slotKey, connection in pairs(menuConnections) do
		if connection then connection:Disconnect() end
	end
	table.clear(menuConnections)

	-- 3. Scrub Live Dictionaries & Pointers
	table.clear(HUD_SLOTS_LIVE)
	table.clear(MENU_SLOTS_LIVE)
	table.clear(UI_CACHE_LIVE)
	table.clear(CurrentLoadout)
	table.clear(AvailableSpellsPool)

	SelectedSourceSkill = nil
	isInteractionBound = false
	loopHaltWarningIssued = false

	print("🔮 HotbarController Engine successfully neutralized.")
end

return HotbarController