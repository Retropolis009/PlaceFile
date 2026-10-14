--!strict
-- Location: StarterPlayer.StarterPlayerScripts.AbilityClient.FpsClient.FpsInterface
local FpsInterface = {}

local Players = game:GetService("Players")

-- [[ STATE & REFERENCES ]]
local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() :: Player
local Camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() :: Camera
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local IsActive = false

-- Cached ammo state to prevent UI resetting on init/re-enable
local CachedClipAmmo: string = "--"
local CachedTotalAmmo: string = "--"

-- TextLabel Instances
local ClipAmmoLabel: TextLabel? = nil
local TotalAmmoLabel: TextLabel? = nil

-- Crosshair Instances
local CrosshairFrame: Frame? = nil
local TopLine: Frame? = nil
local BottomLine: Frame? = nil
local LeftLine: Frame? = nil
local RightLine: Frame? = nil
local CenterDot: Frame? = nil

-- [[ RETICLE INTERPOLATION SETTINGS ]]
local BASE_PIXEL_GAP = 14          -- Resting gap from screen center in pixels (default stance)
local MIN_PIXEL_GAP = 8            -- Hard minimum gap to prevent lines overlapping center dot or each other
local RETICLE_SMOOTH_SPEED = 24    -- Interpolation speed (Higher = snappier)

local CurrentPixelOffset = BASE_PIXEL_GAP
local TargetPixelOffset = BASE_PIXEL_GAP

-- [[ PUBLIC METHODS ]]

--- Hooks into the Ammo TextLabels and Crosshair Frames inside PlayerGui.FpsInterface
function FpsInterface.Init(fpsFrameOverride: Instance?)
	if IsActive then return end

	-- 1. Locate the ScreenGui directly
	local fpsScreenGui = PlayerGui:WaitForChild("FpsInterface", 5) :: ScreenGui?
	if not fpsScreenGui then
		warn("⚠️ [FpsInterface] Could not locate 'FpsInterface' ScreenGui in PlayerGui!")
		return
	end

	-- 2. Locate the Ammo Frame directly under FpsInterface
	local ammoContainer = fpsScreenGui:FindFirstChild("Ammo", true)
	if not ammoContainer then
		warn("⚠️ [FpsInterface] 'Ammo' container not found under FpsInterface ScreenGui!")
	else
		ClipAmmoLabel = ammoContainer:FindFirstChild("ClipAmmo", true) :: TextLabel?
		TotalAmmoLabel = ammoContainer:FindFirstChild("TotalAmmo", true) :: TextLabel?

		if not ClipAmmoLabel then warn("⚠️ [FpsInterface] 'ClipAmmo' TextLabel not found under Ammo!") end
		if not TotalAmmoLabel then warn("⚠️ [FpsInterface] 'TotalAmmo' TextLabel not found under Ammo!") end
	end

	-- 3. Locate the Crosshair Frame under FpsInterface
	CrosshairFrame = fpsScreenGui:FindFirstChild("Crosshair", true) :: Frame?
	if not CrosshairFrame then
		warn("⚠️ [FpsInterface] 'Crosshair' frame not found under FpsInterface ScreenGui!")
	else
		TopLine = (CrosshairFrame:FindFirstChild("Top") or CrosshairFrame:FindFirstChild("TopLine")) :: Frame?
		BottomLine = (CrosshairFrame:FindFirstChild("Bottom") or CrosshairFrame:FindFirstChild("BottomLine")) :: Frame?
		LeftLine = (CrosshairFrame:FindFirstChild("Left") or CrosshairFrame:FindFirstChild("LeftLine")) :: Frame?
		RightLine = (CrosshairFrame:FindFirstChild("Right") or CrosshairFrame:FindFirstChild("RightLine")) :: Frame?
		CenterDot = (CrosshairFrame:FindFirstChild("CenterDot") or CrosshairFrame:FindFirstChild("Dot")) :: Frame?

		-- Enforce uniform AnchorPoints (0.5, 0.5) so lines scale cleanly from screen center
		if TopLine then TopLine.AnchorPoint = Vector2.new(0.5, 0.5) end
		if BottomLine then BottomLine.AnchorPoint = Vector2.new(0.5, 0.5) end
		if LeftLine then LeftLine.AnchorPoint = Vector2.new(0.5, 0.5) end
		if RightLine then RightLine.AnchorPoint = Vector2.new(0.5, 0.5) end
		if CenterDot then CenterDot.AnchorPoint = Vector2.new(0.5, 0.5) end
	end

	IsActive = true

	-- Render the cached ammo values immediately on init
	if ClipAmmoLabel then ClipAmmoLabel.Text = CachedClipAmmo end
	if TotalAmmoLabel then TotalAmmoLabel.Text = CachedTotalAmmo end
end

--- Updates the ClipAmmo and TotalAmmo TextLabel strings directly and updates state cache
function FpsInterface.UpdateAmmo(clipAmmo: number | string, totalAmmo: number | string)
	CachedClipAmmo = tostring(clipAmmo)
	CachedTotalAmmo = tostring(totalAmmo)

	if not IsActive then return end

	if ClipAmmoLabel then ClipAmmoLabel.Text = CachedClipAmmo end
	if TotalAmmoLabel then TotalAmmoLabel.Text = CachedTotalAmmo end
end

--- Updates reticle spread and positions outward symmetrically from screen center
function FpsInterface.UpdateCrosshair(spreadAngle: number, deltaTime: number)
	if not IsActive or not CrosshairFrame or not Camera then return end

	-- Convert spread angle (radians) to screen pixel distance via projection math
	local viewportSize = Camera.ViewportSize
	local currentFov = Camera.FieldOfView
	local fovRad = math.rad(currentFov)
	local screenHeight = viewportSize.Y

	local projectionDistance = (screenHeight * 0.5) / math.tan(fovRad * 0.5)
	local rawPixelOffset = math.tan(spreadAngle) * projectionDistance

	-- Enforce MIN_PIXEL_GAP so lines NEVER overlap regardless of FOV or zero spread
	TargetPixelOffset = math.max(MIN_PIXEL_GAP, BASE_PIXEL_GAP + rawPixelOffset)

	-- Frame-rate independent interpolation
	CurrentPixelOffset += (TargetPixelOffset - CurrentPixelOffset) * math.clamp(deltaTime * RETICLE_SMOOTH_SPEED, 0, 1)

	local roundedOffset = math.round(CurrentPixelOffset)

	-- Reposition all 4 legs symmetrically outward from screen center (0.5, 0.5)
	if TopLine then TopLine.Position = UDim2.new(0.5, 0, 0.5, -roundedOffset) end
	if BottomLine then BottomLine.Position = UDim2.new(0.5, 0, 0.5, roundedOffset) end
	if LeftLine then LeftLine.Position = UDim2.new(0.5, -roundedOffset, 0.5, 0) end
	if RightLine then RightLine.Position = UDim2.new(0.5, roundedOffset, 0.5, 0) end
end

--- Toggle overall Crosshair container visibility
function FpsInterface.SetCrosshairVisible(visible: boolean)
	if CrosshairFrame then
		CrosshairFrame.Visible = visible
	end
end

--- Resets text displays and deactivates bindings
function FpsInterface.Clean()
	IsActive = false

	if ClipAmmoLabel then ClipAmmoLabel.Text = "--" end
	if TotalAmmoLabel then TotalAmmoLabel.Text = "--" end

	ClipAmmoLabel = nil
	TotalAmmoLabel = nil
	CrosshairFrame = nil
	TopLine = nil
	BottomLine = nil
	LeftLine = nil
	RightLine = nil
	CenterDot = nil
end

return FpsInterface