--!strict
-- Builds a greybox city when the place has no Workspace.City folder yet, so the prototype
-- is playable in an empty place. Once a hand-built city exists (with the same tags and
-- attributes on its pickup and delivery parts), this generator is skipped.
--
-- Tags it creates:
--   PickupZone    attributes ShopId, ShopName
--   DeliveryPoint attribute Address

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local BLOCK = 80
local ROAD = 24
local GRID = 4
local STEP = BLOCK + ROAD
local HALF_SPAN = (GRID * BLOCK + (GRID + 1) * ROAD) / 2

-- One row per block row (north to south). Shops blocks hold the shops from Config.Shops in order.
local LAYOUT = {
	{ "Depot", "Shops", "Shops", "Apartments" },
	{ "Houses", "Apartments", "Park", "Houses" },
	{ "Houses", "Houses", "Apartments", "Houses" },
	{ "Apartments", "Houses", "Houses", "Apartments" },
}

local STREETS = { "Oak Street", "Maple Street", "Elm Street", "Pine Street", "Cedar Street" }

local random = Random.new(2026)

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function blockCenter(col: number, row: number): Vector3
	local offset = -((GRID - 1) / 2) * STEP
	return Vector3.new(offset + (col - 1) * STEP, 0, offset + (row - 1) * STEP)
end

