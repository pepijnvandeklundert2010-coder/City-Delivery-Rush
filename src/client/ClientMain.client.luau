--!strict
-- Client entry point: starts the UI and navigation controllers.

local Controllers = script.Parent.Controllers

local OrderState = require(Controllers.OrderState)
local HUDController = require(Controllers.HUDController)
local PhoneController = require(Controllers.PhoneController)
local WaypointController = require(Controllers.WaypointController)

OrderState.start()
HUDController.start()
PhoneController.start()
WaypointController.start()
