--!strict
-- All gameplay numbers in one place so they can be balanced after playtests.

export type TipTier = {
	MaxRatio: number, -- delivery time / target time, at or below this
	TipShare: number, -- tip as a share of base pay
	Reaction: string,
}

export type ShopConfig = {
	Id: string,
	Name: string,
	Items: { string },
	Weight: number,
	Color: Color3,
}

local Config = {}

Config.Round = {
	IntermissionSeconds = 20,
	CountdownSeconds = 5,
	RoundSeconds = 300,
	ResultsSeconds = 15,
	MinPlayers = 1,
}

Config.Orders = {
	OpenPerPlayer = 1.5,
	MinOpen = 4,
	MaxCarry = 1,
	AcceptTimeoutSeconds = 30,
	-- Studs per second used to set each order's target time (default walk speed is 16).
	ReferenceSpeed = 16,
	TargetBufferSeconds = 15,
	MinDistance = 60,
}

Config.Pay = {
	Base = 10,
	PerStud = 0.05,
	TipTiers = {
		{ MaxRatio = 0.5, TipShare = 1.0, Reaction = "Wow, super fast!" },
		{ MaxRatio = 0.75, TipShare = 0.5, Reaction = "Thanks, that was quick!" },
		{ MaxRatio = 1.0, TipShare = 0.2, Reaction = "Thank you!" },
	} :: { TipTier },
	NoTipReaction = "Finally...",
	-- Deliveries slower than LateRatio x target only get LateShare of base pay.
	LateRatio = 2,
	LateShare = 0.5,
	LateReaction = "This is cold!",
	-- Bonus coins for 1st, 2nd and 3rd place at the end of a round.
	PodiumBonus = { 50, 25, 10 },
}

Config.Shops = {
	{
		Id = "Pizza",
		Name = "Pizza Place",
		Items = { "Pizza", "Garlic bread" },
		Weight = 3,
		Color = Color3.fromRGB(214, 69, 65),
	},
	{
		Id = "Burger",
		Name = "Burger Bar",
		Items = { "Burger menu", "Fries" },
		Weight = 3,
		Color = Color3.fromRGB(242, 159, 5),
	},
	{
		Id = "Bakery",
		Name = "Bakery",
		Items = { "Croissants", "Birthday cake" },
		Weight = 2,
		Color = Color3.fromRGB(196, 140, 92),
	},
	{
		Id = "Grocery",
		Name = "Grocery Store",
		Items = { "Groceries", "Milk and eggs" },
		Weight = 2,
		Color = Color3.fromRGB(76, 175, 80),
	},
	{
		Id = "Pharmacy",
		Name = "Pharmacy",
		Items = { "Medicine", "Vitamins" },
		Weight = 1,
		Color = Color3.fromRGB(38, 166, 154),
	},
	{
		Id = "Flowers",
		Name = "Flower Shop",
		Items = { "Bouquet", "Plant" },
		Weight = 1,
		Color = Color3.fromRGB(236, 64, 122),
	},
} :: { ShopConfig }

Config.Data = {
	StoreName = "PlayerData_v1",
	AutosaveSeconds = 120,
}

return Config
