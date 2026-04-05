-- The Puppet class. Container for components, manages lifecycle.

local HttpService = game:GetService("HttpService")

local Signal = require(script.Parent.Packages.Signal)
local Trove = require(script.Parent.Packages.Trove)
local ComponentRegistry = require(script.Parent.ComponentRegistry)
local PuppetUpdater = require(script.Parent.PuppetUpdater)

local PuppetObject = {}
PuppetObject.__index = PuppetObject

local activePuppets = {}

function PuppetObject.new(model: Model, config: { [string]: any }?)
	assert(typeof(model) == "Instance" and model:IsA("Model"),
		"[Puppet] First argument must be a Model")
	assert(not activePuppets[model],
		"[Puppet] A Puppet already exists for this Model. Destroy it first.")

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid,
		"[Puppet] Model must have a Humanoid: " .. model:GetFullName())

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	assert(rootPart and rootPart:IsA("BasePart"),
		"[Puppet] Model must have a HumanoidRootPart: " .. model:GetFullName())

	local self = setmetatable({}, PuppetObject)
	self._id = HttpService:GenerateGUID(false)
	self._destroyed = false
	self._trove = Trove.new()
	self._components = {}
	self._action = nil
	self._deferredChanges = {}
	self._updating = false

	self.Model = model
	self.Humanoid = humanoid
	self.RootPart = rootPart

	self.ComponentAdded = Signal.new()
	self.ComponentRemoved = Signal.new()
	self.ActionChanged = Signal.new()
	self.Destroyed = Signal.new()

	-- Auto-cleanup on model destruction
	self._trove:Add(model.Destroying:Connect(function()
		self:Destroy()
	end))

	-- Auto-cleanup on humanoid death (Died + HealthChanged fallback)
	self._trove:Add(humanoid.Died:Connect(function()
		self:Destroy()
	end))
	self._trove:Add(humanoid.HealthChanged:Connect(function(newHealth)
		if newHealth <= 0 then
			self:Destroy()
		end
	end))

	activePuppets[model] = self
	PuppetUpdater.register(self)

	if config then
		self:_processConfig(config)
	end

	return self
end

function PuppetObject:_processConfig(config)
	local coreEntries = {}
	local actionName = nil
	local actionConfig = nil

	for key, value in config do
		local componentName = ComponentRegistry.resolveConfigKey(key)
		if not componentName then
			warn(string.format("[Puppet] Unknown config key '%s'", key))
			continue
		end

		local componentClass = ComponentRegistry.get(componentName)
		if not componentClass then
			warn(string.format("[Puppet] Component '%s' is not registered", componentName))
			continue
		end

		if componentClass.Type == "Core" then
			table.insert(coreEntries, {
				name = componentName,
				class = componentClass,
				config = value,
			})
		elseif componentClass.Type == "Action" then
			if actionName then
				warn(string.format(
					"[Puppet] Multiple actions in config: '%s' and '%s'. Using '%s'.",
					actionName, componentName, componentName))
			end
			actionName = componentName
			actionConfig = value
		end
	end

	self:_createCoresInOrder(coreEntries)

	if actionName then
		self:SetAction(actionName, actionConfig)
	end
end

function PuppetObject:_createCoresInOrder(coreEntries)
	local created = {}
	local remaining = table.clone(coreEntries)
	local maxIterations = #remaining + 1
	local iteration = 0

	while #remaining > 0 do
		iteration += 1
		if iteration > maxIterations then
			local names = {}
			for _, entry in remaining do
				table.insert(names, entry.name)
			end
			error(string.format(
				"[Puppet] Circular dependency among core components: %s",
				table.concat(names, ", ")))
		end

		local madeProgress = false
		local stillRemaining = {}

		for _, entry in remaining do
			local requires = entry.class.Requires or {}
			local satisfied = true

			for _, req in requires do
				if not created[req] then
					satisfied = false
					break
				end
			end

			if satisfied then
				self:_addComponentInternal(entry.name, entry.class, entry.config)
				created[entry.name] = true
				madeProgress = true
			else
				table.insert(stillRemaining, entry)
			end
		end

		if not madeProgress then
			local names = {}
			for _, entry in stillRemaining do
				table.insert(names, entry.name)
			end
			error(string.format(
				"[Puppet] Cannot resolve dependencies for: %s",
				table.concat(names, ", ")))
		end

		remaining = stillRemaining
	end
