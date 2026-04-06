--[[
	Component registry
	- Registration, validation and lookup
	- Built-ins from init, customs from registerComponent
	- Case-insensitive config keys
]]

local ComponentRegistry = {}

local builtInComponents = {}
local customComponents = {}
local configKeyMap = {}

local builtInNames = {}

local function validateComponentClass(name, componentClass)
	assert(type(name) == "string" and #name > 0,
		"[Puppet] Component name must be a non-empty string")
	assert(type(componentClass) == "table",
		string.format("[Puppet] Component '%s' class must be a table", name))
	assert(componentClass.Name == name,
		string.format("[Puppet] Component Name '%s' must match registration name '%s'",
			tostring(componentClass.Name), name))
	assert(componentClass.Type == "Core" or componentClass.Type == "Action",
		string.format("[Puppet] Component '%s' Type must be 'Core' or 'Action', got '%s'",
			name, tostring(componentClass.Type)))
	assert(type(componentClass.new) == "function",
		string.format("[Puppet] Component '%s' must have a new() constructor", name))
	assert(type(componentClass.Init) == "function",
		string.format("[Puppet] Component '%s' must have an Init() method", name))
	assert(type(componentClass.Destroy) == "function",
		string.format("[Puppet] Component '%s' must have a Destroy() method", name))

	if componentClass.Requires then
		assert(type(componentClass.Requires) == "table",
			string.format("[Puppet] Component '%s' Requires must be a table", name)
		)
		for _, req in componentClass.Requires do
			assert(type(req) == "string",
				string.format("[Puppet] Component '%s' Requires entries must be strings", name)
			)
		end
	end
end

function ComponentRegistry._registerBuiltIn(name: string, componentClass: { [string]: any })
	validateComponentClass(name, componentClass)
	builtInComponents[name] = componentClass
	builtInNames[name] = true
	configKeyMap[string.lower(name)] = name
end

function ComponentRegistry.register(name: string, componentClass: { [string]: any })
	validateComponentClass(name, componentClass)

	if builtInNames[name] or builtInNames[configKeyMap[string.lower(name)]] then
		error(string.format("[Puppet] Cannot override built-in component '%s'", name))
	end

	if customComponents[name] then
		error(string.format("[Puppet] Component '%s' is already registered", name))
	end

	customComponents[name] = componentClass
	configKeyMap[string.lower(name)] = name
end

function ComponentRegistry.get(name: string): { [string]: any }?
	return builtInComponents[name] or customComponents[name]
end

function ComponentRegistry.resolveConfigKey(lowercaseKey: string): string?
	return configKeyMap[lowercaseKey]
end

return ComponentRegistry
