
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local button = script.Parent
local GAMEPASS_ID = 1958940321

button.MouseButton1Click:Connect(function()
	MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, GAMEPASS_ID)
end)