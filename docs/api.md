# API Reference

---

## Puppet (Module)

The entry point. Require this to create NPCs and register custom components.

```lua
local Puppet = require(path.to.Puppet)
```

---

### Puppet.new

```
Puppet.new(model, config?) --> PuppetObject
```

Creates a new Puppet for the given Model.

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | `Model` | Must have a `Humanoid` and `HumanoidRootPart`. |
| `config` | `{ [string]: any }?` | Optional. Component configs keyed by lowercase name. |

```lua
local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 16 },
    perception = { visionRange = 40, threatTags = { "Player" } },
    patrol = { points = { pt1, pt2, pt3 }, waitTime = 1 },
})
```

Config keys are **case-insensitive** (`movement`, `Movement`, and `MOVEMENT` all work).

Core components are created first (in dependency order), then the action is set. Only one action can be specified in the config — if multiple are given, the last one wins with a warning.

The Puppet auto-destroys when:
- The Model is destroyed
- The Humanoid dies (Health reaches 0)
- The HumanoidRootPart is removed

---

### Puppet.registerComponent

```
Puppet.registerComponent(name, componentClass)
```

Registers a custom component. Cannot override built-in components.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Must match `componentClass.Name`. |
| `componentClass` | `table` | Must have `Name`, `Type`, `new`, `Init`, `Destroy`. |

