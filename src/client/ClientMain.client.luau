--!strict
-- Client entry point: starts the UI, navigation and movement controllers.

local Controllers = script.Parent.Controllers

local OrderState = require(Controllers.OrderState)
local HUDController = require(Controllers.HUDController)
local PhoneController = require(Controllers.PhoneController)
local WaypointController = require(Controllers.WaypointController)
local MovementController = require(Controllers.MovementController)

OrderState.start()
HUDController.start()
PhoneController.start()
WaypointController.start()
MovementController.start()
