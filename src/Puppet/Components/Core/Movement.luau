local PathfindingService = game:GetService("PathfindingService")
local Signal = require(script.Parent.Parent.Parent.Packages.Signal)

local Movement = {}
Movement.__index = Movement

Movement.Name = "Movement"
Movement.Type = "Core"

local DEFAULTS = {
	walkSpeed = 12,
	runSpeed = 24,
	arrivalRadius = 4,
}

local DIRECT_MOVE_MAX_DISTANCE = 30
local DIRECT_MOVE_FALLBACK_MAX_DISTANCE = 42
local DIRECT_MOVE_VERTICAL_LIMIT = 4.5
local DIRECT_MOVE_RAY_HEIGHT = 2

local PATH_AGENT_RADIUS = 2
local PATH_AGENT_HEIGHT = 5
local PATH_WAYPOINT_SPACING = 4

local REPATH_COOLDOWN = 0.5
local MOVE_COMMAND_INTERVAL = 0.05

local STUCK_TIME_THRESHOLD = 2.0
local STUCK_DISTANCE_PER_TICK = 0.1
local STUCK_MAX_RETRIES = 3

local WAYPOINT_JUMP_VERTICAL_MIN = 1.5

function Movement.new(puppet: any, config: { [string]: any })
	local self = setmetatable({}, Movement)
	self._puppet = puppet

	self._walkSpeed = config.walkSpeed or DEFAULTS.walkSpeed
	self._runSpeed = config.runSpeed or DEFAULTS.runSpeed
	self._arrivalRadius = config.arrivalRadius or DEFAULTS.arrivalRadius

	self._isMoving = false
	self._isStuck = false
	self._destination = nil
	self._currentPath = nil
	self._waypoints = {}
	self._waypointIndex = 1

	self._stuckTime = 0
	self._stuckRetryCount = 0
	self._lastPosition = nil

	self._lastPathCompute = 0
	self._lastMoveCommand = 0
	self._lastMoveTarget = nil
	self._pathBlockedConn = nil

	self.ReachedDestination = Signal.new()
	self.Stuck = Signal.new()

	puppet.Humanoid.WalkSpeed = self._walkSpeed

	return self
end

function Movement:Init() end

function Movement:Update(dt: number)
	if not self._isMoving then
		self._stuckTime = 0
		self._lastPosition = nil
		return
	end

	self:_advanceWaypoints()
	self:_issueMovement()
	self:_detectStuck(dt)
end

function Movement:WalkTo(position: Vector3): boolean
	if self._puppet._destroyed then return false end
	if typeof(position) ~= "Vector3" then
		warn("[Puppet:Movement] WalkTo position must be a Vector3")
		return false
	end

	local rootPart = self._puppet.RootPart
	if not rootPart or not rootPart.Parent then return false end

	self._destination = position

	-- If already doing a direct move, just redirect seamlessly (no recompute)
	if self._isMoving and not self._currentPath then
		self._waypoints = { { Position = position, Action = Enum.PathWaypointAction.Walk } }
		self._waypointIndex = 1
		return true
	end

	-- Throttle path recomputation
	local now = tick()
	if self._isMoving and (now - self._lastPathCompute) < REPATH_COOLDOWN then
		return true
	end
	self._lastPathCompute = now

	local distance = (position - rootPart.Position).Magnitude
	if distance <= DIRECT_MOVE_MAX_DISTANCE and self:_canDirectMove(position) then
		return self:_setDirectWaypoint(position)
	end

	local ok = self:_computePath(position)
	if not ok then
		if distance <= DIRECT_MOVE_FALLBACK_MAX_DISTANCE and self:_canDirectMove(position) then
			return self:_setDirectWaypoint(position)
		end
	end
	return ok
end

function Movement:Stop()
	self:_clearPathConnection()
	self._isMoving = false
	self._destination = nil
	self._currentPath = nil
	table.clear(self._waypoints)
	self._waypointIndex = 1
	self._isStuck = false
	self._stuckTime = 0
	self._stuckRetryCount = 0
	self._lastPosition = nil
	self._lastMoveTarget = nil

	local humanoid = self._puppet.Humanoid
	local rootPart = self._puppet.RootPart
	if humanoid and rootPart and rootPart.Parent then
		humanoid:MoveTo(rootPart.Position)
	end
end

function Movement:IsMoving(): boolean
	return self._isMoving
end

function Movement:IsStuck(): boolean
	return self._isStuck
end

function Movement:SetConfig(config: { [string]: any })
	if config.walkSpeed ~= nil then
		self._walkSpeed = config.walkSpeed
		self._puppet.Humanoid.WalkSpeed = self._walkSpeed
	end
	if config.runSpeed ~= nil then
		self._runSpeed = config.runSpeed
	end
	if config.arrivalRadius ~= nil then
		self._arrivalRadius = config.arrivalRadius
	end
end

function Movement:Destroy()
	self:_clearPathConnection()
	self:Stop()
	self.ReachedDestination:Destroy()
	self.Stuck:Destroy()
end

