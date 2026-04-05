local Idle = {}
Idle.__index = Idle
Idle.Name = "Idle"
Idle.Type = "Action"

function Idle.new(puppet: any, config: { [string]: any })
	return setmetatable({ _puppet = puppet }, Idle)
end

function Idle:Init() end
function Idle:Destroy() end

return Idle
