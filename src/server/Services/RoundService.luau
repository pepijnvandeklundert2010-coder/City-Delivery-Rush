--!strict
-- Runs the round loop: Intermission -> Countdown -> Running -> Results.
-- The current state and when it ends live in Workspace attributes (RoundState, PhaseEndsAt),
-- so every client can show the timer without the server sending a message each second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local OrderService = require(script.Parent.OrderService)

local RoundService = {}

local roundResults = Remotes.get("RoundResults")

local function setPhase(state: Types.RoundState, seconds: number)
	workspace:SetAttribute("RoundState", state)
	workspace:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + seconds)
end

local function waitPhase(state: Types.RoundState, seconds: number)
	setPhase(state, seconds)
	task.wait(seconds)
end

local function rankPlayers(): Types.RoundRanking
	local ranking: Types.RoundRanking = {}
	for _, player in Players:GetPlayers() do
		local deliveries, coins = LeaderboardService.get(player)
		table.insert(
			ranking,
			{ UserId = player.UserId, Name = player.DisplayName, Deliveries = deliveries, Coins = coins, Bonus = 0 }
		)
	end
	table.sort(ranking, function(a, b)
		if a.Deliveries ~= b.Deliveries then
			return a.Deliveries > b.Deliveries
		end
		return a.Coins > b.Coins
	end)
	return ranking
end

local function finishRound()
	local ranking = rankPlayers()
	for place, entry in ranking do
		local player = Players:GetPlayerByUserId(entry.UserId)
		if player then
			local bonus = if entry.Deliveries > 0 then Config.Pay.PodiumBonus[place] or 0 else 0
			if bonus > 0 then
				EconomyService.awardBonus(player, bonus)
				entry.Bonus = bonus
			end
			DataService.recordRound(player, entry.Coins + bonus, place == 1 and entry.Deliveries > 0)
		end
	end
	roundResults:FireAllClients(ranking)
end

local function loop()
	while true do
		while #Players:GetPlayers() < Config.Round.MinPlayers do
			setPhase("Intermission", 0)
			task.wait(1)
		end
		waitPhase("Intermission", Config.Round.IntermissionSeconds)
		waitPhase("Countdown", Config.Round.CountdownSeconds)

		LeaderboardService.resetAll()
		OrderService.startRound()
		waitPhase("Running", Config.Round.RoundSeconds)
		OrderService.endRound()

		finishRound()
		waitPhase("Results", Config.Round.ResultsSeconds)
	end
end

function RoundService.start()
	task.spawn(loop)
end

return RoundService
