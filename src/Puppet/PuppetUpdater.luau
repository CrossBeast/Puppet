-- Centralized update loop for all Puppet instances.
-- Single RunService.Heartbeat connection, fixed tick rate.
-- Internal module — developers never interact with this directly.

local RunService = game:GetService("RunService")

local PuppetUpdater = {}

local puppets = {}
local tickRate = 1 / 30
local accumulator = 0
local MAX_SUBSTEPS = 3

function PuppetUpdater.register(puppet)
	puppets[puppet._id] = puppet
end

function PuppetUpdater.unregister(puppet)
	puppets[puppet._id] = nil
end

function PuppetUpdater.setTickRate(hz: number)
	assert(type(hz) == "number" and hz > 0, "[Puppet] Tick rate must be a positive number")
	tickRate = 1 / hz
end

function PuppetUpdater.getTickRate(): number
	return math.round(1 / tickRate)
end

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt

	local substeps = 0
	while accumulator >= tickRate and substeps < MAX_SUBSTEPS do
		accumulator -= tickRate
		substeps += 1

		for id, puppet in puppets do
			if puppet._destroyed then
				puppets[id] = nil
				continue
			end

			-- Auto-destroy if critical parts are missing
			local model = puppet.Model
			local humanoid = puppet.Humanoid
			local rootPart = puppet.RootPart
			if not model or not model.Parent
				or not humanoid or not humanoid.Parent
				or not rootPart or not rootPart.Parent then
				puppet:Destroy()
				puppets[id] = nil
				continue
			end

			puppet._updating = true

			-- Update core components
			for _, component in puppet._components do
				if component.Update then
					local ok, err = pcall(component.Update, component, tickRate)
					if not ok then
						warn(string.format("[Puppet] %s:Update() error on '%s': %s",
							component.Name, puppet.Model.Name, tostring(err)))
					end
				end
			end

			-- Update active action
			local action = puppet._action
			if action and action.Update then
				local ok, err = pcall(action.Update, action, tickRate)
				if not ok then
					warn(string.format("[Puppet] %s:Update() error on '%s': %s",
						action.Name, puppet.Model.Name, tostring(err)))
				end
			end

			puppet._updating = false
			puppet:_applyDeferred()
		end
	end

	if accumulator > tickRate then
		accumulator = tickRate
	end
end)

return PuppetUpdater
