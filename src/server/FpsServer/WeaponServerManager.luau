--!strict
-- ServerScriptService.FpsServer.WeaponServerManager

local WeaponServerManager = {}

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

-- Services & Framework Modules
local FpsSystem = ReplicatedStorage:WaitForChild("FpsSystem")
local WeaponsFolder = FpsSystem:WaitForChild("Weapons")
local WeaponConfig = require(WeaponsFolder:WaitForChild("WeaponConfig")) :: any

local HitValidation = require(ServerScriptService:WaitForChild("FpsServer"):WaitForChild("HitValidation")) :: any

-- Network
local Remotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local WeaponFireEvent = Remotes:WaitForChild("WeaponFire") :: RemoteEvent
local WeaponReloadEvent = Remotes:WaitForChild("WeaponReload") :: RemoteEvent
local WeaponFireReplicated = Remotes:WaitForChild("WeaponFireReplicated") :: RemoteEvent
local UpdateAmmoEvent = Remotes:WaitForChild("UpdateAmmo") :: RemoteEvent

-- Constants & Configurations
local MATERIAL_PENETRATION_LIMITS: { [Enum.Material]: number } = {
	[Enum.Material.Glass] = 8.0,
	[Enum.Material.Fabric] = 6.0,
	[Enum.Material.SmoothPlastic] = 3.5,
	[Enum.Material.Plastic] = 3.5,
	[Enum.Material.Wood] = 3.0,
	[Enum.Material.WoodPlanks] = 3.0,
	[Enum.Material.Plaster] = 3.0,
	[Enum.Material.Cardboard] = 5.0,

	[Enum.Material.Concrete] = 0,
	[Enum.Material.Brick] = 0,
	[Enum.Material.Cobblestone] = 0,
	[Enum.Material.CorrodedMetal] = 0,
	[Enum.Material.DiamondPlate] = 0,
	[Enum.Material.Metal] = 0,
}
local DEFAULT_PENETRATION_LIMIT = 2.0

-- Types
type AmmoData = {
	CurrentAmmo: number,
	ReserveAmmo: number,
	IsReloading: boolean,
	ReloadToken: number,
}

type PlayerWeaponState = {
	LastFired: number,
	Inventory: {
		[string]: AmmoData
	}
}

type PenetratingHitResult = {
	HitPart: BasePart,
	HitPosition: Vector3,
	HitNormal: Vector3,
	DamageMultiplier: number,
}

-- Private State
local PlayerStates: { [Player]: PlayerWeaponState } = {}
local IsSystemActive = false

local FireNetworkConnection: RBXScriptConnection? = nil
local ReloadNetworkConnection: RBXScriptConnection? = nil
local PlayerRemovingConnection: RBXScriptConnection? = nil
local CharacterAddedConnections: { [Player]: RBXScriptConnection } = {}

-- Private Helper Functions
local function getOrCreatePlayerState(player: Player): PlayerWeaponState
	if not PlayerStates[player] then
		PlayerStates[player] = {
			LastFired = 0,
			Inventory = {},
		}
	end
	return PlayerStates[player]
end

local function getMaxMagazineSize(config: any): number
	return config.MagazineSize or config.ClipSize or config.MaxAmmo or config.MaxClip or 30
end

local function getOrCreateWeaponAmmo(player: Player, weaponName: string): AmmoData?
	local state = getOrCreatePlayerState(player)
	local config = WeaponConfig.GetWeaponData(weaponName)
	if not config then return nil end

	if not state.Inventory[weaponName] then
		local magSize: number = getMaxMagazineSize(config)
		local reserveSize: number = config.MaxReserveAmmo or config.ReserveAmmo or (magSize * 3)

		state.Inventory[weaponName] = {
			CurrentAmmo = magSize,
			ReserveAmmo = reserveSize,
			IsReloading = false,
			ReloadToken = 0,
		}
	end

	return state.Inventory[weaponName]
end

local function syncAmmoToClient(player: Player, currentAmmo: number, reserveAmmo: number)
	UpdateAmmoEvent:FireClient(player, currentAmmo, reserveAmmo)
end

local function findHitHumanoid(hitPart: BasePart): (Humanoid?, Model?)
	local current: Instance? = hitPart
	while current and current ~= Workspace do
		local hum = current:FindFirstChildOfClass("Humanoid")
		if hum and current:IsA("Model") then
			return hum, current :: Model
		end
		current = current.Parent
	end
	return nil, nil
end