See [Custom Components](#custom-components) in the tutorial for the full interface.

---

### Puppet.setTickRate

```
Puppet.setTickRate(hz)
```

Changes the update rate for all Puppets. Default and recommended is **30hz** — this means every component's `Update` method is called 30 times per second.

| Parameter | Type | Description |
|-----------|------|-------------|
| `hz` | `number` | Updates per second. Must be > 0. |

Higher values (e.g. 60hz) make NPC reactions snappier and movement smoother, but cost more CPU since every component updates more frequently. Lower values (e.g. 10hz) are cheaper on performance but NPCs will feel less responsive — perception scans less often, stuck detection reacts slower, and actions update less frequently. 30hz is a good balance between responsiveness and performance for most games.

---

### Puppet.getTickRate

```
Puppet.getTickRate() --> number
```

Returns the current tick rate in hz.

---

## PuppetObject

Returned by `Puppet.new()`. Manages components and lifecycle for a single NPC.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `.Model` | `Model` | The NPC's model. Read-only. `nil` after destroy. |
| `.Humanoid` | `Humanoid` | The NPC's humanoid. Read-only. `nil` after destroy. |
| `.RootPart` | `BasePart` | The HumanoidRootPart. Read-only. `nil` after destroy. |

### Signals

| Signal | Parameters | Description |
|--------|-----------|-------------|
| `.ComponentAdded` | `(name: string)` | Fires when a core component is added. |
| `.ComponentRemoved` | `(name: string)` | Fires when a core component is removed. |
| `.ActionChanged` | `(previousName: string?, newName: string?)` | Fires when the action changes. |
| `.Destroyed` | `()` | Fires when the Puppet is destroyed. |

---

### PuppetObject:AddComponent

```
PuppetObject:AddComponent(name, config?)
```

Adds a core component. Errors if the component is an Action (use `SetAction` instead).

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Registered component name (e.g. `"Perception"`). |
| `config` | `{ [string]: any }?` | Config passed to the component constructor. |

---

### PuppetObject:RemoveComponent

```
PuppetObject:RemoveComponent(name)
```

Removes a core component. Errors if another component or the active action depends on it.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Component to remove. |

---

### PuppetObject:GetComponent

```
PuppetObject:GetComponent(name) --> component?
```

Returns the component instance, or `nil` if not present.

```lua
local movement = npc:GetComponent("Movement")
movement:WalkTo(targetPosition)
```

---

### PuppetObject:HasComponent

```
PuppetObject:HasComponent(name) --> boolean
```

Returns `true` if the component is on this Puppet.

---

### PuppetObject:SetAction

```
PuppetObject:SetAction(name, config?)
```

Sets the active action. Automatically destroys the previous action. Errors if the component is a Core type.

| Parameter | Type | Description |
|-----------|------|-------------|
| `name` | `string` | Action name (e.g. `"Patrol"`, `"Follow"`). |
| `config` | `{ [string]: any }?` | Config for the action. |

```lua
npc:SetAction("Follow", { target = enemyModel, distance = 5 })
```

---

### PuppetObject:GetAction

```
PuppetObject:GetAction() --> action?
```

Returns the current action instance, or `nil`.

---

### PuppetObject:ClearAction

```
PuppetObject:ClearAction()
```

Removes the current action without setting a new one. The NPC will have no active action until `SetAction` is called again.

---

### PuppetObject:Reconfigure

```
PuppetObject:Reconfigure(config)
```

Replaces the entire component setup in one call. Removes components not in the new config, updates existing ones via `SetConfig`, adds new ones, and sets a new action.

| Parameter | Type | Description |
|-----------|------|-------------|
| `config` | `{ [string]: any }` | Same format as `Puppet.new` config. |

```lua
npc:Reconfigure({
    movement = { walkSpeed = 22 },
    perception = { visionRange = 60, visionAngle = 270 },
    wander = { origin = bossArena, radius = 20 },
})
```

This is safe to call during updates — it bypasses the deferral mechanism.

---

### PuppetObject:Destroy

```
PuppetObject:Destroy()
```

Destroys the Puppet. Cleans up all components, disconnects all internal connections, fires the `Destroyed` signal. Calling `Destroy` multiple times is safe (no-op after the first).

> **Note:** This does NOT destroy the Model. If you want to remove the NPC from the workspace, destroy the Model separately — or destroy the Model first and the Puppet will auto-cleanup.

---

## Built-in Components

### Movement

**Type:** Core

Handles pathfinding, direct movement, stuck detection, and walk speed.

#### Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `walkSpeed` | `number` | `12` | Humanoid WalkSpeed. Applied immediately. |
| `runSpeed` | `number` | `24` | Stored for developer use. Not auto-applied. |
| `arrivalRadius` | `number` | `4` | How close counts as "arrived" at a waypoint. |

#### Methods

**`:WalkTo(position) --> boolean`**

Moves the NPC to the target position. Returns `true` if movement started, `false` on failure. Uses direct movement for short/clear paths, pathfinding for longer or obstructed ones.

```lua
local movement = npc:GetComponent("Movement")
local success = movement:WalkTo(Vector3.new(50, 5, 30))
```

**`:Stop()`**

Stops all movement immediately. Does not modify WalkSpeed.

**`:IsMoving() --> boolean`**

Returns `true` if the NPC is actively moving to a destination.

**`:IsStuck() --> boolean`**

Returns `true` if the NPC hasn't made progress for 2+ seconds.

**`:SetConfig(config)`**

Updates movement settings at runtime. WalkSpeed is applied to the Humanoid immediately.

```lua
movement:SetConfig({ walkSpeed = 28 })
```

#### Signals

| Signal | Description |
|--------|-------------|
| `.ReachedDestination` | Fires when the NPC arrives at the WalkTo target. |
| `.Stuck` | Fires after 3 failed retry attempts (jumps + repath). |

---

### Perception

**Type:** Core

Vision cone detection with tracking awareness. Fires signals when threats are spotted or lost.

#### Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `visionRange` | `number` | `60` | Max detection distance (studs). |
| `visionAngle` | `number` | `120` | Initial detection cone (degrees). |
| `trackingAngle` | `number` | `360` | Angle used for already-spotted targets. |
| `hearingRange` | `number` | `40` | Range for `CanHear` checks. |
| `perceptionInterval` | `number` | `0.2` | Seconds between scans. |
| `threatTags` | `{ string }` | `{ "Player" }` | CollectionService tags to scan for. |
| `maxChecks` | `number` | `10` | Max raycasts per scan (performance cap). |

#### Detection vs Tracking

When a target is **first detected**, Perception uses the `visionAngle` cone — the NPC must be facing them.

Once a target is **already tracked** (was visible last scan), Perception uses `trackingAngle` instead (default: 360, omnidirectional). The only way to escape a tracking NPC is to:

- Get out of `visionRange`
- Break line of sight behind geometry

This prevents the common issue of targets escaping just by jumping behind the NPC.

#### Methods

**`:CanSee(target, overrideAngle?) --> boolean`**

Checks if the target Model is within range, within the vision cone, and has clear line of sight. Optionally override the angle for custom checks.

**`:CanHear(position) --> boolean`**

Returns `true` if the position is within `hearingRange`. Omnidirectional — no cone check.

**`:GetVisibleThreats() --> { Model }`**

Returns all currently visible threats from the last scan.

**`:SetConfig(config)`**

Updates perception settings at runtime.

#### Signals

| Signal | Parameters | Description |
|--------|-----------|-------------|
| `.ThreatSpotted` | `(target: Model)` | A new threat entered detection. |
| `.ThreatLost` | `(target: Model)` | A previously tracked threat is no longer detected. |

---

### Patrol

**Type:** Action
**Requires:** Movement

Loops through a list of waypoints.

#### Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `points` | `{ Vector3 }` | *required* | Waypoints to cycle through. Any number of points. |
| `waitTime` | `number` | `1.0` | Seconds to wait at each point before advancing. |

```lua
npc:SetAction("Patrol", {
    points = { pointA, pointB, pointC, pointD },
    waitTime = 2,
})
```

The NPC cycles `A → B → C → D → A → B → ...` indefinitely.

---

### Wander

**Type:** Action
**Requires:** Movement

Picks random points within a radius and walks to them.

#### Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `origin` | `Vector3` | NPC's current position | Center of the wander area. |
| `radius` | `number` | `20` | Max distance from origin. |
| `waitTime` | `number` | `2.0` | Seconds to wait between wander points. |

```lua
npc:SetAction("Wander", {
    origin = guardPost,
    radius = 15,
    waitTime = 1,
})
```

Wander validates each random point with a ground raycast — it won't send the NPC off a cliff. A minimum distance is enforced so the NPC doesn't shuffle in place.

---

### Follow

**Type:** Action
**Requires:** Movement

Follows a target Model, maintaining a set distance.

#### Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `target` | `Model` | *required* | The model to follow. Must exist. |
| `distance` | `number` | `10` | Desired distance from the target. |

```lua
npc:SetAction("Follow", {
    target = playerCharacter,
    distance = 8,
})
```

Follow automatically clears itself if the target is destroyed. It has a built-in buffer zone to prevent micro-stepping — the NPC won't re-engage until the target moves meaningfully beyond the follow distance.

---

### Idle

**Type:** Action

Does nothing. Useful as a placeholder action when the NPC should stand still but you want to explicitly set an action state.

```lua
npc:SetAction("Idle")
```

---

## Custom Components

You can register your own components with `Puppet.registerComponent`. A component must implement this interface:

```lua
local MyComponent = {}
MyComponent.__index = MyComponent

MyComponent.Name = "MyComponent"
MyComponent.Type = "Core" -- or "Action"
MyComponent.Requires = { "Movement" } -- optional, list dependency names

function MyComponent.new(puppet, config)
    local self = setmetatable({}, MyComponent)
    self._puppet = puppet
    -- read config, set up state
    return self
end

function MyComponent:Init()
    -- called after dependencies are injected
    -- self.Movement is available here if declared in Requires
end

function MyComponent:Update(dt)
    -- optional, called every tick (30hz by default)
end

function MyComponent:SetConfig(config)
    -- optional, called by Reconfigure to update settings
end

function MyComponent:Destroy()
    -- cleanup connections, signals, etc.
end

return MyComponent
```

Register it before creating any Puppets that use it:

```lua
Puppet.registerComponent("MyComponent", require(path.to.MyComponent))
```

Then use it in configs like any built-in:

```lua
local npc = Puppet.new(model, {
    movement = {},
    mycomponent = { someSetting = true },
})
```
