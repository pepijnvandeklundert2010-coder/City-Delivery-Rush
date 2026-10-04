--!strict
-- Owns every order. Shops post orders while a round runs; players accept them on their
-- phone, pick them up at the shop's PickupZone and deliver to the customer's DeliveryPoint.
-- Every request from a client is checked here before anything changes.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)

type Order = {
	Id: string,
	Shop: BasePart,
	ShopId: string,
	ShopName: string,
	Item: string,
	Drop: BasePart,
	Address: string,
	Distance: number,
	BasePay: number,
	TargetSeconds: number,
	Status: Types.OrderStatus,
	Courier: Player?,
	AcceptedAt: number?,
	PickedUpAt: number?,
}

local OrderService = {}

local orders: { [string]: Order } = {}
local running = false
local random = Random.new()

local ordersChanged = Remotes.get("OrdersChanged")
local deliveryCompleted = Remotes.get("DeliveryCompleted")
local notify = Remotes.get("Notify")

local function now(): number
	return workspace:GetServerTimeNow()
end

local function toPublic(order: Order): Types.PublicOrder
	return {
		Id = order.Id,
		ShopId = order.ShopId,
		ShopName = order.ShopName,
		Item = order.Item,
		Address = order.Address,
		Distance = order.Distance,
		BasePay = order.BasePay,
		TargetSeconds = order.TargetSeconds,
		Status = order.Status,
		CourierUserId = if order.Courier then order.Courier.UserId else nil,
		ShopPosition = order.Shop.Position,
		DropPosition = order.Drop.Position,
		PickedUpAt = order.PickedUpAt,
	}
end

local function broadcast()
	local list = {}
	for _, order in orders do
		table.insert(list, toPublic(order))
	end
	ordersChanged:FireAllClients(list)
end

local function shopConfig(shopId: string): Config.ShopConfig?
	for _, shop in Config.Shops do
		if shop.Id == shopId then
			return shop
		end
	end
	return nil
end

local function carriedBy(player: Player): { Order }
	local result = {}
	for _, order in orders do
		if order.Courier == player then
			table.insert(result, order)
		end
	end
	return result
end

local function isNear(player: Player, target: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - target.Position).Magnitude <= 16
end

