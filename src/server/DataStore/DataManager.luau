--!strict
-- ServerScriptService.DataManager
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local AbilityDataStore = DataStoreService:GetDataStore("AbilitySystem_v4")

type PlayerDataProfile = {
	ActiveLoadout: { [string]: string },
	UnlockedAbilities: { [string]: boolean }
}

local SessionCache: { [Player]: PlayerDataProfile } = {}
local DataManager = {}

local DEFAULT_PROFILE: PlayerDataProfile = {
	ActiveLoadout = {
		["Slot1"] = "Dash",
		["Slot2"] = "Fireball", 
		["Slot3"] = "KineticBarrier",
		["Slot4"] = "Heal"
	},
	UnlockedAbilities = {
		["Dash"] = true,
		["Fireball"] = true,
		["KineticBarrier"] = true,
		["Heal"] = true,
		["Teleport"] = true,
		["Silence"] = true,
		["LightningStrike"] = true,
		["EarthShaker"] = true,
		["MeteorShower"] = true,
	}
}

-- [[ PUBLIC DATA ACCESS API ]]

function DataManager.GetProfile(player: Player): PlayerDataProfile?
	return SessionCache[player]
end

function DataManager.UpdateSlot(player: Player, slotKey: string, abilityName: string): boolean
	local profile = SessionCache[player]
	if profile and profile.UnlockedAbilities[abilityName] then
		profile.ActiveLoadout[slotKey] = abilityName
		return true
	end
	return false
end

function DataManager.UnlockAbility(player: Player, abilityName: string)
	local profile = SessionCache[player]
	if profile then
		profile.UnlockedAbilities[abilityName] = true
	end
end

local function loadData(player: Player)
	local key = "Player_" .. player.UserId
	local success, data = pcall(function()
		return AbilityDataStore:GetAsync(key)
	end)

	if success and type(data) == "table" then
		local active = data.ActiveLoadout or table.clone(DEFAULT_PROFILE.ActiveLoadout)
		local unlocked = data.UnlockedAbilities or table.clone(DEFAULT_PROFILE.UnlockedAbilities)

		-- CRITICAL RECONCILIATION: Reconcile newly added abilities into old data profiles
		for defaultAbility, state in pairs(DEFAULT_PROFILE.UnlockedAbilities) do
			if unlocked[defaultAbility] == nil then
				unlocked[defaultAbility] = state
				print(string.format("🔧 [Data Migration] Migrated missing ability '%s' into %s's profile.", defaultAbility, player.Name))
			end
		end

		SessionCache[player] = {
			ActiveLoadout = active,
			UnlockedAbilities = unlocked
		}
	else
		-- New player fallback sequence
		SessionCache[player] = {
			ActiveLoadout = table.clone(DEFAULT_PROFILE.ActiveLoadout),
			UnlockedAbilities = table.clone(DEFAULT_PROFILE.UnlockedAbilities)
		}
	end
end

local function saveData(player: Player)
	local profile = SessionCache[player]
	if not profile then return end

	local key = "Player_" .. player.UserId
	local tries = 3
	local success = false

	while tries > 0 and not success do
		success = pcall(function()
			AbilityDataStore:SetAsync(key, profile)
		end)
		if not success then
			tries -= 1
			task.wait(1)
		end
	end
	SessionCache[player] = nil
end

Players.PlayerAdded:Connect(loadData)
Players.PlayerRemoving:Connect(saveData)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(saveData, player)
	end
end)

return DataManager