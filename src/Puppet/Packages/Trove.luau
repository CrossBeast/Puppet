-- Lightweight cleanup utility for Puppet
-- Tracks objects and cleans them all at once

local Trove = {}
Trove.__index = Trove

function Trove.new()
	local self = setmetatable({}, Trove)
	self._objects = {}
	return self
end

function Trove:Add(object)
	table.insert(self._objects, object)
	return object
end

function Trove:Clean()
	for i = #self._objects, 1, -1 do
		local object = self._objects[i]
		local objectType = typeof(object)

		if objectType == "RBXScriptConnection" then
			object:Disconnect()
		elseif objectType == "Instance" then
			object:Destroy()
		elseif objectType == "function" then
			object()
		elseif objectType == "table" then
			if type(object.Destroy) == "function" then
				object:Destroy()
			elseif type(object.Disconnect) == "function" then
				object:Disconnect()
			end
		end
	end
	table.clear(self._objects)
end

Trove.Destroy = Trove.Clean

return Trove
