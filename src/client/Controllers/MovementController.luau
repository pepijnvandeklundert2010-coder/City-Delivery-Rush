--!strict
-- Character movement: sprint (hold Left Shift) with a stamina bar, a faster run animation,
-- and wall running. Jump next to a wall while moving along it to run on it; jump again to
-- leap off. The local player owns their character's physics, so this all runs on the client.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local Movement = Config.Movement
local WallRunConfig = Movement.WallRun

local MovementController = {}

type WallRun = {
	normal: Vector3, -- points away from the wall, flat
	direction: Vector3, -- along the wall, flat
	startedAt: number,
	verticalSpeed: number,
}

local player = Players.LocalPlayer

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local wallRunTrack: AnimationTrack? = nil

local stamina = Movement.StaminaMax
local sprintHeld = false
local sprinting = false
local lastStaminaUse = 0

local wallRun: WallRun? = nil
local lastWall: Instance? = nil
local cooldownUntil = 0
local lastJumpRequest = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- Stamina bar, just above the order card.
local gui = Instance.new("ScreenGui")
gui.Name = "Movement"
gui.ResetOnSpawn = false

local barBack = Instance.new("Frame")
barBack.Name = "StaminaBar"
barBack.AnchorPoint = Vector2.new(0.5, 1)
barBack.Position = UDim2.new(0.5, 0, 1, -164)
barBack.Size = UDim2.fromOffset(240, 10)
barBack.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
barBack.BackgroundTransparency = 0.3
barBack.Parent = gui
local backCorner = Instance.new("UICorner")
backCorner.CornerRadius = UDim.new(1, 0)
backCorner.Parent = barBack

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(1, 1)
barFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
barFill.Parent = barBack
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = barFill

-- Closest steep wall on the character's left or right, if any.
local function findWall(): RaycastResult?
	local r = root
	if not r then
		return nil
	end
	local right = r.CFrame.RightVector
	local best: RaycastResult? = nil
	for _, side in { right, -right } do
		local hit = workspace:Raycast(r.Position, side * WallRunConfig.DetectDistance, rayParams)
		if hit and math.abs(hit.Normal.Y) < 0.3 and hit.Instance.CanCollide then
			if not best or hit.Distance < best.Distance then
				best = hit
			end
		end
	end
	return best
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function startWallRun(hit: RaycastResult)
	local r, h = root, humanoid
	if not r or not h then
		return
	end
	local normal = flat(hit.Normal).Unit
	local heading = flat(r.AssemblyLinearVelocity)
	if heading.Magnitude < 2 then
		heading = flat(r.CFrame.LookVector)
	end
	-- Keep only the part of the heading that runs along the wall.
	local along = heading - normal * heading:Dot(normal)
	if along.Magnitude < 0.5 then
		return -- facing straight into the wall
	end

	stamina -= WallRunConfig.StaminaCost
	lastStaminaUse = os.clock()
	lastWall = hit.Instance
	wallRun = {
		normal = normal,
		direction = along.Unit,
		startedAt = os.clock(),
		verticalSpeed = WallRunConfig.StartUpSpeed,
	}
	h.AutoRotate = false
	-- Physics state hands movement to this script and pauses the default animations.
	h:ChangeState(Enum.HumanoidStateType.Physics)
	if wallRunTrack then
		wallRunTrack:Play(0.1)
	end
end

local function endWallRun(jump: boolean)
	local run = wallRun
	wallRun = nil
	cooldownUntil = os.clock() + WallRunConfig.CooldownSeconds
	if wallRunTrack then
		wallRunTrack:Stop(0.15)
	end
	local r, h = root, humanoid
	if not run or not r or not h then
		return
	end
	r.CFrame = CFrame.lookAt(r.Position, r.Position + run.direction)
	if jump then
		r.AssemblyLinearVelocity = run.normal * WallRunConfig.JumpOffSpeed
			+ run.direction * (WallRunConfig.Speed * 0.5)
			+ Vector3.yAxis * WallRunConfig.JumpUpSpeed
	end
	h.AutoRotate = true
	h:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function stepWallRun(dt: number)
	local run = wallRun
	local r = root
	if not run or not r then
		return
	end
	local hit = findWall()
	if
		os.clock() - run.startedAt > WallRunConfig.MaxSeconds
		or not hit
		or flat(hit.Normal).Unit:Dot(run.normal) < 0.8
	then
		endWallRun(false)
		return
	end

	run.verticalSpeed -= WallRunConfig.Gravity * dt
	-- A small push into the wall keeps the character from drifting off it.
	r.AssemblyLinearVelocity = run.direction * WallRunConfig.Speed + Vector3.yAxis * run.verticalSpeed - run.normal * 2

	-- Face along the wall and lean away from it, feet toward the wall.
	local facing = CFrame.lookAt(r.Position, r.Position + run.direction)
	local wallOnRight = (-run.normal):Dot(facing.RightVector) > 0
	local lean = math.rad(if wallOnRight then WallRunConfig.LeanDegrees else -WallRunConfig.LeanDegrees)
	r.CFrame = facing * CFrame.Angles(0, 0, lean)
