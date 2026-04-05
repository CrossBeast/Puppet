local Wander = {}
Wander.__index = Wander

Wander.Name = "Wander"
Wander.Type = "Action"
Wander.Requires = { "Movement" }

local DEFAULTS = {
	radius = 20,
	waitTime = 2.0,
}

local MAX_POINT_ATTEMPTS = 10
local GROUND_RAY_START_HEIGHT = 50
local GROUND_RAY_DISTANCE = 100
local GROUND_OFFSET = 3

function Wander.new(puppet: any, config: { [string]: any })
	local self = setmetatable({}, Wander)
	self._puppet = puppet

	self._origin = config.origin or puppet.RootPart.Position
	self._radius = config.radius or DEFAULTS.radius
	self._waitTime = config.waitTime or DEFAULTS.waitTime
	self._waiting = false
	self._waitElapsed = 0

	self.Movement = nil
	self._reachedConn = nil
	self._stuckConn = nil

	return self
end

function Wander:Init()
	self._reachedConn = self.Movement.ReachedDestination:Connect(function()
		if self._puppet._destroyed then return end
		self._waiting = true
		self._waitElapsed = 0
	end)

	self._stuckConn = self.Movement.Stuck:Connect(function()
		if self._puppet._destroyed then return end
		self:_pickRandomPoint()
	end)

	self:_pickRandomPoint()
end

function Wander:Update(dt: number)
	if self._waiting then
		self._waitElapsed += dt
		if self._waitElapsed >= self._waitTime then
			self._waiting = false
			self._waitElapsed = 0
			self:_pickRandomPoint()
		end
		return
	end

	if not self.Movement:IsMoving() and not self._waiting then
		self:_pickRandomPoint()
	end
end

function Wander:Destroy()
	if self._reachedConn then self._reachedConn:Disconnect() end
	if self._stuckConn then self._stuckConn:Disconnect() end
	self.Movement:Stop()
end

function Wander:_pickRandomPoint()
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { self._puppet.Model }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	for _ = 1, MAX_POINT_ATTEMPTS do
		local angle = math.random() * math.pi * 2
		local minDist = math.min(self._radius * 0.3, 5)
		local dist = minDist + math.random() * (self._radius - minDist)
		local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local candidate = self._origin + offset

		local ground = workspace:Raycast(
			candidate + Vector3.new(0, GROUND_RAY_START_HEIGHT, 0),
			Vector3.new(0, -GROUND_RAY_DISTANCE, 0),
			rayParams
		)

		if ground then
			local target = ground.Position + Vector3.new(0, GROUND_OFFSET, 0)
			if self.Movement:WalkTo(target) then
				return
			end
		end
	end

	self.Movement:WalkTo(self._origin)
end

return Wander
