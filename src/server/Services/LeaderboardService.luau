--!strict
-- Round leaderboard shown in the player list (leaderstats: Deliveries, Coins).
-- Global all-time boards (OrderedDataStore) come in phase 4.

local Players = game:GetService("Players")

local LeaderboardService = {}

local function statsFor(player: Player): (IntValue?, IntValue?)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil, nil
	end
	local deliveries = leaderstats:FindFirstChild("Deliveries")
	local coins = leaderstats:FindFirstChild("Coins")
	return if deliveries and deliveries:IsA("IntValue") then deliveries else nil,
		if coins and coins:IsA("IntValue") then coins else nil
end

local function setup(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local deliveries = Instance.new("IntValue")
	deliveries.Name = "Deliveries"
	deliveries.Parent = leaderstats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats
	leaderstats.Parent = player
end

function LeaderboardService.addDelivery(player: Player, coinsEarned: number)
	local deliveries, coins = statsFor(player)
	if deliveries and coins then
		deliveries.Value += 1
		coins.Value += coinsEarned
	end
end

function LeaderboardService.addCoins(player: Player, amount: number)
	local _, coins = statsFor(player)
	if coins then
		coins.Value += amount
	end
end

function LeaderboardService.get(player: Player): (number, number)
	local deliveries, coins = statsFor(player)
	return if deliveries then deliveries.Value else 0, if coins then coins.Value else 0
end

function LeaderboardService.resetAll()
	for _, player in Players:GetPlayers() do
		local deliveries, coins = statsFor(player)
		if deliveries and coins then
			deliveries.Value = 0
			coins.Value = 0
		end
	end
end

function LeaderboardService.init()
	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
end

return LeaderboardService
