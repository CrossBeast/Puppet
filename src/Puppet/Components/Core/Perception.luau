--[[
	Perception (Core)
	- Vision cone, configurable angle and range
	- Wider tracking for already-spotted targets
	- Signals: ThreatSpotted, ThreatLost
]]

local CollectionService = game:GetService("CollectionService")
local Signal = require(script.Parent.Parent.Parent.Packages.Signal)

local Perception = {}
Perception.__index = Perception

Perception.Name = "Perception"
Perception.Type = "Core"

local DEFAULTS = {
	visionRange = 60,
	visionAngle = 120,
	hearingRange = 40,
	perceptionInterval = 0.2,
	threatTags = { "Player" },
	maxChecks = 10,
	trackingAngle = 360,
}

function Perception.new(puppet: any, config: { [string]: any })
	local self = setmetatable({}, Perception)
	self._puppet = puppet

	self._visionRange = config.visionRange or DEFAULTS.visionRange
	self._visionAngle = config.visionAngle or DEFAULTS.visionAngle
	self._hearingRange = config.hearingRange or DEFAULTS.hearingRange
	self._perceptionInterval = config.perceptionInterval or DEFAULTS.perceptionInterval
	self._threatTags = config.threatTags or table.clone(DEFAULTS.threatTags)
	self._maxChecks = config.maxChecks or DEFAULTS.maxChecks
	self._trackingAngle = config.trackingAngle or DEFAULTS.trackingAngle

	self._lastCheck = tick() - (math.random() * self._perceptionInterval)
	self._visibleThreats = {}
	self._previousThreats = {}

	self.ThreatSpotted = Signal.new()
	self.ThreatLost = Signal.new()

	return self
end

function Perception:Init() end

function Perception:Update(dt: number)
	local now = tick()
	if now - self._lastCheck < self._perceptionInterval then return end
	self._lastCheck = now

	local candidates = self:_getCandidates()

	local previousSet = {}
	for _, threat in self._previousThreats do
		previousSet[threat] = true
	end

	local currentThreats = {}
	local checked = 0
	for _, candidate in candidates do
		if checked >= self._maxChecks then break end
		checked += 1
		local isTracked = previousSet[candidate]
		if self:CanSee(candidate, isTracked and self._trackingAngle or nil) then
			table.insert(currentThreats, candidate)
		end
	end

	local currentSet = {}
	for _, threat in currentThreats do
		currentSet[threat] = true
		if not previousSet[threat] then
			self.ThreatSpotted:Fire(threat)
		end
	end

	for _, threat in self._previousThreats do
		if not currentSet[threat] then
			self.ThreatLost:Fire(threat)
		end
	end

	self._visibleThreats = currentThreats
	self._previousThreats = currentThreats
end

function Perception:CanSee(target: Model, overrideAngle: number?): boolean
	if self._puppet._destroyed then return false end

	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not targetRoot or not targetRoot:IsA("BasePart") then return false end

	local selfPos = self._puppet.RootPart.Position
	local toTarget = targetRoot.Position - selfPos
	local distance = toTarget.Magnitude

	if distance > self._visionRange then return false end
	if distance < 1e-3 then return true end

	local forward = self._puppet.RootPart.CFrame.LookVector
	local direction = toTarget.Unit
	local dot = forward:Dot(direction)
	local halfAngle = math.rad((overrideAngle or self._visionAngle) / 2)
	if dot < math.cos(halfAngle) then return false end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { self._puppet.Model, target }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(selfPos, toTarget, rayParams)
	return result == nil
end

function Perception:CanHear(position: Vector3): boolean
	if self._puppet._destroyed then return false end
	if typeof(position) ~= "Vector3" then return false end
	return (self._puppet.RootPart.Position - position).Magnitude <= self._hearingRange
end

function Perception:GetVisibleThreats(): { Model }
	return self._visibleThreats
end

function Perception:SetConfig(config: { [string]: any })
	if config.visionRange ~= nil then self._visionRange = config.visionRange end
	if config.visionAngle ~= nil then self._visionAngle = config.visionAngle end
	if config.hearingRange ~= nil then self._hearingRange = config.hearingRange end
	if config.perceptionInterval ~= nil then self._perceptionInterval = config.perceptionInterval end
	if config.threatTags ~= nil then self._threatTags = config.threatTags end
	if config.maxChecks ~= nil then self._maxChecks = config.maxChecks end
	if config.trackingAngle ~= nil then self._trackingAngle = config.trackingAngle end
end

function Perception:Destroy()
	table.clear(self._visibleThreats)
	table.clear(self._previousThreats)
	self.ThreatSpotted:Destroy()
	self.ThreatLost:Destroy()
end

function Perception:_getCandidates()
	local candidates = {}
	for _, tag in self._threatTags do
		for _, tagged in CollectionService:GetTagged(tag) do
			if tagged:IsA("Model") and tagged ~= self._puppet.Model then
				local humanoid = tagged:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					table.insert(candidates, tagged)
				end
			end
		end
	end
	return candidates
end

return Perception