local function addLabel(target: BasePart, text: string, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 150
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = target
end

local function addZone(parent: Instance, position: Vector3, color: Color3, tag: string, actionText: string): Part
	local zone = part({
		Name = tag,
		Size = Vector3.new(8, 0.4, 6),
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	}, parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = zone
	CollectionService:AddTag(zone, tag)
	return zone
end

-- Each block has four lots; lot (a, b) faces the road on its outer z side.
local function lots(center: Vector3): { { position: Vector3, facing: number } }
	local result = {}
	for _, b in { -1, 1 } do
		for _, a in { -1, 1 } do
			table.insert(result, { position = center + Vector3.new(a * 20, 0, b * 20), facing = b })
		end
	end
	return result
end

local function streetFor(row: number, facing: number): string
	local index = if facing < 0 then row else row + 1
	return STREETS[index]
end

function MapBuilder.build()
	if workspace:FindFirstChild("City") then
		return
	end

	local city = Instance.new("Folder")
	city.Name = "City"

	-- Ground and roads
	part({
		Name = "Ground",
		Size = Vector3.new(HALF_SPAN * 2 + 80, 1, HALF_SPAN * 2 + 80),
		Position = Vector3.new(0, -0.45, 0),
		Color = Color3.fromRGB(96, 140, 72),
		Material = Enum.Material.Grass,
	}, city)
	for i = 0, GRID do
		local line = -HALF_SPAN + ROAD / 2 + i * STEP
		part({
			Name = "Road",
			Size = Vector3.new(HALF_SPAN * 2, 0.2, ROAD),
			Position = Vector3.new(0, 0.1, line),
			Color = Color3.fromRGB(55, 55, 60),
			Material = Enum.Material.Asphalt,
		}, city)
		part({
			Name = "Road",
			Size = Vector3.new(ROAD, 0.2, HALF_SPAN * 2),
			Position = Vector3.new(line, 0.1, 0),
			Color = Color3.fromRGB(55, 55, 60),
			Material = Enum.Material.Asphalt,
		}, city)
	end

	local shopIndex = 1
	local houseNumber = 1
	local benchNumber = 1

	for row, columns in LAYOUT do
		for col, kind in columns do
			local center = blockCenter(col, row)
			local block = Instance.new("Model")
			block.Name = `{kind}_{row}_{col}`
			block.Parent = city

			part({
				Name = "Sidewalk",
				Size = Vector3.new(BLOCK, 0.6, BLOCK),
				Position = center + Vector3.new(0, 0.3, 0),
				Color = if kind == "Park" then Color3.fromRGB(84, 160, 70) else Color3.fromRGB(180, 180, 175),
				Material = if kind == "Park" then Enum.Material.Grass else Enum.Material.Concrete,
			}, block)

			if kind == "Depot" then
				local garage = part({
					Name = "Depot",
					Size = Vector3.new(50, 16, 24),
					Position = center + Vector3.new(0, 8.6, -16),
					Color = Color3.fromRGB(60, 90, 160),
				}, block)
				addLabel(garage, "Delivery Depot", 12)
				for i = -1, 1 do
					local spawn = Instance.new("SpawnLocation")
					spawn.Anchored = true
					spawn.Size = Vector3.new(6, 1, 6)
					spawn.Position = center + Vector3.new(i * 10, 1.1, 16)
					spawn.Neutral = true
					spawn.Duration = 0
					spawn.Parent = block
				end
			elseif kind == "Park" then
				for _ = 1, 6 do
					local spot = center + Vector3.new(random:NextNumber(-30, 30), 0, random:NextNumber(-30, 30))
					part({
						Name = "Trunk",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(8, 2, 2),
						CFrame = CFrame.new(spot + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
						Color = Color3.fromRGB(110, 80, 50),
					}, block)
					part({
						Name = "Leaves",
						Shape = Enum.PartType.Ball,
						Size = Vector3.new(9, 9, 9),
						Position = spot + Vector3.new(0, 10, 0),
						Color = Color3.fromRGB(60, 130, 60),
						Material = Enum.Material.Grass,
						CanCollide = false,
					}, block)
				end
				for _, lot in lots(center) do
					local bench = part({
						Name = "Bench",
						Size = Vector3.new(6, 1, 2),
						Position = lot.position + Vector3.new(0, 1.6, lot.facing * 12),
						Color = Color3.fromRGB(140, 100, 60),
					}, block)
					local zone = addZone(
						block,
						bench.Position + Vector3.new(0, -0.9, lot.facing * 3),
						Color3.fromRGB(80, 200, 255),
						"DeliveryPoint",
						"Deliver"
					)
					zone:SetAttribute("Address", `Park bench {benchNumber}`)
					benchNumber += 1
				end
			else
				for _, lot in lots(center) do
					local front = lot.position + Vector3.new(0, 0, lot.facing * 19)
					if kind == "Shops" and shopIndex <= #Config.Shops then
						local shop = Config.Shops[shopIndex]
						shopIndex += 1
						local building = part({
							Name = shop.Name,
							Size = Vector3.new(30, 18, 30),
							Position = lot.position + Vector3.new(0, 9.6, 0),
							Color = shop.Color,
						}, block)
						addLabel(building, shop.Name, 12)
						local zone = addZone(
							block,
							front + Vector3.new(0, 0.8, 0),
							Color3.fromRGB(255, 220, 60),
							"PickupZone",
							"Pick up order"
						)
						zone:SetAttribute("ShopId", shop.Id)
						zone:SetAttribute("ShopName", shop.Name)
					else
						local isApartment = kind == "Apartments"
						local height = if isApartment then random:NextInteger(36, 60) else random:NextInteger(12, 18)
						local shade = random:NextInteger(150, 235)
						part({
							Name = if isApartment then "Apartment" else "House",
							Size = Vector3.new(if isApartment then 32 else 24, height, if isApartment then 32 else 24),
							Position = lot.position + Vector3.new(0, height / 2 + 0.6, 0),
							Color = Color3.fromRGB(shade, random:NextInteger(120, shade), random:NextInteger(100, 200)),
						}, block)
						local zone = addZone(
							block,
							front + Vector3.new(0, 0.8, 0),
							Color3.fromRGB(80, 200, 255),
							"DeliveryPoint",
							"Deliver"
						)
						local street = streetFor(row, lot.facing)
						zone:SetAttribute(
							"Address",
							if isApartment then `{houseNumber} {street}, apartments` else `{houseNumber} {street}`
						)
						houseNumber += 1
					end
				end
			end
		end
	end

	city.Parent = workspace
end

return MapBuilder