end

local function stepSprint(dt: number)
	local h = humanoid
	local moving = h ~= nil and h.MoveDirection.Magnitude > 0.1
	local allowed = sprinting or stamina >= Movement.MinStaminaToSprint
	sprinting = sprintHeld and moving and allowed and stamina > 0 and wallRun == nil

	if sprinting then
		stamina = math.max(0, stamina - Movement.StaminaDrainPerSecond * dt)
		lastStaminaUse = os.clock()
	elseif os.clock() - lastStaminaUse > Movement.StaminaRegenDelaySeconds then
		stamina = math.min(Movement.StaminaMax, stamina + Movement.StaminaRegenPerSecond * dt)
	end

	if h then
		h.WalkSpeed = if sprinting then Movement.SprintSpeed else Movement.WalkSpeed
	end

	local camera = workspace.CurrentCamera
	if camera then
		local target = if sprinting then Movement.SprintFieldOfView else Movement.NormalFieldOfView
		camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * 8)
	end

	local share = stamina / Movement.StaminaMax
	barFill.Size = UDim2.fromScale(share, 1)
	barFill.BackgroundColor3 = if share < Movement.MinStaminaToSprint / Movement.StaminaMax
		then Color3.fromRGB(255, 110, 100)
		else Color3.fromRGB(90, 200, 255)
	barBack.Visible = share < 1 or sprinting
end

local function onJumpRequest()
	local h = humanoid
	if not h then
		return
	end
	local now = os.clock()
	-- JumpRequest repeats while the button is held; a gap means a fresh press.
	local freshPress = now - lastJumpRequest > 0.15
	lastJumpRequest = now

	local run = wallRun
	if run then
		if freshPress and now - run.startedAt > 0.15 then
			endWallRun(true)
		end
		return
	end
	if now < cooldownUntil or stamina < WallRunConfig.StaminaCost then
		return
	end
	local state = h:GetState()
	if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
		return
	end
	local hit = findWall()
	-- One run per wall until the player lands, so they can't climb a single wall forever.
	if hit and hit.Instance ~= lastWall then
		startWallRun(hit)
	end
end

local function useRunAnimation(character: Model)
	local animate = character:WaitForChild("Animate", 10)
	local run = animate and animate:FindFirstChild("run")
	if run then
		for _, child in run:GetChildren() do
			if child:IsA("Animation") then
				-- The default Animate script reloads its run set when this changes.
				child.AnimationId = Movement.RunAnimationId
			end
		end
	end
end

local function onCharacterAdded(character: Model)
	wallRun = nil
	lastWall = nil
	stamina = Movement.StaminaMax
	rayParams.FilterDescendantsInstances = { character }

	local h = character:WaitForChild("Humanoid", 10)
	local r = character:WaitForChild("HumanoidRootPart", 10)
	if not h or not h:IsA("Humanoid") or not r or not r:IsA("BasePart") then
		return
	end
	humanoid = h
	root = r

	wallRunTrack = nil
	local animator = h:FindFirstChildOfClass("Animator") or h:WaitForChild("Animator", 5)
	if animator and animator:IsA("Animator") then
		local animation = Instance.new("Animation")
		animation.AnimationId = Movement.RunAnimationId
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		wallRunTrack = track
	end

	h.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			lastWall = nil
		elseif new == Enum.HumanoidStateType.Dead then
			wallRun = nil
		end
	end)

	if h.RigType == Enum.HumanoidRigType.R15 then
		task.spawn(useRunAnimation, character)
	end
end

function MovementController.start()
	gui.Parent = player:WaitForChild("PlayerGui")

	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)

	ContextActionService:BindAction("Sprint", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			sprintHeld = true
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			sprintHeld = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("Sprint", "Sprint")
	ContextActionService:SetPosition("Sprint", UDim2.new(1, -170, 1, -150))

	UserInputService.JumpRequest:Connect(onJumpRequest)

	RunService.Heartbeat:Connect(function(dt)
		stepWallRun(dt)
		stepSprint(dt)
	end)
end

return MovementController
