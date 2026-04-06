--[[
	Follow (Action)
	- Tails a target at a set distance
	- Buffer zone to prevent micro-stepping
	- Requires Movement
]]

local Follow = {}
Follow.__index = Follow

Follow.Name = "Follow"
Follow.Type = "Action"
Follow.Requires = { "Movement" }

local DEFAULTS = {
	distance = 10,
}

local REPATH_THRESHOLD = 5

function Follow.new(puppet: any, config: { [string]: any })
	local self = setmetatable({}, Follow)
	self._puppet = puppet

	assert(config.target and typeof(config.target) == "Instance" and config.target:IsA("Model"),
		"[Puppet:Follow] Config must include 'target' (a Model)")

	self._target = config.target
	self._distance = config.distance or DEFAULTS.distance
	self._lastTargetPosition = nil

	self.Movement = nil
	self._destroyConn = nil

	return self
end

function Follow:Init()
	self._destroyConn = self._target.Destroying:Connect(function()
		if self._puppet._destroyed then return end
		self._puppet:ClearAction()
	end)
end

function Follow:Update(dt: number)
	if self._puppet._destroyed then return end
	local target = self._target
	if not target or not target.Parent then
		self._puppet:ClearAction()
		return
	end

	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then return end

	local targetPos = targetRoot.Position
	local selfPos = self._puppet.RootPart.Position
	local distance = (selfPos - targetPos).Magnitude

	if distance <= self._distance then
		if self.Movement:IsMoving() then
			self.Movement:Stop()
		end
		return
	end

	if distance <= self._distance + REPATH_THRESHOLD and not self.Movement:IsMoving() then
		return
	end

	local targetMoved = not self._lastTargetPosition
		or (targetPos - self._lastTargetPosition).Magnitude > REPATH_THRESHOLD
	local needsRepath = targetMoved or not self.Movement:IsMoving()

	if needsRepath then
		local direction = (targetPos - selfPos).Unit
		local goalPos = targetPos - direction * self._distance
		self.Movement:WalkTo(goalPos)
		self._lastTargetPosition = targetPos
	end
end

function Follow:Destroy()
	if self._destroyConn then
		self._destroyConn:Disconnect()
	end
	self.Movement:Stop()
end

return Follow
