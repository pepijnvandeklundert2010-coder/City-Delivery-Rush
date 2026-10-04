--!strict
-- Keeps the latest order list from the server and tells the UI when it changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local OrderState = {}

local orders: { Types.PublicOrder } = {}
local listeners: { () -> () } = {}

function OrderState.all(): { Types.PublicOrder }
	return orders
end

-- The order this player is working on (accepted or picked up), if any.
function OrderState.mine(): Types.PublicOrder?
	local userId = Players.LocalPlayer.UserId
	for _, order in orders do
		if order.CourierUserId == userId then
			return order
		end
	end
	return nil
end

function OrderState.onChanged(callback: () -> ())
	table.insert(listeners, callback)
end

function OrderState.start()
	Remotes.get("OrdersChanged").OnClientEvent:Connect(function(list: { Types.PublicOrder })
		orders = list
		table.sort(orders, function(a, b)
			return a.BasePay > b.BasePay
		end)
		for _, callback in listeners do
			task.spawn(callback)
		end
	end)
end

return OrderState
