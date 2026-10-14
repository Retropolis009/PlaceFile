local Workspace = game:GetService("Workspace")

-- Replace "MyModel" with the exact name of your model in Workspace
local targetModel = Workspace:WaitForChild("Car1")
local targetModel2 = Workspace:WaitForChild("Car2")

-- Function to toggle anchoring on all BasePart instances in a model
local function setModelAnchored(model: Model, anchored: boolean)
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = anchored
		end
	end
end

-- 1. Anchor all parts in the model
setModelAnchored(targetModel, true)
setModelAnchored(targetModel2,true)
print("Model parts anchored.")

-- 2. Wait 5 seconds
task.wait(5)

-- 3. Unanchor all parts in the model
setModelAnchored(targetModel, false)
setModelAnchored(targetModel2,false)
print("Model parts unanchored.")