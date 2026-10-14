--!strict

local HitValidation = {}

local MAX_ORIGIN_VARIANCE = 18

function HitValidation.ValidateShot(player: Player, clientClaimedOrigin: Vector3, reportedTarget: Vector3): boolean
	local character = player.Character
	if not character then return false end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = character:FindFirstChild("Head") :: BasePart

	if not rootPart or not head then
		return false
	end

	local serverEyeOrigin = head.Position
	local originVariance = (clientClaimedOrigin - serverEyeOrigin).Magnitude

	if originVariance > MAX_ORIGIN_VARIANCE then
		return false
	end

	local shotDistance = (reportedTarget - clientClaimedOrigin).Magnitude
	if shotDistance < 4 then
		return true
	end

	local rayDirection = (reportedTarget - clientClaimedOrigin)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }

	local serverTrace = workspace:Raycast(clientClaimedOrigin, rayDirection, raycastParams)
	
	if serverTrace then
		local hitInstance = serverTrace.Instance
		local distFromReportedTarget = (serverTrace.Position - reportedTarget).Magnitude		
		if hitInstance:IsA("BasePart") and hitInstance.CanCollide and hitInstance.Anchored and distFromReportedTarget > 3.5 then
			local ancestorModel = hitInstance:FindFirstAncestorOfClass("Model")
			local hasHumanoid = ancestorModel and ancestorModel:FindFirstChildOfClass("Humanoid")

			if not hasHumanoid then
				return false
			end
		end
	end

	return true
end

return HitValidation