--!strict
-- Shared types. PublicOrder is what clients receive; the server keeps the full Order.

export type OrderStatus = "Posted" | "Accepted" | "PickedUp"

export type PublicOrder = {
	Id: string,
	ShopId: string,
	ShopName: string,
	Item: string,
	Address: string,
	Distance: number,
	BasePay: number,
	TargetSeconds: number,
	Status: OrderStatus,
	CourierUserId: number?,
	ShopPosition: Vector3,
	DropPosition: Vector3,
	PickedUpAt: number?, -- server time (workspace:GetServerTimeNow())
}

export type DeliveryResult = {
	OrderId: string,
	Item: string,
	BasePay: number,
	Tip: number,
	Seconds: number,
	TargetSeconds: number,
	Reaction: string,
}

export type RoundRanking = {
	{
		UserId: number,
		Name: string,
		Deliveries: number,
		Coins: number,
		Bonus: number,
	}
}

export type RoundState = "Intermission" | "Countdown" | "Running" | "Results"

return {}
