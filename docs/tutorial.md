# Tutorial

---

## Getting Started

Download Puppet from [GitHub](https://github.com/CrossBeast/Puppet) or the [Roblox Creator Store](https://create.roblox.com/store/asset/139690896215004/Puppet). Place the `Puppet` module in `ServerScriptService`.

Then require it from any server script:

```lua
local Puppet = require(game.ServerScriptService.Puppet)
```

> Puppet runs on the **server only**. All NPC logic is server-authoritative.

---

## 1. Your first NPC — Patrol

```lua
local Puppet = require(game.ServerScriptService.Puppet)

-- Any Model with a Humanoid + HumanoidRootPart works
local npcModel = workspace.GuardNPC

local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 14 },
    patrol = {
        points = {
            Vector3.new(0, 5, 0),
            Vector3.new(20, 5, 0),
            Vector3.new(20, 5, 20),
            Vector3.new(0, 5, 20),
        },
        waitTime = 1.5,
    },
})
```

The NPC patrols between the given points, waiting 1.5 seconds at each one before moving to the next.

---

## 2. Wander

An NPC that roams randomly around an area:

```lua
local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 10 },
    wander = {
        origin = npcModel.HumanoidRootPart.Position,
        radius = 25,
        waitTime = 2,
    },
})
```

The NPC picks random points within 25 studs of its origin and walks to them. It validates each point with a ground raycast, so it won't walk off edges.

---

## 3. Follow

An NPC that follows another model:

```lua
local target = workspace.SomeOtherNPC

local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 16 },
    follow = {
        target = target,
        distance = 8,
    },
})
```

The NPC maintains ~8 studs from the target. If the target is destroyed, Follow automatically clears itself.

---

## 4. Swapping actions at runtime

Actions are exclusive — setting a new one replaces the old:

```lua
local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 14 },
    idle = {},
})

-- Start patrolling
npc:SetAction("Patrol", {
    points = { pointA, pointB },
    waitTime = 1,
})

-- Switch to follow
npc:SetAction("Follow", {
    target = playerCharacter,
    distance = 5,
})

-- Stop everything
npc:ClearAction()
```

The old action is cleaned up automatically — connections disconnected, movement stopped.

---

## 5. Perception — detecting threats

Add Perception to make the NPC aware of its surroundings:

```lua
local CollectionService = game:GetService("CollectionService")

-- Tag player characters so Perception can find them
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        CollectionService:AddTag(character, "Enemy")
    end)
end)

-- Create an NPC with perception + idle
local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 16 },
    perception = {
        visionRange = 40,
        visionAngle = 160,
        threatTags = { "Enemy" },
    },
    idle = {},
})
```

Perception includes signals for when threats are detected or lost. You decide what to do when they fire:

```lua
local perc = npc:GetComponent("Perception")

perc.ThreatSpotted:Connect(function(target)
    npc:SetAction("Follow", { target = target, distance = 5 })
end)

perc.ThreatLost:Connect(function(target)
    npc:SetAction("Idle")
end)
```

### Tracking vs Detection

Once Perception spots a target, it uses a wider tracking angle (360° by default) to keep detecting them. The target can't escape just by stepping behind the NPC — they need to get out of `visionRange` or break line of sight behind geometry.

You can customize this:

```lua
perception = {
    visionAngle = 120,     -- narrow cone for initial detection
    trackingAngle = 240,   -- wider but not full 360 for tracking
}
```

---

## 6. Changing speed at runtime

Use `SetConfig` on any component to update settings without recreating it:

```lua
local movement = npc:GetComponent("Movement")

-- Slow down (debuff, swamp, etc.)
movement:SetConfig({ walkSpeed = 6 })

-- Speed up
movement:SetConfig({ walkSpeed = 28 })
```

WalkSpeed is applied to the Humanoid immediately, even mid-movement.

You can also change the global tick rate for all Puppets:

```lua
Puppet.setTickRate(60) -- smoother but more CPU
Puppet.setTickRate(15) -- cheaper but less responsive
```

### Movement signals

Movement fires signals you can listen to for custom behavior:

```lua
local movement = npc:GetComponent("Movement")

movement.ReachedDestination:Connect(function()
    print("Arrived!")
end)

movement.Stuck:Connect(function()
    print("Can't reach destination")
end)
```

`ReachedDestination` fires when the NPC arrives at a `WalkTo` target. `Stuck` fires after multiple failed attempts to make progress (jumps + repath).

---

## 7. Reconfigure — changing everything at once

`Reconfigure` replaces the entire component setup in one call. It removes components not in the new config, updates existing ones, adds new ones, and sets a new action. An example use case is NPC bosses with different phases that call for different behaviors:

```lua
local npc = Puppet.new(bossModel, {
    movement = { walkSpeed = 10 },
    perception = { visionRange = 30, visionAngle = 90 },
    patrol = {
        points = { pt1, pt2, pt3, pt4 },
        waitTime = 0.8,
    },
})

-- You can define configs ahead of time
local phase2Config = {
    movement = { walkSpeed = 22 },
    perception = { visionRange = 60, visionAngle = 270 },
    wander = { origin = arenaCenter, radius = 20 },
}

local phase3Config = {
    movement = { walkSpeed = 30 },
    patrol = {
        points = { corner1, corner2, corner3, corner4 },
        waitTime = 0.2,
    },
}

-- Then apply them when needed
task.delay(30, function()
    npc:Reconfigure(phase2Config)
end)

task.delay(60, function()
    npc:Reconfigure(phase3Config)
end)
```

You can also pass the config inline:

```lua
npc:Reconfigure({
    movement = { walkSpeed = 22 },
    wander = { origin = arenaCenter, radius = 20 },
})
```

### AddComponent and RemoveComponent

If you only need to add or remove a single core component without replacing the entire config, use `AddComponent` and `RemoveComponent`:

```lua
-- Add perception to an existing NPC
npc:AddComponent("Perception", { visionRange = 40, threatTags = { "Player" } })

-- Later, remove it
npc:RemoveComponent("Perception")
```

These are useful when you want to modify one part of the NPC without affecting the rest. `Reconfigure` is better when you're changing multiple things at once — like swapping out the action, updating movement speed, and adding/removing components all in one call.

Note: `RemoveComponent` will error if another component or the active action depends on it. Clear the dependent action first:

```lua
-- This would error because Follow requires Movement
npc:RemoveComponent("Movement")

-- Clear the action first, then remove
npc:ClearAction()
npc:RemoveComponent("Movement")
```

---

## 8. Death and respawn

Puppet auto-destroys when the Humanoid dies. The PuppetObject is gone at that point — if you want to respawn the NPC, you need to create a new model and a new Puppet for it:

```lua
local function spawnGuard(position)
    local model = createNPCModel(position) -- your function
    local npc = Puppet.new(model, {
        movement = { walkSpeed = 12 },
        wander = { origin = position, radius = 10 },
    })

    npc.Destroyed:Connect(function()
        -- Clean up the dead body
        if model.Parent then model:Destroy() end

        -- Respawn after 5 seconds with the same config
        task.delay(5, function()
            spawnGuard(position)
        end)
    end)
end

spawnGuard(Vector3.new(0, 5, 0))
```

---

## 9. Listening to lifecycle events

Track what's happening on a Puppet:

```lua
npc.ComponentAdded:Connect(function(name)
    print("Added component:", name)
end)

npc.ComponentRemoved:Connect(function(name)
    print("Removed component:", name)
end)

npc.ActionChanged:Connect(function(previousAction, newAction)
    print("Action:", previousAction, "->", newAction)
end)

npc.Destroyed:Connect(function()
    print("NPC destroyed")
end)
```

---

## 10. Custom components

Puppet is expandable — you can create your own Core and Action components.

A component must have: `Name`, `Type` (`"Core"` or `"Action"`), `new()`, `Init()`, and `Destroy()`. Optionally: `Update(dt)`, `SetConfig(config)`, and `Requires` (a list of dependency names).

### Register from outside

Use `Puppet.registerComponent` when a component is specific to a particular game system or NPC type. The component lives in your game code, not inside the Puppet folder.

This example creates an **Aggro** component — a Core component that tracks how much damage each player has dealt to this NPC. Whoever has dealt the most (minus natural decay over time) is considered the highest threat. Other game code can read this to decide who the NPC should target:

```lua
-- ServerScriptService.MyGame.Aggro

local Signal = require(game.ServerScriptService.Puppet.Packages.Signal)

local Aggro = {}
Aggro.__index = Aggro

Aggro.Name = "Aggro"
Aggro.Type = "Core"

function Aggro.new(puppet, config)
    local self = setmetatable({}, Aggro)
    self._puppet = puppet
    self._threats = {} -- [player] = aggroValue
    self._decayRate = config.decayRate or 5

    self.HighestThreatChanged = Signal.new()
    return self
end

function Aggro:Init() end

function Aggro:Update(dt)
    for player, value in self._threats do
        self._threats[player] = math.max(0, value - self._decayRate * dt)
        if self._threats[player] == 0 then
            self._threats[player] = nil
        end
    end
end

function Aggro:AddAggro(player, amount)
    self._threats[player] = (self._threats[player] or 0) + amount
    self.HighestThreatChanged:Fire(self:GetHighestThreat())
end

function Aggro:GetHighestThreat()
    local highest, target = 0, nil
    for player, value in self._threats do
        if value > highest then
            highest = value
            target = player
        end
    end
    return target
end

function Aggro:Destroy()
    self.HighestThreatChanged:Destroy()
end

return Aggro
```

Register it in your game script before creating Puppets that use it:

```lua
local Puppet = require(game.ServerScriptService.Puppet)
local Aggro = require(game.ServerScriptService.MyGame.Aggro)

Puppet.registerComponent("Aggro", Aggro)

local boss = Puppet.new(bossModel, {
    movement = { walkSpeed = 16 },
    aggro = { decayRate = 3 },
    patrol = { points = { ptA, ptB }, waitTime = 1 },
})

-- When a player deals damage, add aggro
local aggro = boss:GetComponent("Aggro")
aggro:AddAggro(player, 25)

-- Chase whoever has the most aggro
aggro.HighestThreatChanged:Connect(function(target)
    if target and target.Character then
        boss:SetAction("Follow", { target = target.Character, distance = 5 })
    end
end)
```

### Drop-in: add to the Components folder

For components generic enough to be reusable across projects, drop a ModuleScript directly into `Puppet/Components/Core/` or `Puppet/Components/Action/`. Puppet auto-discovers it on startup — no registration needed.

This example creates a **Flee** action — the opposite of Follow. The NPC runs away from a threat until it reaches a safe distance, then clears its action. It requires Movement to move the NPC:

```lua
-- ServerScriptService.Puppet.Components.Action.Flee

local Packages = script.Parent.Parent.Parent.Packages

local Flee = {}
Flee.__index = Flee

Flee.Name = "Flee"
Flee.Type = "Action"
Flee.Requires = { "Movement" }

function Flee.new(puppet, config)
    local self = setmetatable({}, Flee)
    self._puppet = puppet
    self._threat = config.threat
    self._fleeDistance = config.fleeDistance or 50
    self.Movement = nil -- injected via Requires
    return self
end

function Flee:Init()
    self:_runAway()
end

function Flee:Update(dt)
    if not self._threat or not self._threat.Parent then
        self._puppet:ClearAction()
        return
    end

    local threatRoot = self._threat:FindFirstChild("HumanoidRootPart")
    if not threatRoot then return end

    local distance = (self._puppet.RootPart.Position - threatRoot.Position).Magnitude

    if distance >= self._fleeDistance then
        self._puppet:ClearAction()
        return
    end

    if not self.Movement:IsMoving() then
        self:_runAway()
    end
end

function Flee:_runAway()
    local threatRoot = self._threat:FindFirstChild("HumanoidRootPart")
    if not threatRoot then return end

    local awayDir = (self._puppet.RootPart.Position - threatRoot.Position).Unit
    local fleeTarget = self._puppet.RootPart.Position + awayDir * 30
    self.Movement:WalkTo(fleeTarget)
end

function Flee:Destroy()
    self.Movement:Stop()
end

return Flee
```

Because it's inside the `Components` folder, you can use it immediately without registering:

```lua
npc:SetAction("Flee", { threat = enemyModel, fleeDistance = 50 })
```

Both approaches produce the same result — the component works identically either way. Use `registerComponent` to keep game-specific code separate from the framework. Use the drop-in folder for components generic enough to ship with Puppet.

---

## 11. Optimization and replication

### Puppet's overhead

Puppet itself is lightweight. All NPCs share a single `RunService.Heartbeat` connection at 30hz. Components state are just Lua tables. Signals are cheap. The framework adds almost nothing on top of what Roblox already costs per NPC.

The real bottleneck is Roblox's automatic replication. Every Humanoid model in Workspace is replicated to every client — position, rotation, animations, every property change. At 50+ NPCs this becomes expensive in both bandwidth and client framerate.

### Using a replication module

Puppet works alongside custom replication without any changes. The most straightforward option is [Chrono](https://parihsz.github.io/Chrono/), a drop-in replication library that replaces Roblox's default physics replication with efficient custom replication:

```lua
local Puppet = require(game.ServerScriptService.Puppet)
local Chrono = require(path.to.Chrono)

local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 16 },
    patrol = { points = { ptA, ptB, ptC }, waitTime = 1 },
})

-- Chrono takes over replication for this model
Chrono:AddEntity(npcModel)
```

Puppet moves the Humanoid on the server like normal. Chrono handles delivering position, rotation, and animation data to clients efficiently. Nothing in Puppet needs to change.

For small NPC counts (under ~50), you don't need any of this — Roblox's default replication works fine.

### Building your own replication

If you prefer to build custom replication instead of using a dedicated module, Puppet doesn't get in the way. Position and rotation are always available directly from the Model:

```lua
local position = puppet.RootPart.Position
local lookDirection = puppet.RootPart.CFrame.LookVector
```

For custom component data that you want on the client (like aggro values or combat state), a recommended pattern is to have components define a `GetReplicatedState` method. Components that define it opt in — components that don't are skipped:

```lua
-- In your custom component
function Aggro:GetReplicatedState()
    return {
        highestThreat = self:GetHighestThreat(),
        threatCount = self:GetThreatCount(),
    }
end
```

Then collect everything in your replication loop:

```lua
local function collectNpcState(puppet)
    local state = {
        position = puppet.RootPart.Position,
        rotation = puppet.RootPart.CFrame.LookVector,
    }

    for name, component in puppet._components do
        if component.GetReplicatedState then
            state[name] = component:GetReplicatedState()
        end
    end

    if puppet._action and puppet._action.GetReplicatedState then
        state[puppet._action.Name] = puppet._action:GetReplicatedState()
    end

    return state
end
```

This isn't built into Puppet — it's a pattern. The collection logic lives in your game code, and you choose how and when to send it to clients.