end

function PuppetObject:_addComponentInternal(name, componentClass, config)
	local component = componentClass.new(self, config or {})

	local requires = componentClass.Requires or {}
	for _, reqName in requires do
		local dep = self._components[reqName]
		if not dep then
			error(string.format(
				'[Puppet] "%s" requires "%s", but it hasn\'t been added.',
				name, reqName))
		end
		component[reqName] = dep
	end

	self._components[name] = component
	component:Init()
	self.ComponentAdded:Fire(name)
end

function PuppetObject:AddComponent(name: string, config: { [string]: any }?)
	if self._destroyed then
		warn("[Puppet] Cannot AddComponent on a destroyed Puppet")
		return
	end

	local componentClass = ComponentRegistry.get(name)
	if not componentClass then
		error(string.format("[Puppet] Component '%s' is not registered", name))
	end

	if componentClass.Type == "Action" then
		warn(string.format('[Puppet] "%s" is an Action. Use SetAction() instead.', name))
		return
	end

	if self._components[name] then
		warn(string.format('[Puppet] "%s" is already added.', name))
		return
	end

	if self._updating then
		table.insert(self._deferredChanges, { type = "addComponent", name = name, config = config })
		return
	end

	self:_addComponentInternal(name, componentClass, config)
end

function PuppetObject:RemoveComponent(name: string)
	if self._destroyed then
		warn("[Puppet] Cannot RemoveComponent on a destroyed Puppet")
		return
	end

	local component = self._components[name]
	if not component then
		warn(string.format('[Puppet] Component "%s" is not on this Puppet', name))
		return
	end

	if self._action then
		local actionRequires = self._action.Requires or {}
		for _, req in actionRequires do
			if req == name then
				error(string.format(
					'[Puppet] Cannot remove "%s" -- required by action "%s". Remove the action first.',
					name, self._action.Name))
			end
		end
	end

	for otherName, otherComponent in self._components do
		if otherName ~= name then
			local otherRequires = otherComponent.Requires or {}
			for _, req in otherRequires do
				if req == name then
					error(string.format(
						'[Puppet] Cannot remove "%s" -- required by "%s". Remove "%s" first.',
						name, otherName, otherName))
				end
			end
		end
	end

	if self._updating then
		table.insert(self._deferredChanges, { type = "removeComponent", name = name })
		return
	end

	component:Destroy()
	self._components[name] = nil
	self.ComponentRemoved:Fire(name)
end

function PuppetObject:GetComponent(name: string): any?
	return self._components[name]
end

function PuppetObject:HasComponent(name: string): boolean
	return self._components[name] ~= nil
end

function PuppetObject:SetAction(name: string, config: { [string]: any }?)
	if self._destroyed then
		warn("[Puppet] Cannot SetAction on a destroyed Puppet")
		return
	end

	local componentClass = ComponentRegistry.get(name)
	if not componentClass then
		error(string.format("[Puppet] Action '%s' is not registered", name))
	end

	if componentClass.Type ~= "Action" then
		warn(string.format('[Puppet] "%s" is a Core component. Use AddComponent() instead.', name))
		return
	end

	if self._updating then
		table.insert(self._deferredChanges, { type = "setAction", name = name, config = config })
		return
	end

	local previousName = self._action and self._action.Name or nil

	if self._action then
		self._action:Destroy()
		self._action = nil
	end

	local component = componentClass.new(self, config or {})

	local requires = componentClass.Requires or {}
	for _, reqName in requires do
		local dep = self._components[reqName]
		if not dep then
			error(string.format(
				'[Puppet] "%s" requires "%s", but it hasn\'t been added.',
				name, reqName))
		end
		component[reqName] = dep
	end

	self._action = component
	component:Init()
	self.ActionChanged:Fire(previousName, name)
