--!strict
-- Server entry point: builds the city if needed, then starts every service in order.

local Services = script.Parent.Services

local MapBuilder = require(Services.MapBuilder)
local DataService = require(Services.DataService)
local LeaderboardService = require(Services.LeaderboardService)
local OrderService = require(Services.OrderService)
local RoundService = require(Services.RoundService)

MapBuilder.build()
LeaderboardService.init()
DataService.init()
OrderService.init()
RoundService.start()