local function getShootingOrigin(character: Model, weaponName: string): Vector3
	local tool = character:FindFirstChild(weaponName)
	if tool and tool:IsA("Tool") then
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		if handle then return handle.Position end
	end

	local head = character:FindFirstChild("Head") :: BasePart?
	if head then return head.Position end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then 
		return rootPart.Position + Vector3.new(0, 1.5, 0) 
	end

	return Vector3.zero
end

local function calculateDamageMultiplier(hitPart: BasePart, headshotMult: number): number
	local partName = hitPart.Name
	if partName == "Head" then
		return headshotMult
	elseif partName == "UpperTorso" or partName == "LowerTorso" or partName == "Torso" then
		return 1.0
	else
		return 0.75
	end
end

local function applyCreatorTag(targetHumanoid: Humanoid, attacker: Player)
	local oldTag = targetHumanoid:FindFirstChild("creator")
	if oldTag then oldTag:Destroy() end

	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Name = "creator"
	creatorTag.Value = attacker
	creatorTag.Parent = targetHumanoid
	Debris:AddItem(creatorTag, 2)
end

local function castPenetratingRay(
	origin: Vector3, 
	direction: Vector3, 
	maxDistance: number, 
	baseIgnoreList: { Instance }
): { PenetratingHitResult }

	local hits: { PenetratingHitResult } = {}
	local currentOrigin = origin
	local currentDirection = direction.Unit
	local remainingDistance = maxDistance
	local currentDamageMult = 1.0

	local ignoreList = table.clone(baseIgnoreList)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	while remainingDistance > 0 do
		rayParams.FilterDescendantsInstances = ignoreList
		local rayResult = Workspace:Raycast(currentOrigin, currentDirection * remainingDistance, rayParams)

		if not rayResult or not rayResult.Instance:IsA("BasePart") then 
			break 
		end

		local hitPart = rayResult.Instance
		local hitPos = rayResult.Position
		local hitMaterial = rayResult.Material

		table.insert(hits, {
			HitPart = hitPart,
			HitPosition = hitPos,
			HitNormal = rayResult.Normal,
			DamageMultiplier = currentDamageMult,
		})

		local hitHumanoid, _ = findHitHumanoid(hitPart)
		if hitHumanoid then
			break
		end

		local maxThickness = MATERIAL_PENETRATION_LIMITS[hitMaterial] or DEFAULT_PENETRATION_LIMIT
		if maxThickness <= 0 then
			break
		end

		local exitProbeParams = RaycastParams.new()
		exitProbeParams.FilterType = Enum.RaycastFilterType.Include
		exitProbeParams.FilterDescendantsInstances = { hitPart }

		local probeStart = hitPos + (currentDirection * (maxThickness + 0.05))
		local probeResult = Workspace:Raycast(probeStart, -currentDirection * (maxThickness + 0.1), exitProbeParams)

		local wallThickness = maxThickness + 1

		if probeResult then
			wallThickness = (probeResult.Position - hitPos).Magnitude
		else
			local localOrigin = hitPart.CFrame:PointToObjectSpace(hitPos)
			local localDir = hitPart.CFrame:VectorToObjectSpace(currentDirection)
			local halfSize = hitPart.Size * 0.5

			local tx1 = (-halfSize.X - localOrigin.X) / (localDir.X ~= 0 and localDir.X or 1e-5)
			local tx2 = (halfSize.X - localOrigin.X) / (localDir.X ~= 0 and localDir.X or 1e-5)
			local ty1 = (-halfSize.Y - localOrigin.Y) / (localDir.Y ~= 0 and localDir.Y or 1e-5)
			local ty2 = (halfSize.Y - localOrigin.Y) / (localDir.Y ~= 0 and localDir.Y or 1e-5)
			local tz1 = (-halfSize.Z - localOrigin.Z) / (localDir.Z ~= 0 and localDir.Z or 1e-5)
			local tz2 = (halfSize.Z - localOrigin.Z) / (localDir.Z ~= 0 and localDir.Z or 1e-5)

			local tmin = math.max(math.min(tx1, tx2), math.min(ty1, ty2), math.min(tz1, tz2))
			local tmax = math.min(math.max(tx1, tx2), math.max(ty1, ty2), math.max(tz1, tz2))

			if tmax >= math.max(0, tmin) then
				wallThickness = tmax - math.max(0, tmin)
			end
		end

		if wallThickness <= maxThickness and wallThickness > 0.001 then
			currentDamageMult *= 0.65

			local stepDistance = wallThickness + 0.05
			currentOrigin = hitPos + (currentDirection * stepDistance)
			remainingDistance -= (hitPos - currentOrigin).Magnitude

			table.insert(ignoreList, hitPart)
		else
			break
		end
	end

	return hits
