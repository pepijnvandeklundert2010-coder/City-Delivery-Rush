--!strict
-- Always-on HUD: round timer, this round's coins and deliveries, saved cash, the current
-- order card with its tip countdown, message toasts, payout popups and the results screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local OrderState = require(script.Parent.OrderState)

local HUDController = {}

local player = Players.LocalPlayer

local function label(props: { [string]: any }, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
	l.BackgroundTransparency = 0.25
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = true
	for key, value in props do
		(l :: any)[key] = value
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = l
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = l
	l.Parent = parent
	return l
end

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false

local timerLabel = label({
	Name = "Timer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(260, 44),
	Text = "",
}, gui)
local roundLabel = label({
	Name = "RoundStats",
	Position = UDim2.fromOffset(12, 60),
	Size = UDim2.fromOffset(220, 34),
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
}, gui)
local cashLabel = label({
	Name = "Cash",
	Position = UDim2.fromOffset(12, 100),
	Size = UDim2.fromOffset(220, 30),
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(255, 220, 90),
}, gui)
local orderCard = label({
	Name = "OrderCard",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.fromOffset(380, 64),
	Text = "",
	Visible = false,
	TextWrapped = true,
}, gui)
local toast = label({
	Name = "Toast",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 60),
	Size = UDim2.fromOffset(420, 36),
	Text = "",
	Visible = false,
	BackgroundColor3 = Color3.fromRGB(45, 55, 75),
}, gui)
local payout = label({
	Name = "Payout",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.38),
	Size = UDim2.fromOffset(360, 80),
	Text = "",
	Visible = false,
	TextColor3 = Color3.fromRGB(255, 230, 100),
	BackgroundTransparency = 1,
	TextStrokeTransparency = 0.2,
}, gui)

local results = Instance.new("Frame")
results.Name = "Results"
results.AnchorPoint = Vector2.new(0.5, 0.5)
results.Position = UDim2.fromScale(0.5, 0.5)
results.Size = UDim2.fromOffset(420, 320)
results.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
results.BackgroundTransparency = 0.1
results.Visible = false
results.Parent = gui
local resultsCorner = Instance.new("UICorner")
resultsCorner.CornerRadius = UDim.new(0, 14)
resultsCorner.Parent = results
local resultsText = Instance.new("TextLabel")
resultsText.Size = UDim2.new(1, -32, 1, -32)
resultsText.Position = UDim2.fromOffset(16, 16)
resultsText.BackgroundTransparency = 1
resultsText.Font = Enum.Font.Gotham
resultsText.TextColor3 = Color3.new(1, 1, 1)
resultsText.TextSize = 20
resultsText.TextXAlignment = Enum.TextXAlignment.Left
resultsText.TextYAlignment = Enum.TextYAlignment.Top
resultsText.RichText = true
resultsText.Parent = results

local toastToken = 0
local function showToast(message: string)
	toastToken += 1
	local token = toastToken
	toast.Text = message
	toast.Visible = true
	task.delay(3, function()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local STATE_TEXT = {
	Intermission = "Next round in",
	Countdown = "Get ready!",
	Running = "Time left",
	Results = "Round over",
}

local function updateTimer()
	local state = workspace:GetAttribute("RoundState")
	local endsAt = workspace:GetAttribute("PhaseEndsAt")
	if type(state) ~= "string" or type(endsAt) ~= "number" then
		timerLabel.Text = "Waiting for players"
		return
	end
	local remaining = endsAt - workspace:GetServerTimeNow()
	timerLabel.Text = `{STATE_TEXT[state] or state}  {formatTime(remaining)}`
	timerLabel.TextColor3 = if state == "Running" and remaining <= 30
		then Color3.fromRGB(255, 110, 100)
		else Color3.new(1, 1, 1)
end

local function updateStats()
	local leaderstats = player:FindFirstChild("leaderstats")
	local deliveries = leaderstats and leaderstats:FindFirstChild("Deliveries")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if deliveries and coins and deliveries:IsA("IntValue") and coins:IsA("IntValue") then
		roundLabel.Text = `Deliveries {deliveries.Value}   Coins {coins.Value}`
	end
	local cash = player:GetAttribute("Cash")
	cashLabel.Text = `Bank: {if type(cash) == "number" then cash else 0} coins`
end

-- Which tip the player still gets if they deliver right now.
local function tipStatus(order: Types.PublicOrder): string
	if not order.PickedUpAt then
		return `Pick up at {order.ShopName}`
	end
	local elapsed = workspace:GetServerTimeNow() - order.PickedUpAt
	for _, tier in Config.Pay.TipTiers do
		local cutoff = order.TargetSeconds * tier.MaxRatio
		if elapsed <= cutoff then
			return `+{math.floor(order.BasePay * tier.TipShare)} tip for {formatTime(cutoff - elapsed)}`
		end
	end
	return "No tip, hurry!"
end

local function updateOrderCard()
	local order = OrderState.mine()
	if not order then
		orderCard.Visible = false
		return
	end
	orderCard.Visible = true
	orderCard.Text = `{order.Item} to {order.Address}\n{order.BasePay} coins · {tipStatus(order)}`
end

local function showPayout(result: Types.DeliveryResult)
	payout.Text = if result.Tip > 0
		then `+{result.BasePay} coins  +{result.Tip} tip!\n"{result.Reaction}"`
		else `+{result.BasePay} coins\n"{result.Reaction}"`
	payout.Visible = true
	payout.Size = UDim2.fromOffset(200, 44)
	TweenService:Create(payout, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(360, 80) }):Play()
	task.delay(2.5, function()
		payout.Visible = false
	end)
end

local function showResults(ranking: Types.RoundRanking)
	local lines = { "<b>Round results</b>", "" }
	for place, entry in ranking do
		if place > 8 then
			break
		end
		local bonus = if entry.Bonus > 0 then `  (+{entry.Bonus} bonus)` else ""
		local name = if entry.UserId == player.UserId then `<b>{entry.Name}</b>` else entry.Name
		table.insert(lines, `{place}. {name}: {entry.Deliveries} deliveries, {entry.Coins} coins{bonus}`)
	end
	resultsText.Text = table.concat(lines, "\n")
	results.Visible = true
	task.delay(Config.Round.ResultsSeconds, function()
		results.Visible = false
	end)
end

function HUDController.start()
	gui.Parent = player:WaitForChild("PlayerGui")
	Remotes.get("Notify").OnClientEvent:Connect(showToast)
	Remotes.get("DeliveryCompleted").OnClientEvent:Connect(showPayout)
	Remotes.get("RoundResults").OnClientEvent:Connect(showResults)
	OrderState.onChanged(updateOrderCard)
	RunService.Heartbeat:Connect(function()
		updateTimer()
		updateStats()
		updateOrderCard()
	end)
end

return HUDController
