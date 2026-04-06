--[[
	Patrol (Action)
	- Cycles through waypoints
	- Configurable wait time
	- Requires Movement
]]

local Patrol = {}
Patrol.__index = Patrol

Patrol.Name = "Patrol"
Patrol.Type = "Action"
Patrol.Requires = { "Movement" }

local DEFAULTS = {
	waitTime = 1.0,
}

function Patrol.new(puppet: any, config: { [string]: any })
	local self = setmetatable({}, Patrol)
	self._puppet = puppet

	assert(type(config.points) == "table" and #config.points > 0,
		"[Puppet:Patrol] Config must include 'points' with at least one Vector3")

	self._points = config.points
	self._waitTime = config.waitTime or DEFAULTS.waitTime
	self._currentIndex = 1
	self._waiting = false
	self._waitElapsed = 0

	self.Movement = nil
	self._reachedConn = nil
	self._stuckConn = nil

	return self
end

function Patrol:Init()
	self._reachedConn = self.Movement.ReachedDestination:Connect(function()
		if self._puppet._destroyed then return end
		self._waiting = true
		self._waitElapsed = 0
	end)

	self._stuckConn = self.Movement.Stuck:Connect(function()
		if self._puppet._destroyed then return end
		self:_advance()
		self.Movement:WalkTo(self._points[self._currentIndex])
	end)

	self.Movement:WalkTo(self._points[self._currentIndex])
end

function Patrol:Update(dt: number)
	if self._waiting then
		self._waitElapsed += dt
		if self._waitElapsed >= self._waitTime then
			self._waiting = false
			self._waitElapsed = 0
			self:_advance()
			self.Movement:WalkTo(self._points[self._currentIndex])
		end
		return
	end

	if not self.Movement:IsMoving() and not self._waiting then
		self.Movement:WalkTo(self._points[self._currentIndex])
	end
end

function Patrol:Destroy()
	if self._reachedConn then self._reachedConn:Disconnect() end
	if self._stuckConn then self._stuckConn:Disconnect() end
	self.Movement:Stop()
end

function Patrol:_advance()
	self._currentIndex += 1
	if self._currentIndex > #self._points then
		self._currentIndex = 1
	end
end

return Patrol
