--!strict
-- Draws a beam from the player to where they need to go next: the shop for an accepted
-- order, the customer for a picked-up one. Also shows a marker over the target.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local OrderState = require(script.Parent.OrderState)

local WaypointController = {}

local player = Players.LocalPlayer

local target = Instance.new("Part")
target.Name = "DeliveryWaypoint"
target.Anchored = true
target.CanCollide = false
target.CanQuery = false
target.Transparency = 1
target.Size = Vector3.new(1, 1, 1)

local targetAttachment = Instance.new("Attachment")
targetAttachment.Parent = target

local beam = Instance.new("Beam")
beam.Attachment1 = targetAttachment
beam.Width0 = 0.6
beam.Width1 = 0.6
beam.FaceCamera = true
beam.LightEmission = 1
beam.TextureSpeed = 2
beam.Segments = 20
beam.Parent = target

local marker = Instance.new("BillboardGui")
marker.Size = UDim2.fromOffset(160, 50)
marker.StudsOffset = Vector3.new(0, 8, 0)
marker.AlwaysOnTop = true
marker.Parent = target
local markerLabel = Instance.new("TextLabel")
markerLabel.Size = UDim2.fromScale(1, 1)
markerLabel.BackgroundTransparency = 1
markerLabel.Font = Enum.Font.GothamBold
markerLabel.TextScaled = true
markerLabel.TextColor3 = Color3.new(1, 1, 1)
markerLabel.TextStrokeTransparency = 0.2
markerLabel.Parent = marker

local function attachToCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart")
	local attachment = Instance.new("Attachment")
	attachment.Name = "WaypointAttachment"
	attachment.Parent = root
	beam.Attachment0 = attachment
end

local function refresh()
	local order = OrderState.mine()
	if not order then
		target.Parent = nil
		return
	end
	local picked = order.Status == "PickedUp"
	target.Position = if picked then order.DropPosition else order.ShopPosition
	beam.Color = ColorSequence.new(if picked then Color3.fromRGB(80, 200, 255) else Color3.fromRGB(255, 220, 60))
	markerLabel.Text = if picked then `Deliver: {order.Address}` else `Pick up at {order.ShopName}`
	target.Parent = workspace
end

function WaypointController.start()
	if player.Character then
		task.spawn(attachToCharacter, player.Character)
	end
	player.CharacterAdded:Connect(attachToCharacter)
	OrderState.onChanged(refresh)

	-- Show distance on the marker while moving.
	RunService.Heartbeat:Connect(function()
		local order = OrderState.mine()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if order and root and root:IsA("BasePart") and target.Parent then
			local meters = math.floor((root.Position - target.Position).Magnitude * 0.28)
			local place = if order.Status == "PickedUp" then order.Address else order.ShopName
			markerLabel.Text = `{place} · {meters} m`
		end
	end)
end

return WaypointController
