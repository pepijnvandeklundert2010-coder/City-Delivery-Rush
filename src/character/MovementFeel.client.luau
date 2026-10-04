--!strict
--[[
	MovementFeel

	Makes the default R15 character move with weight:
	  1. Momentum: eases into and out of movement and swings smoothly into new directions
	  2. Leaning: tilts forward with speed and into turns
	  3. Landing: a springy crouch on landing, deeper after higher falls
	  4. Head and torso turn a little toward where the camera looks
	  5. Feet stay planted on slopes and stairs while standing or walking slowly (IKControl)
	  6. Animation blending: the default Animate script already blends walk and run by
	     speed; because speed now ramps instead of jumping, those blends happen gradually
	  7. Light camera bob while moving and a wider field of view at high speed

	Where it goes: a LocalScript named MovementFeel in StarterPlayer > StarterCharacterScripts.
	It runs again for every new character, works only on this player's screen, and leaves
	game rules alone: it never changes WalkSpeed, JumpPower, health or anything on the server.
	Other scripts that put the Humanoid in the Physics state (like wall running) take over
	movement; this script steps aside until they're done.
]]

local CONFIG = {
	-- 1. Momentum (higher = snappier). Rates are "per second" smoothing speeds.
	Acceleration = 7, -- how fast you reach full speed
	Deceleration = 9, -- how fast you come to a stop after letting go
	TurnSpeed = 9, -- how fast the move direction swings toward a new heading
	ReverseThreshold = -0.6, -- input this far opposite (dot product) means slow down, then turn
	AirControl = 0.6, -- multiplies the three rates above while airborne

	-- 2. Leaning (degrees)
	ForwardLean = 7, -- forward tilt at full speed
	TurnLeanPerRadian = 5, -- sideways tilt per radian/second of turning
	MaxTurnLean = 14,
	LeanSmoothing = 10,

	-- 3. Landing
	LandMinFallSpeed = 25, -- studs/second; slower landings get no squash
	LandMaxFallSpeed = 90, -- this fast or faster gets the full squash
	LandMaxDrop = 0.8, -- studs the hips dip on the hardest landing
	LandMaxTilt = 10, -- degrees forward on the hardest landing
	LandSpringSpeed = 16, -- spring stiffness
	LandSpringDamping = 0.5, -- below 1 gives a small bounce back up
	LandCameraDip = 0.6, -- studs the camera dips on the hardest landing

	-- 4. Head and upper body
	LookStrength = 0.8, -- 0 turns it off, 1 follows the camera fully (within the limits)
	LookMaxYaw = 70, -- degrees left/right
	LookMaxPitch = 35, -- degrees up/down
	WaistShare = 0.35, -- share of the turn done by the torso; the head does the rest
	LookSmoothing = 8,

	-- 5. Feet
	FootIKEnabled = true,
	FootIKMaxSpeed = 5, -- studs/second; above this the walk animation moves the feet freely
	FootIKSmoothTime = 0.06,
	FootReach = 1.5, -- how far below normal floor height a foot may reach
	MaxHipDrop = 1.2, -- how far the hips may lower so the low foot reaches the ground
	FootSmoothing = 12,

	-- 7. Camera
	BobAmountY = 0.12, -- studs
	BobAmountX = 0.07,
	BobStepsPerStud = 0.28, -- footstep rhythm; higher = faster bobbing
	BobFullSpeed = 26, -- bob reaches full strength at this speed
	BaseFieldOfView = 70,
	MaxFieldOfViewBoost = 10,
	FovStartSpeed = 17, -- speed (studs/second) where the boost starts
	FovFullSpeed = 30, -- speed where the boost is complete
	FovSmoothing = 6,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local root = character:WaitForChild("HumanoidRootPart") :: BasePart

if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
	warn("[MovementFeel] Needs an R15 character; turning off.")
	return
end

local rootMotor = character:WaitForChild("LowerTorso"):WaitForChild("Root") :: Motor6D
local waist = character:WaitForChild("UpperTorso"):WaitForChild("Waist") :: Motor6D
local neck = character:WaitForChild("Head"):WaitForChild("Neck") :: Motor6D

local rootBase = rootMotor.C0
local waistBase = waist.C0
local neckBase = neck.C0

local BIND_NAME = "MovementFeel"
local DISABLED_STATES = {
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

-- Exponential smoothing that behaves the same at any frame rate.
local function damp(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- State ---------------------------------------------------------------------------------

local moveDir = flat(root.CFrame.LookVector).Unit -- smoothed heading
local speedFactor = 0 -- smoothed 0..1 share of WalkSpeed
local pitch, roll = 0, 0 -- current lean, degrees
local lookYaw, lookPitch = 0, 0 -- current head/torso look, radians
local landX, landV = 0, 0 -- landing spring position (0..1) and velocity
local lowestFallVelocity = 0
local hipDrop = 0
local bobPhase = 0
local bobStrength = 0

-- Feet: one IKControl per leg, aimed at an attachment placed on the ground under the foot.
type Leg = {
	foot: BasePart,
	ik: IKControl,
	target: Attachment,
	pole: Attachment,
	weight: number,
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }
rayParams.IgnoreWater = true

local legs: { Leg } = {}

local function makeLeg(side: string, sideSign: number)
	local upperLeg = character:WaitForChild(side .. "UpperLeg") :: BasePart
	local foot = character:WaitForChild(side .. "Foot") :: BasePart

	local target = Instance.new("Attachment")
	target.Name = "MovementFeel_" .. side .. "FootTarget"
	target.Parent = workspace.Terrain

	-- The pole sits in front of the knee so knees bend forward, not sideways.
	local pole = Instance.new("Attachment")
	pole.Name = "MovementFeel_" .. side .. "KneePole"
	pole.Position = Vector3.new(sideSign * 0.5, -1, -4)
	pole.Parent = root

	local ik = Instance.new("IKControl")
	ik.Name = "MovementFeel_" .. side .. "Foot"
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = upperLeg
	ik.EndEffector = foot
	ik.Target = target
	ik.Pole = pole
	ik.SmoothTime = CONFIG.FootIKSmoothTime
	ik.Weight = 0
	ik.Parent = humanoid

	table.insert(legs, { foot = foot, ik = ik, target = target, pole = pole, weight = 0 })
end

if CONFIG.FootIKEnabled then
	makeLeg("Left", -1)
	makeLeg("Right", 1)
end

-- Landing ---------------------------------------------------------------------------------

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Landed then
		local fallSpeed = -lowestFallVelocity
		lowestFallVelocity = 0
		local impact = math.clamp(
			(fallSpeed - CONFIG.LandMinFallSpeed) / (CONFIG.LandMaxFallSpeed - CONFIG.LandMinFallSpeed),
			0,
			1
		)
		if impact > 0 then
			-- Kick the spring downward; it dips, then settles (with a small bounce).
			landV += impact * CONFIG.LandSpringSpeed * 2.2
		end
	end
end)

-- Per-frame steps ---------------------------------------------------------------------------

local function stepMomentum(dt: number, enabled: boolean, grounded: boolean)
	if not enabled then
		-- Something else is driving the character; follow along so we resume smoothly.
		local velocity = flat(root.AssemblyLinearVelocity)
		if velocity.Magnitude > 0.5 then
			moveDir = velocity.Unit
		end
		speedFactor = math.clamp(velocity.Magnitude / math.max(humanoid.WalkSpeed, 1), 0, 1)
		return
	end

	-- The default controls call Humanoid:Move every frame just before this runs, so
	-- MoveDirection here is the player's raw input for this frame.
	local raw = flat(humanoid.MoveDirection)
	local rawMag = math.min(raw.Magnitude, 1)
	local control = if grounded then 1 else CONFIG.AirControl
	local targetSpeed = rawMag

	if rawMag > 0.01 then
		local rawDir = raw.Unit
		if speedFactor < 0.15 then
			moveDir = rawDir -- from (almost) standing, start off in the new direction
		elseif moveDir:Dot(rawDir) < CONFIG.ReverseThreshold then
			targetSpeed = 0 -- sharp reversal: slow down first, then turn
		else
			local blended = moveDir:Lerp(rawDir, 1 - math.exp(-CONFIG.TurnSpeed * control * dt))
			if blended.Magnitude > 0.001 then
				moveDir = blended.Unit
			end
		end
	end

	local rate = if targetSpeed > speedFactor then CONFIG.Acceleration else CONFIG.Deceleration
	speedFactor = damp(speedFactor, targetSpeed, rate * control, dt)
	if speedFactor < 0.01 and targetSpeed == 0 then
		speedFactor = 0
	end

	-- Replace this frame's move with the smoothed one. Magnitude below 1 walks slower,
	-- so WalkSpeed itself (and any sprint script that sets it) stays untouched.
	humanoid:Move(moveDir * speedFactor, false)
end

local function stepLean(dt: number, enabled: boolean, previousDir: Vector3, speedRatio: number)
	local targetPitch, targetRoll = 0, 0
	if enabled and dt > 0 then
		local turnRate = math.atan2(previousDir:Cross(moveDir).Y, previousDir:Dot(moveDir)) / dt
		targetPitch = -CONFIG.ForwardLean * speedRatio
		targetRoll =
			math.clamp(turnRate * CONFIG.TurnLeanPerRadian * speedRatio, -CONFIG.MaxTurnLean, CONFIG.MaxTurnLean)
	end
	pitch = damp(pitch, targetPitch, CONFIG.LeanSmoothing, dt)
	roll = damp(roll, targetRoll, CONFIG.LeanSmoothing, dt)
end

local function stepLanding(dt: number)
	-- Damped spring pulling landX back to 0.
	local w = CONFIG.LandSpringSpeed
	local accel = -w * w * landX - 2 * CONFIG.LandSpringDamping * w * landV
	landV += accel * dt
	landX = math.clamp(landX + landV * dt, -0.3, 1.2)
end

local function stepFeet(dt: number, enabled: boolean, grounded: boolean, speed: number)
	if #legs == 0 then
		return
	end
	local targetWeight = if enabled and grounded then math.clamp(1 - speed / CONFIG.FootIKMaxSpeed, 0, 1) else 0
	local floorY = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local deepest = 0

	for _, leg in legs do
		local legTarget = targetWeight
		if targetWeight > 0 then
			local footPos = leg.foot.Position
			local origin = Vector3.new(footPos.X, root.Position.Y, footPos.Z)
			local reach = root.Position.Y - floorY + CONFIG.FootReach
			local hit = workspace:Raycast(origin, Vector3.new(0, -reach, 0), rayParams)
			if hit and hit.Normal.Y > 0.5 then
				leg.target.WorldPosition = hit.Position + Vector3.new(0, leg.foot.Size.Y / 2, 0)
				deepest = math.max(deepest, floorY - hit.Position.Y)
			else
				legTarget = 0
			end
		end
		leg.weight = damp(leg.weight, legTarget, CONFIG.FootSmoothing, dt)
		leg.ik.Weight = leg.weight
	end

	-- Lower the hips so the foot on the lower step can reach it.
	local targetDrop = math.clamp(deepest, 0, CONFIG.MaxHipDrop) * targetWeight
	hipDrop = damp(hipDrop, targetDrop, CONFIG.FootSmoothing, dt)
end

local function stepLook(dt: number, enabled: boolean)
	local targetYaw, targetPitch = 0, 0
	local camera = workspace.CurrentCamera
	if enabled and camera and CONFIG.LookStrength > 0 then
		local rel = root.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
		local yaw = math.atan2(-rel.X, -rel.Z) -- positive = looking left
		local up = math.asin(math.clamp(rel.Y, -1, 1))
		-- Don't twist like an owl when the camera looks back at the character.
		if math.abs(yaw) < math.rad(110) then
			targetYaw = math.clamp(yaw, -math.rad(CONFIG.LookMaxYaw), math.rad(CONFIG.LookMaxYaw)) * CONFIG.LookStrength
			targetPitch = math.clamp(up, -math.rad(CONFIG.LookMaxPitch), math.rad(CONFIG.LookMaxPitch))
				* CONFIG.LookStrength
		end
	end
	lookYaw = damp(lookYaw, targetYaw, CONFIG.LookSmoothing, dt)
	lookPitch = damp(lookPitch, targetPitch, CONFIG.LookSmoothing, dt)
end

local function stepCamera(dt: number, speed: number, grounded: boolean)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local targetStrength = if grounded then math.clamp(speed / CONFIG.BobFullSpeed, 0, 1) else 0
	bobStrength = damp(bobStrength, targetStrength, 8, dt)
	bobPhase = (bobPhase + speed * CONFIG.BobStepsPerStud * math.pi * dt) % (math.pi * 2)
	local bobX = math.sin(bobPhase) * CONFIG.BobAmountX * bobStrength
	local bobY = math.abs(math.sin(bobPhase)) * CONFIG.BobAmountY * bobStrength
	local dip = math.max(landX, 0) * CONFIG.LandCameraDip
	humanoid.CameraOffset = Vector3.new(bobX, bobY - dip, 0)

	local boost = math.clamp((speed - CONFIG.FovStartSpeed) / (CONFIG.FovFullSpeed - CONFIG.FovStartSpeed), 0, 1)
		* CONFIG.MaxFieldOfViewBoost
	camera.FieldOfView = damp(camera.FieldOfView, CONFIG.BaseFieldOfView + boost, CONFIG.FovSmoothing, dt)
end

local function applyPose()
	local drop = hipDrop + math.max(landX, 0) * CONFIG.LandMaxDrop
	local tilt = pitch - landX * CONFIG.LandMaxTilt
	rootMotor.C0 = rootBase * CFrame.new(0, -drop, 0) * CFrame.Angles(math.rad(tilt), 0, math.rad(roll))

	local share = CONFIG.WaistShare
	waist.C0 = waistBase * CFrame.Angles(lookPitch * share, lookYaw * share, 0)
	neck.C0 = neckBase * CFrame.Angles(lookPitch * (1 - share), lookYaw * (1 - share), 0)
end

local function onRenderStep(dt: number)
	local state = humanoid:GetState()
	local enabled = not DISABLED_STATES[state] and humanoid.Health > 0
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local velocity = root.AssemblyLinearVelocity
	if not grounded then
		lowestFallVelocity = math.min(lowestFallVelocity, velocity.Y)
	end
	local speed = flat(velocity).Magnitude
	local speedRatio = math.clamp(speed / math.max(humanoid.WalkSpeed, 1), 0, 1.3)

	local previousDir = moveDir
	stepMomentum(dt, enabled, grounded)
	stepLean(dt, enabled, previousDir, speedRatio)
	stepLanding(dt)
	stepFeet(dt, enabled, grounded, speed)
	stepLook(dt, enabled)
	stepCamera(dt, speed, grounded)
	applyPose()
end

-- Run right after the default controls read input, so our smoothed move replaces theirs.
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Input.Value + 1, onRenderStep)

local cleanedUp = false
local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	RunService:UnbindFromRenderStep(BIND_NAME)
	for _, leg in legs do
		leg.ik:Destroy()
		leg.target:Destroy()
		leg.pole:Destroy()
	end
	if rootMotor.Parent then
		rootMotor.C0 = rootBase
		waist.C0 = waistBase
		neck.C0 = neckBase
	end
	humanoid.CameraOffset = Vector3.zero
end

humanoid.Died:Connect(cleanup)
character.AncestryChanged:Connect(function()
	if not character:IsDescendantOf(workspace) then
		cleanup()
	end
end)
script.Destroying:Connect(cleanup)

Players.LocalPlayer.CharacterRemoving:Connect(cleanup)
