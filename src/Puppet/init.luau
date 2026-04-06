--[[ A composition-based NPC framework (CrossBeast) ]] --

--[[
	Entry point for Puppet
	- Auto registers built-in components
	- Exposes public API
]]

local PuppetObject = require(script.PuppetObject)
local PuppetUpdater = require(script.PuppetUpdater)
local ComponentRegistry = require(script.ComponentRegistry)
local Types = require(script.Types)

for _, module in script.Components:GetDescendants() do
	if module:IsA("ModuleScript") then
		local componentClass = require(module)
		ComponentRegistry._registerBuiltIn(componentClass.Name, componentClass)
	end
end

export type PuppetObject = Types.PuppetObject
export type Movement = Types.Movement
export type Perception = Types.Perception

local Puppet = {}

function Puppet.new(model: Model, config: { [string]: any }?): PuppetObject
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
