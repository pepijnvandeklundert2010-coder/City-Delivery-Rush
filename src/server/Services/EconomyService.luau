--!strict
-- Turns a finished delivery into coins: base pay for distance plus a tip for speed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)

local EconomyService = {}

function EconomyService.basePay(distance: number): number
	return math.floor(Config.Pay.Base + Config.Pay.PerStud * distance)
end

-- Returns pay, tip and the customer's reaction for a delivery that took `seconds`.
function EconomyService.payout(basePay: number, seconds: number, targetSeconds: number): (number, number, string)
	local ratio = seconds / targetSeconds
	if ratio > Config.Pay.LateRatio then
		return math.floor(basePay * Config.Pay.LateShare), 0, Config.Pay.LateReaction
	end
	for _, tier in Config.Pay.TipTiers do
		if ratio <= tier.MaxRatio then
			return basePay, math.floor(basePay * tier.TipShare), tier.Reaction
		end
	end
	return basePay, 0, Config.Pay.NoTipReaction
end

function EconomyService.awardDelivery(player: Player, pay: number, tip: number)
	DataService.addCash(player, pay + tip)
	DataService.recordDelivery(player, tip)
	LeaderboardService.addDelivery(player, pay + tip)
end

function EconomyService.awardBonus(player: Player, amount: number)
	DataService.addCash(player, amount)
	LeaderboardService.addCoins(player, amount)
end

return EconomyService
