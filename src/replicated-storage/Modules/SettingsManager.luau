--!strict
-- ReplicatedStorage.SettingsManager
local SettingsManager = {}

-- Define the default fallback keys for your 4 slots
local DefaultBinds: { [string]: Enum.KeyCode } = {
	["Slot1"] = Enum.KeyCode.One,
	["Slot2"] = Enum.KeyCode.Two,
	["Slot3"] = Enum.KeyCode.Three,
	["Slot4"] = Enum.KeyCode.Four,
}

-- Runtime table holding active bindings in memory
local CurrentBinds: { [string]: Enum.KeyCode } = {}

-- Initialize memory with defaults
for slot, key in pairs(DefaultBinds) do
	CurrentBinds[slot] = key
end

-- [[ PUBLIC API ]]

-- Returns the KeyCode currently tied to a specific slot
function SettingsManager.GetKeyForSlot(slotName: string): Enum.KeyCode
	return CurrentBinds[slotName] or Enum.KeyCode.Unknown
end

-- Allows your Settings UI to authoritatively remap a slot to a new KeyCode
function SettingsManager.RemapSlot(slotName: string, newKey: Enum.KeyCode)
	-- Security/Sanity Check: Prevent binding system keys like Escape or Backquote
	if newKey == Enum.KeyCode.Escape or newKey == Enum.KeyCode.Backquote then 
		warn("Cannot bind vital system keys!")
		return 
	end

	-- Optional Anti-Duplicate Rule: If another slot uses this key, clear it or swap it!
	for otherSlot, boundKey in pairs(CurrentBinds) do
		if otherSlot ~= slotName and boundKey == newKey then
			CurrentBinds[otherSlot] = Enum.KeyCode.Unknown -- Or handle a graceful swap
		end
	end

	CurrentBinds[slotName] = newKey
	print(string.format("Control Remapped: %s is now bound to %s", slotName, newKey.Name))

	-- FUTURE SAVE HOOK: You can fire a RemoteEvent here to tell the server to save this to a DataStore!
end

return SettingsManager