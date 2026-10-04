--!strict
-- Loads and saves each player's profile. Cash is mirrored to a "Cash" attribute on the
-- player so the client HUD can show it. Phase 4 swaps this for ProfileStore (session locking).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type Profile = {
	dataVersion: number,
	cash: number,
	stats: {
		deliveries: number,
		tips: number,
		bestRound: number,
		roundsWon: number,
	},
}

local DataService = {}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil

local function defaultProfile(): Profile
	return {
		dataVersion = 1,
		cash = 0,
		stats = { deliveries = 0, tips = 0, bestRound = 0, roundsWon = 0 },
	}
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T?)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(`[DataService] {label} failed (attempt {attempt}): {result}`)
		task.wait(attempt * 2)
	end
	return false, nil
end

local function load(player: Player)
	local profile = defaultProfile()
	local activeStore = store
	if activeStore then
		local ok, saved = withRetries(`load {player.UserId}`, function()
			return activeStore:GetAsync(tostring(player.UserId))
		end)
		if ok and type(saved) == "table" then
			local data = saved :: any
			profile.cash = tonumber(data.cash) or 0
			if type(data.stats) == "table" then
				for key, value in data.stats do
					if (profile.stats :: any)[key] ~= nil and type(value) == "number" then
						(profile.stats :: any)[key] = value
					end
				end
			end
		end
	end
	if player.Parent then
		profiles[player] = profile
		player:SetAttribute("Cash", profile.cash)
	end
end

local function save(player: Player)
	local profile = profiles[player]
	local activeStore = store
	if not profile or not activeStore then
		return
	end
	withRetries(`save {player.UserId}`, function()
		activeStore:SetAsync(tostring(player.UserId), profile)
		return true
	end)
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.addCash(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.cash += amount
	player:SetAttribute("Cash", profile.cash)
end

function DataService.recordDelivery(player: Player, tip: number)
	local profile = profiles[player]
	if profile then
		profile.stats.deliveries += 1
		profile.stats.tips += tip
	end
end

function DataService.recordRound(player: Player, coins: number, won: boolean)
	local profile = profiles[player]
	if profile then
		profile.stats.bestRound = math.max(profile.stats.bestRound, coins)
		if won then
			profile.stats.roundsWon += 1
		end
	end
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok and RunService:IsStudio() then
		-- Studio without API access fails every call; probe once instead of retrying on each join.
		ok = pcall(function()
			result:GetAsync("probe")
		end)
	end
	if ok then
		store = result
	else
		warn(
			"[DataService] DataStores unavailable; progress will not be saved. In Studio, enable "
				.. "Game Settings > Security > Enable Studio Access to API Services."
		)
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveSeconds)
			for player in profiles do
				task.spawn(save, player)
			end
		end
	end)
end

return DataService