-- Picks a shop by weight, then a customer point at least MinDistance away that has no open order.
local function createOrder(): Order?
	local shops = CollectionService:GetTagged("PickupZone")
	local drops = CollectionService:GetTagged("DeliveryPoint")
	if #shops == 0 or #drops == 0 then
		return nil
	end

	local totalWeight = 0
	local weighted: { { zone: BasePart, config: Config.ShopConfig } } = {}
	for _, zone in shops do
		local config = shopConfig(zone:GetAttribute("ShopId") :: string)
		if config and zone:IsA("BasePart") then
			table.insert(weighted, { zone = zone, config = config })
			totalWeight += config.Weight
		end
	end
	if #weighted == 0 then
		return nil
	end
	local pick = random:NextNumber(0, totalWeight)
	local chosen = weighted[#weighted]
	for _, entry in weighted do
		pick -= entry.config.Weight
		if pick <= 0 then
			chosen = entry
			break
		end
	end

	local busy: { [Instance]: boolean } = {}
	for _, order in orders do
		busy[order.Drop] = true
	end
	local candidates: { BasePart } = {}
	for _, drop in drops do
		if drop:IsA("BasePart") and not busy[drop] then
			local offset = drop.Position - chosen.zone.Position
			-- Streets run on a grid, so city-block distance is closer to the real trip than a straight line.
			if math.abs(offset.X) + math.abs(offset.Z) >= Config.Orders.MinDistance then
				table.insert(candidates, drop)
			end
		end
	end
	if #candidates == 0 then
		return nil
	end
	local drop = candidates[random:NextInteger(1, #candidates)]
	local offset = drop.Position - chosen.zone.Position
	local distance = math.floor(math.abs(offset.X) + math.abs(offset.Z))

	local order: Order = {
		Id = HttpService:GenerateGUID(false),
		Shop = chosen.zone,
		ShopId = chosen.config.Id,
		ShopName = chosen.config.Name,
		Item = chosen.config.Items[random:NextInteger(1, #chosen.config.Items)],
		Drop = drop,
		Address = (drop:GetAttribute("Address") :: string?) or "Unknown address",
		Distance = distance,
		BasePay = EconomyService.basePay(distance),
		TargetSeconds = math.floor(distance / Config.Orders.ReferenceSpeed + Config.Orders.TargetBufferSeconds),
		Status = "Posted",
	}
	orders[order.Id] = order
	return order
end

local function openOrderCount(): number
	local count = 0
	for _, order in orders do
		if order.Status == "Posted" then
			count += 1
		end
	end
	return count
end

local function refill()
	local wanted = math.max(Config.Orders.MinOpen, math.ceil(#Players:GetPlayers() * Config.Orders.OpenPerPlayer))
	local changed = false
	for _ = 1, wanted - openOrderCount() do
		if createOrder() then
			changed = true
		end
	end
	if changed then
		broadcast()
	end
end

local function release(order: Order)
	order.Status = "Posted"
	order.Courier = nil
	order.AcceptedAt = nil
	order.PickedUpAt = nil
end

local function accept(player: Player, order: Order): boolean
	if order.Status ~= "Posted" then
		notify:FireClient(player, "Someone else took that order.")
		return false
	end
	if #carriedBy(player) >= Config.Orders.MaxCarry then
		notify:FireClient(player, "You can't carry more orders. Deliver the one you have first.")
		return false
	end
	order.Status = "Accepted"
	order.Courier = player
	order.AcceptedAt = now()
	return true
end

local function onAcceptRequest(player: Player, orderId: unknown)
	if not running or type(orderId) ~= "string" then
		return
	end
	local order = orders[orderId]
	if order and accept(player, order) then
		broadcast()
	end
end

local function onPickup(player: Player, shopZone: BasePart)
	if not running or not isNear(player, shopZone) then
		return
	end
	-- Prefer an order this player already accepted here; otherwise take the best-paying open one.
	local target: Order? = nil
	for _, order in carriedBy(player) do
		if order.Shop == shopZone and order.Status == "Accepted" then
			target = order
		end
	end
	if not target then
		local best: Order? = nil
		for _, order in orders do
			if order.Shop == shopZone and order.Status == "Posted" and (not best or order.BasePay > best.BasePay) then
				best = order
			end
		end
		if not best then
			notify:FireClient(player, "No orders waiting at this shop right now.")
			return
		end
		if not accept(player, best) then
			return
		end
		target = best
	end
	assert(target)
	target.Status = "PickedUp"
	target.PickedUpAt = now()
	notify:FireClient(player, `Picked up {target.Item}. Deliver to {target.Address}!`)
	broadcast()
end

local function onDeliver(player: Player, dropZone: BasePart)
	if not running or not isNear(player, dropZone) then
		return
	end
	for _, order in carriedBy(player) do
		if order.Drop == dropZone and order.Status == "PickedUp" then
			local seconds = now() - (order.PickedUpAt or now())
			local pay, tip, reaction = EconomyService.payout(order.BasePay, seconds, order.TargetSeconds)
			EconomyService.awardDelivery(player, pay, tip)
			orders[order.Id] = nil
			local result: Types.DeliveryResult = {
				OrderId = order.Id,
				Item = order.Item,
				BasePay = pay,
				Tip = tip,
				Seconds = math.floor(seconds),
				TargetSeconds = order.TargetSeconds,
				Reaction = reaction,
			}
			deliveryCompleted:FireClient(player, result)
			refill()
			broadcast()
			return
		end
	end
	notify:FireClient(player, "This isn't the address for your order.")
end

local function hookPrompt(zone: Instance, handler: (Player, BasePart) -> ())
	if not zone:IsA("BasePart") then
		return
	end
	local prompt = zone:FindFirstChildWhichIsA("ProximityPrompt")
	if not prompt then
		local created = Instance.new("ProximityPrompt")
		created.MaxActivationDistance = 12
		created.RequiresLineOfSight = false
		created.Parent = zone
		prompt = created
	end
	assert(prompt)
	prompt.Triggered:Connect(function(player)
		handler(player, zone)
	end)
end

function OrderService.startRound()
	table.clear(orders)
	running = true
	refill()
	broadcast()
end

function OrderService.endRound()
	running = false
	table.clear(orders)
	broadcast()
end

function OrderService.init()
	for _, zone in CollectionService:GetTagged("PickupZone") do
		hookPrompt(zone, onPickup)
	end
	CollectionService:GetInstanceAddedSignal("PickupZone"):Connect(function(zone)
		hookPrompt(zone, onPickup)
	end)
	for _, zone in CollectionService:GetTagged("DeliveryPoint") do
		hookPrompt(zone, onDeliver)
	end
	CollectionService:GetInstanceAddedSignal("DeliveryPoint"):Connect(function(zone)
		hookPrompt(zone, onDeliver)
	end)

	Remotes.get("AcceptOrder").OnServerEvent:Connect(onAcceptRequest)

	Players.PlayerRemoving:Connect(function(player)
		for _, order in carriedBy(player) do
			release(order)
		end
		broadcast()
	end)
	Players.PlayerAdded:Connect(function(player)
		local list = {}
		for _, order in orders do
			table.insert(list, toPublic(order))
		end
		ordersChanged:FireClient(player, list)
	end)

	-- Orders accepted but not picked up in time go back on the board.
	task.spawn(function()
		while true do
			task.wait(1)
			if running then
				local changed = false
				for _, order in orders do
					if
						order.Status == "Accepted"
						and now() - (order.AcceptedAt or 0) > Config.Orders.AcceptTimeoutSeconds
					then
						if order.Courier then
							notify:FireClient(order.Courier, `Your {order.Item} order went back on the board.`)
						end
						release(order)
						changed = true
					end
				end
				if changed then
					broadcast()
				end
			end
		end
	end)
end

return OrderService
