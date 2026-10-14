--!strict
-- ReplicatedStorage.UIController
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local UIController = {}

-- [[ CENTRALIZED AUDIO CONFIGURATION ]]
local AUDIO_ASSETS = {
	Open  = "rbxassetid://74947743572579",
	Close = "rbxassetid://8968249849", 
	Hover = "rbxassetid://136108770017536", 
	Click = "rbxassetid://138567614125924"  
}

-- [[ TWEEN STYLING CONFIGURATION ]]
local HUD_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local WINDOW_OPEN_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local WINDOW_CLOSE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BUTTON_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)

type PanelCache = {
	OpenPosition: UDim2,
	ClosedPosition: UDim2
}

local windowSizeCache: { [Frame]: UDim2 } = {}
local sliderPositionCache: { [Frame]: PanelCache } = {}

-- [[ PRIVATE SYSTEM HELPERS ]]
local function playSoundByKey(key: string, volume: number?)
	local soundId = AUDIO_ASSETS[key]
	if not soundId then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.PlayOnRemove = true
	sound.Parent = SoundService
	sound:Destroy()
end

-- [[ PUBLIC API ]]

-- 1. HUD Bars
function UIController.updateBar(barFrame: Frame, label: TextLabel, current: number, max: number)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(barFrame, HUD_TWEEN_INFO, { Size = UDim2.new(ratio, 0, 1, 0) }):Play()
	label.Text = string.format("%d / %d", math.round(current), math.round(max))
end

-- 2. Pop Windows
function UIController.openWindow(frame: Frame)
	if not windowSizeCache[frame] then windowSizeCache[frame] = frame.Size end
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.Visible = true

	TweenService:Create(frame, WINDOW_OPEN_INFO, { Size = windowSizeCache[frame] }):Play()
	playSoundByKey("Open", 0.6)
end

function UIController.closeWindow(frame: Frame)
	local closeTween = TweenService:Create(frame, WINDOW_CLOSE_INFO, { Size = UDim2.new(0, 0, 0, 0) })
	closeTween:Play()
	playSoundByKey("Close", 0.5)

	local connection: RBXScriptConnection
	connection = closeTween.Completed:Connect(function()
		frame.Visible = false
		connection:Disconnect()
	end)
end

-- 3. Dynamic Side Slider Engine
function UIController.toggleSlider(frame: Frame, isOpen: boolean)
	if not sliderPositionCache[frame] then
		local closedPos = frame.Position

		-- DOUBLED CALCULATION MECHANICS:
		-- If closed position X scale is negative (offscreen left), we multiply the inverse 
		-- of the offscreen distance to project it twice as far onto the active layout horizon.
		-- If it's a right-side panel, we double the frame size addition scale vector.
		local openScale = if closedPos.X.Scale < 0 then (closedPos.X.Scale * -1) else closedPos.X.Scale + (frame.Size.X.Scale * 2)
		local openOffset = if closedPos.X.Scale < 0 then (closedPos.X.Offset * -1) else closedPos.X.Offset + (frame.Size.X.Offset * 2)

		sliderPositionCache[frame] = {
			OpenPosition = UDim2.new(openScale, openOffset, closedPos.Y.Scale, closedPos.Y.Offset),
			ClosedPosition = closedPos
		}

		print(string.format("[UIController Cache] Calculated Closed Pos: %s | Open Target Pos: %s", tostring(closedPos), tostring(sliderPositionCache[frame].OpenPosition)))
	end

	local cache = sliderPositionCache[frame]
	local targetPosition = isOpen and cache.OpenPosition or cache.ClosedPosition

	frame.Visible = true
	frame:SetAttribute("IsSliderOpen", isOpen)

	TweenService:Create(frame, SLIDE_TWEEN_INFO, { Position = targetPosition }):Play()
	playSoundByKey(isOpen and "Open" or "Close", 0.4)
end

-- 4. Unified Interaction and Execution Binder
function UIController.bindButton(button: GuiButton, associatedSliderFrame: Frame?)
	local originalSize = button.Size

	button.MouseEnter:Connect(function()
		TweenService:Create(button, BUTTON_TWEEN_INFO, {
			Size = UDim2.new(originalSize.X.Scale * 1.05, originalSize.X.Offset, originalSize.Y.Scale * 1.05, originalSize.Y.Offset)
		}):Play()
		playSoundByKey("Hover", 0.25)
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, BUTTON_TWEEN_INFO, { Size = originalSize }):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, BUTTON_TWEEN_INFO, {
			Size = UDim2.new(originalSize.X.Scale * 0.95, originalSize.X.Offset, originalSize.Y.Scale * 0.95, originalSize.Y.Offset)
		}):Play()
		playSoundByKey("Click", 0.5)
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, BUTTON_TWEEN_INFO, { Size = originalSize }):Play()
	end)

	-- CONNECT CLICK EXECUTION PATH TO COMPONENT TOGGLE MECHANICS
	if associatedSliderFrame then
		-- SWAPPED TO MouseButton1Down FOR DIRECT AND INSTANT UNBLOCKED LAYOUT INTERCEPTION
		button.MouseButton1Down:Connect(function()
			local currentStatus = associatedSliderFrame:GetAttribute("IsSliderOpen") or false
			UIController.toggleSlider(associatedSliderFrame, not currentStatus)
		end)
	end
end

return UIController