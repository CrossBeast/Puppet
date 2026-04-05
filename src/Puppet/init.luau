-- Puppet — Composition-Based NPC System
-- Entry point. Auto-discovers built-in components and exposes public API.

local PuppetObject = require(script.PuppetObject)
local PuppetUpdater = require(script.PuppetUpdater)
local ComponentRegistry = require(script.ComponentRegistry)

-- Auto-discover and register all built-in components
for _, module in script.Components:GetDescendants() do
	if module:IsA("ModuleScript") then
		local componentClass = require(module)
		ComponentRegistry._registerBuiltIn(componentClass.Name, componentClass)
	end
end

local Puppet = {}

function Puppet.new(model: Model, config: { [string]: any }?): any
	return PuppetObject.new(model, config)
end

function Puppet.registerComponent(name: string, componentClass: { [string]: any })
	ComponentRegistry.register(name, componentClass)
end

function Puppet.setTickRate(hz: number)
	PuppetUpdater.setTickRate(hz)
end

function Puppet.getTickRate(): number
	return PuppetUpdater.getTickRate()
end

return Puppet