function Movement:_canDirectMove(position)
	local origin = self._puppet.RootPart.Position
	if math.abs(position.Y - origin.Y) > DIRECT_MOVE_VERTICAL_LIMIT then
		return false
	end

	local travel = position - origin
	if travel.Magnitude < 1e-3 then return true end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { self._puppet.Model }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(
		origin + Vector3.new(0, DIRECT_MOVE_RAY_HEIGHT, 0),
		travel,
		rayParams
	)
	return result == nil
end

function Movement:_setDirectWaypoint(position)
	self._currentPath = nil
	self._waypoints = { { Position = position, Action = Enum.PathWaypointAction.Walk } }
	self._waypointIndex = 1
	self._isMoving = true
	self._stuckRetryCount = 0
	return true
end

function Movement:_clearPathConnection()
	if self._pathBlockedConn then
		self._pathBlockedConn:Disconnect()
		self._pathBlockedConn = nil
	end
end

function Movement:_computePath(position)
	self:_clearPathConnection()

	local path = PathfindingService:CreatePath({
		AgentRadius = PATH_AGENT_RADIUS,
		AgentHeight = PATH_AGENT_HEIGHT,
		AgentCanJump = true,
		WaypointSpacing = PATH_WAYPOINT_SPACING,
	})

	local ok, err = pcall(function()
		path:ComputeAsync(self._puppet.RootPart.Position, position)
	end)

	if not ok then
		warn("[Puppet:Movement] Path computation error: " .. tostring(err))
		self._isMoving = false
		return false
	end

	if path.Status ~= Enum.PathStatus.Success then
		self._isMoving = false
		return false
	end

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		self._isMoving = false
		return false
	end

	self._currentPath = path
	self._waypoints = waypoints
	self._waypointIndex = if #waypoints >= 2 then 2 else 1
	self._isMoving = true
	self._stuckRetryCount = 0

	-- Immediate repath when path is blocked ahead
	self._pathBlockedConn = path.Blocked:Connect(function(blockedIndex)
		if blockedIndex >= self._waypointIndex and self._destination then
			self._lastPathCompute = 0
			self:WalkTo(self._destination)
		end
	end)

	return true
end

function Movement:_advanceWaypoints()
	local waypoints = self._waypoints
	local count = #waypoints
	if count == 0 then
		self._isMoving = false
		return
	end

	local index = self._waypointIndex
	local rootPos = self._puppet.RootPart.Position

	while index <= count do
		local wp = waypoints[index]
		if not wp then break end
		if self:_horizontalDistance(rootPos, wp.Position) <= self._arrivalRadius then
			index += 1
		else
			break
		end
	end
	self._waypointIndex = index

	if index > count then
		local dest = self._destination
		if dest and self:_horizontalDistance(rootPos, dest) <= self._arrivalRadius then
			self._isMoving = false
			self._destination = nil
			-- Only fire if NPC actually traveled (suppress trivial arrivals from micro-moves)
			local moveTime = tick() - self._lastPathCompute
			if moveTime > 0.1 then
				self.ReachedDestination:Fire()
			end
		elseif dest then
			self._lastPathCompute = 0
			self:WalkTo(dest)
		else
			self._isMoving = false
		end
	end
end

function Movement:_issueMovement()
	if not self._isMoving then return end

	local waypoint = self._waypoints[self._waypointIndex]
	if not waypoint then return end

	if waypoint.Action == Enum.PathWaypointAction.Jump then
		local verticalDelta = waypoint.Position.Y - self._puppet.RootPart.Position.Y
		if verticalDelta >= WAYPOINT_JUMP_VERTICAL_MIN then
			self._puppet.Humanoid.Jump = true
		end
	end

	local now = tick()
	local targetPos = waypoint.Position
	local targetChanged = not self._lastMoveTarget
		or (self._lastMoveTarget - targetPos).Magnitude > 0.2

	if targetChanged or (now - self._lastMoveCommand >= MOVE_COMMAND_INTERVAL) then
		self._puppet.Humanoid:MoveTo(targetPos)
		self._lastMoveCommand = now
		self._lastMoveTarget = targetPos
	end
end

function Movement:_detectStuck(dt)
	if not self._isMoving then
		self._isStuck = false
		self._stuckTime = 0
		return
	end

	local rootPos = self._puppet.RootPart.Position

	if self._lastPosition then
		local moved = (rootPos - self._lastPosition).Magnitude
		if moved < STUCK_DISTANCE_PER_TICK then
			self._stuckTime += dt
		else
			self._stuckTime = 0
			self._stuckRetryCount = 0
		end
	end

	self._lastPosition = rootPos
	self._isStuck = self._stuckTime > STUCK_TIME_THRESHOLD

	if self._isStuck then
		self._stuckRetryCount += 1
		self._stuckTime = 0

		if self._stuckRetryCount > STUCK_MAX_RETRIES then
			self:Stop()
			self.Stuck:Fire()
			return
		end

		self._puppet.Humanoid.Jump = true

		if self._destination then
			self._lastPathCompute = 0
			self:WalkTo(self._destination)
		end
	end
end

function Movement:_horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

return Movement
