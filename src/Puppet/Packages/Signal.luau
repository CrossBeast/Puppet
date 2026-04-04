-- Lightweight Signal implementation for Puppet
-- Supports Connect, Once, Fire, Destroy

local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._handlers = {}
	self._destroyed = false
	return self
end

function Signal:Connect(handler)
	assert(not self._destroyed, "[Signal] Cannot connect to a destroyed Signal")
	assert(type(handler) == "function", "[Signal] Handler must be a function")

	local connection = {
		_handler = handler,
		_signal = self,
		Connected = true,
	}

	function connection.Disconnect(conn)
		if not conn.Connected then return end
		conn.Connected = false
		local handlers = conn._signal._handlers
		local idx = table.find(handlers, conn)
		if idx then
			table.remove(handlers, idx)
		end
	end

	table.insert(self._handlers, connection)
	return connection
end

function Signal:Once(handler)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...)
	if self._destroyed then return end
	for i = #self._handlers, 1, -1 do
		local conn = self._handlers[i]
		if conn.Connected then
			task.spawn(conn._handler, ...)
		end
	end
end

function Signal:Destroy()
	self._destroyed = true
	for _, conn in self._handlers do
		conn.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