end

function PuppetObject:GetAction(): any?
	return self._action
end

function PuppetObject:ClearAction()
	if self._destroyed then return end

	if self._updating then
		table.insert(self._deferredChanges, { type = "clearAction" })
		return
	end

	local previousName = self._action and self._action.Name or nil

	if self._action then
		self._action:Destroy()
		self._action = nil
	end

	if previousName then
		self.ActionChanged:Fire(previousName, nil)
	end
end

function PuppetObject:Reconfigure(config: { [string]: any })
	if self._destroyed then
		warn("[Puppet] Cannot Reconfigure a destroyed Puppet")
		return
	end

	local newCores = {}
	local newActionName = nil
	local newActionConfig = nil

	for key, value in config do
		local componentName = ComponentRegistry.resolveConfigKey(key)
		if not componentName then
			warn(string.format("[Puppet] Unknown config key '%s'", key))
			continue
		end

		local componentClass = ComponentRegistry.get(componentName)
		if not componentClass then continue end

		if componentClass.Type == "Core" then
			newCores[componentName] = value
		elseif componentClass.Type == "Action" then
			newActionName = componentName
			newActionConfig = value
		end
	end

	-- Reconfigure bypasses deferral — it applies changes directly
	-- regardless of whether we're mid-update.
	local wasUpdating = self._updating
	self._updating = false

	-- Clear current action directly
	local previousActionName = self._action and self._action.Name or nil
	if self._action then
		self._action:Destroy()
		self._action = nil
	end
	if previousActionName then
		self.ActionChanged:Fire(previousActionName, nil)
	end

	-- Remove cores not in new config
	local toRemove = {}
	for name in self._components do
		if not newCores[name] then
			table.insert(toRemove, name)
		end
	end
	for _, name in toRemove do
		if self._components[name] then
			self._components[name]:Destroy()
			self._components[name] = nil
			self.ComponentRemoved:Fire(name)
		end
	end

	-- Update existing cores
	for name, newConfig in newCores do
		local existing = self._components[name]
		if existing and existing.SetConfig then
			existing:SetConfig(newConfig)
		end
	end

	-- Add new cores in dependency order
	local coreEntries = {}
	for name, coreConfig in newCores do
		if not self._components[name] then
			local componentClass = ComponentRegistry.get(name)
			if componentClass then
				table.insert(coreEntries, {
					name = name,
					class = componentClass,
					config = coreConfig,
				})
			end
		end
	end
	if #coreEntries > 0 then
		self:_createCoresInOrder(coreEntries)
	end

	-- Set new action
	if newActionName then
		self:SetAction(newActionName, newActionConfig)
	end

	-- Restore updating state
	self._updating = wasUpdating
end

function PuppetObject:_applyDeferred()
	if self._destroyed or #self._deferredChanges == 0 then return end

	local changes = self._deferredChanges
	self._deferredChanges = {}

	for _, change in changes do
		if change.type == "addComponent" then
			self:AddComponent(change.name, change.config)
		elseif change.type == "removeComponent" then
			self:RemoveComponent(change.name)
		elseif change.type == "setAction" then
			self:SetAction(change.name, change.config)
		elseif change.type == "clearAction" then
			self:ClearAction()
		end
	end
end

function PuppetObject:Destroy()
	if self._destroyed then return end
	self._destroyed = true

	if self._action then
		self._action:Destroy()
		self._action = nil
	end

	for _, component in self._components do
		component:Destroy()
	end
	table.clear(self._components)

	PuppetUpdater.unregister(self)
	if self.Model then
		activePuppets[self.Model] = nil
	end

	self.Destroyed:Fire()

	self._trove:Clean()
	self.ComponentAdded:Destroy()
	self.ComponentRemoved:Destroy()
	self.ActionChanged:Destroy()
	self.Destroyed:Destroy()

	self.Model = nil
	self.Humanoid = nil
	self.RootPart = nil
end

return PuppetObject
