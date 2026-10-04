--!strict
-- The delivery phone: a list of open orders with an Accept button each.
-- Toggle with the phone button or the O key.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local OrderState = require(script.Parent.OrderState)

local PhoneController = {}

local player = Players.LocalPlayer
local acceptOrder = Remotes.get("AcceptOrder")

local gui = Instance.new("ScreenGui")
gui.Name = "Phone"
gui.ResetOnSpawn = false

local toggle = Instance.new("TextButton")
toggle.Name = "PhoneButton"
toggle.AnchorPoint = Vector2.new(1, 1)
toggle.Position = UDim2.new(1, -16, 1, -16)
toggle.Size = UDim2.fromOffset(130, 48)
toggle.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
toggle.Font = Enum.Font.GothamBold
toggle.TextScaled = true
toggle.Text = "Orders (O)"
toggle.Parent = gui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 12)
toggleCorner.Parent = toggle

local phone = Instance.new("Frame")
phone.Name = "PhoneScreen"
phone.AnchorPoint = Vector2.new(1, 1)
phone.Position = UDim2.new(1, -16, 1, -76)
phone.Size = UDim2.fromOffset(300, 420)
phone.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
phone.Visible = false
phone.Parent = gui
local phoneCorner = Instance.new("UICorner")
phoneCorner.CornerRadius = UDim.new(0, 18)
phoneCorner.Parent = phone

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.fromOffset(12, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "Open orders"
title.Parent = phone

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -60)
list.Position = UDim2.fromOffset(12, 50)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = phone
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function row(order: Types.PublicOrder, index: number, mine: boolean)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -8, 0, 76)
	frame.LayoutOrder = index
	frame.BackgroundColor3 = if mine then Color3.fromRGB(60, 80, 50) else Color3.fromRGB(40, 46, 60)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -96, 1, -12)
	info.Position = UDim2.fromOffset(10, 6)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.Gotham
	info.TextColor3 = Color3.new(1, 1, 1)
	info.TextSize = 15
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.RichText = true
	info.Text =
		`<b>{order.Item}</b> from {order.ShopName}\nto {order.Address}\n{order.Distance} studs · <b>{order.BasePay} coins</b>`
	info.Parent = frame

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(76, 40)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.new(1, 1, 1)
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button
	if mine then
		button.Text = if order.Status == "PickedUp" then "Carrying" else "Accepted"
		button.BackgroundColor3 = Color3.fromRGB(90, 110, 80)
		button.AutoButtonColor = false
	else
		button.Text = "Accept"
		button.BackgroundColor3 = Color3.fromRGB(46, 160, 90)
		button.Activated:Connect(function()
			acceptOrder:FireServer(order.Id)
		end)
	end
	button.Parent = frame
	frame.Parent = list
end

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local userId = player.UserId
	local index = 0
	for _, order in OrderState.all() do
		local mine = order.CourierUserId == userId
		if order.Status == "Posted" or mine then
			index += 1
			row(order, if mine then 0 else index, mine)
		end
	end
	title.Text = if index == 0 then "No open orders" else "Open orders"
end

local function setOpen(open: boolean)
	phone.Visible = open
	if open then
		render()
	end
end

function PhoneController.start()
	gui.Parent = player:WaitForChild("PlayerGui")
	toggle.Activated:Connect(function()
		setOpen(not phone.Visible)
	end)
	ContextActionService:BindAction("TogglePhone", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			setOpen(not phone.Visible)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.O)
	OrderState.onChanged(function()
		if phone.Visible then
			render()
		end
	end)
end

return PhoneController
