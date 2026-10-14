local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local GAMEPASS_ID = 1987016962

local function grantRewards(player: Player)
	-- Insert your reward logic here (e.g., granting plot items, coins, or exclusive tools)
	print("Granted 3k Gamepass benefits to: " .. player.Name)
end

-- Grant benefits if bought while inside the game
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased and passId == GAMEPASS_ID then
		grantRewards(player)
	end
end)

-- Grant benefits if they already own it when joining
Players.PlayerAdded:Connect(function(player)
	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GAMEPASS_ID)
	end)

	if success and ownsPass then
		grantRewards(player)
	end
end)