end

local function replicateFireToPeers(shooter: Player, weaponName: string, muzzleOrigin: Vector3, targetPositions: { Vector3 })
	for _, recipient in ipairs(Players:GetPlayers()) do
		if recipient ~= shooter then
			WeaponFireReplicated:FireClient(recipient, shooter, weaponName, muzzleOrigin, targetPositions)
		end
	end
end

-- Network Logic Handlers
local function processIncomingReloadRequest(player: Player, weaponName: any)
	if typeof(weaponName) ~= "string" or not IsSystemActive then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local config = WeaponConfig.GetWeaponData(weaponName)
	local ammoData = getOrCreateWeaponAmmo(player, weaponName)

	if not config or not ammoData or ammoData.IsReloading then return end

	local maxMag = getMaxMagazineSize(config)

	if ammoData.CurrentAmmo >= maxMag or ammoData.ReserveAmmo <= 0 then
		syncAmmoToClient(player, ammoData.CurrentAmmo, ammoData.ReserveAmmo)
		return
	end

	ammoData.IsReloading = true
	ammoData.ReloadToken += 1
	local currentToken = ammoData.ReloadToken

	local reloadTime = config.ReloadDuration or config.ReloadTime or 2.0

	task.delay(reloadTime, function()
		if ammoData and ammoData.ReloadToken == currentToken then
			local needed = maxMag - ammoData.CurrentAmmo
			local transferred = math.min(needed, ammoData.ReserveAmmo)

			ammoData.CurrentAmmo += transferred
			ammoData.ReserveAmmo -= transferred
			ammoData.IsReloading = false

			syncAmmoToClient(player, ammoData.CurrentAmmo, ammoData.ReserveAmmo)
		end
	end)
end

