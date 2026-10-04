--!strict
-- One place that names every RemoteEvent. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"AcceptOrder", -- client -> server: (orderId)
	"OrdersChanged", -- server -> clients: ({PublicOrder})
	"DeliveryCompleted", -- server -> one client: (DeliveryResult)
	"Notify", -- server -> one client: (message)
	"RoundResults", -- server -> clients: (RoundRanking)
}

local folder: Instance
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		folder = created
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	assert(table.find(NAMES, name), `Unknown remote {name}`)
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), `{name} is not a RemoteEvent`)
	return remote
end

return Remotes