local function processIncomingFireRequest(player: Player, weaponName: any, targetPayload: any)
	if not IsSystemActive or typeof(weaponName) ~= "string" then return end

	local wName: string = weaponName :: string

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local head = character:FindFirstChild("Head") :: BasePart?

	local equippedTool = character:FindFirstChild(wName)
	if not equippedTool or not equippedTool:IsA("Tool") then
		warn(string.format("Player %s attempted to fire unequipped weapon %s.", player.Name, wName))
		return
	end

	local targetPositions: { Vector3 } = {}
	local clientHitParts: { [number]: Instance? } = {}

	local function processEntry(entry: any)
		if typeof(entry) == "Vector3" then
			table.insert(targetPositions, entry)
		elseif typeof(entry) == "table" then
			local pos = entry.Position or entry[1]
			if typeof(pos) == "Vector3" then
				table.insert(targetPositions, pos)
				if entry.Instance then
					clientHitParts[#targetPositions] = entry.Instance
				end
			else
				for _, subEntry in ipairs(entry) do
					processEntry(subEntry)
				end
			end
		end
	end

	processEntry(targetPayload)

	if #targetPositions == 0 then
		warn(string.format("Invalid target payload received from %s.", player.Name))
		return
	end

	local config = WeaponConfig.GetWeaponData(wName)
	if not config then 
		warn(string.format("Invalid weapon configuration key '%s' requested by %s.", wName, player.Name))
		return 
	end

	local playerState = getOrCreatePlayerState(player)
	local ammoData = getOrCreateWeaponAmmo(player, wName)
	if not ammoData then return end

	if ammoData.IsReloading then
		warn(string.format("Player %s attempted to fire while reloading %s.", player.Name, wName))
		return
	end

	if ammoData.CurrentAmmo <= 0 then
		warn(string.format("Player %s attempted to fire %s with empty magazine.", player.Name, wName))
		syncAmmoToClient(player, ammoData.CurrentAmmo, ammoData.ReserveAmmo)
		return
	end

	local currentTime = os.clock()
	local timeDelta = currentTime - playerState.LastFired
	local fireRateThreshold: number = config.FireRate or 0.1

	if timeDelta < (fireRateThreshold - 0.03) then
		warn(string.format("Player %s is firing %s faster than limit. Delta: %.3fs (Limit: %.3fs)", 
			player.Name, wName, timeDelta, fireRateThreshold))
		return
	end

	playerState.LastFired = currentTime
	ammoData.CurrentAmmo -= 1

	syncAmmoToClient(player, ammoData.CurrentAmmo, ammoData.ReserveAmmo)

	local serverOrigin = getShootingOrigin(character, wName)
	local maxRange: number = config.Range or 400

	local validatedTargets: { Vector3 } = {}
	local validatedHitParts: { [number]: Instance? } = {}

	for idx, targetPos in ipairs(targetPositions) do
		if HitValidation.ValidateShot(player, serverOrigin, targetPos) then
			table.insert(validatedTargets, targetPos)
			validatedHitParts[#validatedTargets] = clientHitParts[idx]
		end
	end

	if #validatedTargets == 0 then
		warn(string.format("Shot validation failed for %s.", player.Name))
		return
	end

	replicateFireToPeers(player, wName, serverOrigin, validatedTargets)

	local baseDamage: number = config.Damage or config.BaseDamage or 10
	local headshotMult: number = config.HeadshotMultiplier or 2.0

	for idx, targetPos in ipairs(validatedTargets) do
		local castOrigin = serverOrigin

		if (targetPos - serverOrigin).Magnitude < 4 and head then
			castOrigin = head.Position
		end

		local fireDirection = (targetPos - castOrigin)
		local fireDistance = fireDirection.Magnitude

		if fireDistance > (maxRange + 15) then
			targetPos = castOrigin + fireDirection.Unit * maxRange
			fireDirection = (targetPos - castOrigin)
			fireDistance = maxRange
		end

		local castDirection = if fireDistance > 0 then fireDirection.Unit else Vector3.new(0, 0, -1)
		local castDistance = math.min(fireDistance + 50, maxRange)

		local wallHits = castPenetratingRay(castOrigin, castDirection, castDistance, { character })
		local hitEnemy = false

		for _, hitInfo in ipairs(wallHits) do
			local hitPart = hitInfo.HitPart
			local hitHumanoid, hitModel = findHitHumanoid(hitPart)

			if hitHumanoid and hitModel and hitHumanoid.Health > 0 and hitModel ~= character then
				local partMultiplier = calculateDamageMultiplier(hitPart, headshotMult)
				local finalDamage = math.floor(baseDamage * partMultiplier * hitInfo.DamageMultiplier)

				applyCreatorTag(hitHumanoid, player)
				hitHumanoid:TakeDamage(math.max(1, finalDamage))
				hitEnemy = true
				break
			end
		end

		if not hitEnemy and validatedHitParts[idx] then
			local clientPart = validatedHitParts[idx]
			if clientPart and clientPart:IsA("BasePart") then
				local hitHumanoid, hitModel = findHitHumanoid(clientPart)

				if hitHumanoid and hitModel and hitHumanoid.Health > 0 and hitModel ~= character then
					local targetDist = (clientPart.Position - castOrigin).Magnitude
					if targetDist <= (maxRange + 25) then
						local partMultiplier = calculateDamageMultiplier(clientPart, headshotMult)
						local finalDamage = math.floor(baseDamage * partMultiplier * 0.65)

						applyCreatorTag(hitHumanoid, player)
						hitHumanoid:TakeDamage(math.max(1, finalDamage))
					end
				end
			end
		end
	end
end

-- Lifecycle Management
function WeaponServerManager.InitMode()
	if IsSystemActive then return end
	IsSystemActive = true

	FireNetworkConnection = WeaponFireEvent.OnServerEvent:Connect(processIncomingFireRequest)
	ReloadNetworkConnection = WeaponReloadEvent.OnServerEvent:Connect(processIncomingReloadRequest)

	local function onPlayerAdded(player: Player)
		CharacterAddedConnections[player] = player.CharacterAdded:Connect(function()
			local state = PlayerStates[player]
			if state then
				for _, ammoData in pairs(state.Inventory) do
					ammoData.IsReloading = false
					ammoData.ReloadToken += 1
				end
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		PlayerStates[player] = nil
		if CharacterAddedConnections[player] then
			CharacterAddedConnections[player]:Disconnect()
			CharacterAddedConnections[player] = nil
		end
	end)
end

function WeaponServerManager.CleanMode()
	IsSystemActive = false

	if FireNetworkConnection then FireNetworkConnection:Disconnect(); FireNetworkConnection = nil end
	if ReloadNetworkConnection then ReloadNetworkConnection:Disconnect(); ReloadNetworkConnection = nil end
	if PlayerRemovingConnection then PlayerRemovingConnection:Disconnect(); PlayerRemovingConnection = nil end

	for player, connection in pairs(CharacterAddedConnections) do
		connection:Disconnect()
		CharacterAddedConnections[player] = nil
	end

	table.clear(PlayerStates)
end

return WeaponServerManager