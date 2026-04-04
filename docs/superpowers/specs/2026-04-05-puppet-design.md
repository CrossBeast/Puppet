# Puppet — Composition-Based NPC System

## Overview

Puppet is a server-side Luau module for Roblox that provides composable NPC capabilities. It follows **Inversion of Control** — the module provides tools (movement, perception, patrol, etc.), not decisions. Game logic and behavior orchestration live in the developer's scripts.

Ships as a self-contained package. One `require()`, no external dependencies.

### Design Principles

- **Inversion of Control** — Puppet provides capabilities, the developer orchestrates behavior
- **Single Responsibility** — each component does one thing
- **Open/Closed** — developers extend via custom components without modifying source
- **Composition over Inheritance** — NPCs are a bag of components, not a class hierarchy
- **Least Surprise** — API does what you'd expect, no hidden side effects

### Typing Strategy

Basic type annotations for variables, return types, and function signatures. No `--!strict`. Enough for autocomplete and readability, not so much that it clutters the code.

---

## Package Structure

```
Puppet/
  init.luau             -- entry point: require(path.to.Puppet)
  Types.luau            -- shared type definitions
  PuppetObject.luau     -- the Puppet class
  PuppetUpdater.luau    -- centralized update loop (internal)
  ComponentRegistry.luau -- built-in + custom component registration
  Packages/
    Trove/              -- cleanup utility
    Signal/             -- signal implementation
  Components/
    Movement.luau
    Perception.luau
    Patrol.luau
    Wander.luau
    Idle.luau
    Follow.luau
```

---

## Architecture

### Three Layers

**1. Puppet (the NPC object)**
The container. Holds a reference to the Roblox Model, manages a flat table of core components and a single active action, handles component lifecycle, and registers itself with the PuppetUpdater on creation.

**2. Components**
Self-contained capability modules. Two types:

- **Core** — stackable, can coexist (Movement, Perception). These are the tools.
- **Action** — exclusive, one active at a time (Patrol, Wander, Idle, Follow). These use the tools.

**3. PuppetUpdater (internal)**
A single `RunService.Heartbeat` connection that iterates all living Puppets and calls `Update(dt)` on their active components. Default tick rate: 30hz. Globally configurable via `Puppet.setTickRate(hz)`. The developer never interacts with this directly.

### Update Flow

```
PuppetUpdater (one Heartbeat connection, 30hz default)
  └── for each registered Puppet:
        └── for each component on the Puppet:
              ├── Core: Movement:Update(dt)
              ├── Core: Perception:Update(dt)  -- internally throttled by perceptionInterval
              └── Action: Patrol:Update(dt)
                    └── uses self.Movement (injected reference)
```

---

## Component Contract

Every component (built-in or custom) follows this contract:

```lua
local MyComponent = {}
MyComponent.__index = MyComponent

-- Required fields
MyComponent.Name = "MyComponent"
MyComponent.Type = "Core"                -- "Core" or "Action"

-- Optional fields
MyComponent.Requires = { "Movement" }    -- dependencies (Core component names ONLY)

-- Required methods
function MyComponent.new(puppet, config)
    local self = setmetatable({}, MyComponent)
    self._puppet = puppet
    -- read config here
    return self
end

function MyComponent:Init()
    -- called after dependencies are injected onto self
    -- self.Movement is available here if declared in Requires
end

function MyComponent:Destroy()
    -- cleanup connections, state, references
end

-- Optional methods
function MyComponent:Update(dt)
    -- called each tick; omit if component has nothing to update
end

function MyComponent:SetConfig(config)
    -- merge new config values at runtime
end
```

### Rules

- `Update()` is optional. If a component does not define it, the updater skips it.
- `SetConfig()` is optional. If defined, it merges new values and they take effect on the next `Update`. It does not restart the component.
- `Destroy()` must clean up all connections, state, and references. The Puppet calls this when the component is removed.
- Components access their dependencies via `self.DependencyName` (set by the Puppet during injection). They do NOT call `puppet:GetComponent()` internally.
- `puppet:GetComponent()` is for external game scripts only.
- `Requires` can only reference **Core** components. An Action cannot require another Action (only one Action is active at a time).
- All required components must be **explicitly present** in the config or already added to the Puppet. Puppet does NOT auto-add missing dependencies. If Patrol requires Movement and Movement isn't in the config, construction errors: `[Puppet] "Patrol" requires "Movement", but it hasn't been added. Add movement to your config.`

---

## Dependency Resolution

Happens at `AddComponent()` / `SetAction()` time:

1. Read the component's `Requires` table (if any).
2. For each requirement, look it up in `puppet._components` (the core components table).
3. If found, set `component[name] = puppet._components[name]`.
4. If missing, error: `[Puppet] "Patrol" requires "Movement", but it hasn't been added.`
5. Call `component:Init()`.

### Dependency Protection on Removal

When `RemoveComponent(name)` is called:

1. Check if the active action's `Requires` includes `name`.
2. Check if any other core component's `Requires` includes `name`.
3. If anything depends on it, error: `[Puppet] Cannot remove "Movement" — required by "Patrol". Remove "Patrol" first.`
4. Otherwise, call `component:Destroy()` and remove the reference.

### Core Component Ordering During Construction

When `Puppet.new()` processes the config, core components are created in dependency order:

1. Collect all core components from the config.
2. Create components with no `Requires` first.
3. Create components whose `Requires` are already satisfied.
4. Repeat until all are created. If a cycle is detected (a core requires another core that requires the first), error at construction time.
5. Create the action last (it can depend on any core).

---

## Component Type Rules

### AddComponent (Core only)

- Accepts Core components only.
- If an Action name is passed, warns: `[Puppet] "Patrol" is an Action. Use SetAction() instead.`
- If the component already exists on this Puppet, warns: `[Puppet] "Movement" is already added.`

### SetAction (Action only)

- Accepts Action components only.
- Destroys the current action (if any) before creating the new one.
- Resolves dependencies from existing core components.
- If a required core component is missing, errors.

### ClearAction

- Destroys the current action, sets it to nil.
- The NPC stands still — no active behavior.

### RemoveComponent (Core only)

- Checks dependency protection (see above).
- Calls `Destroy()` on the component.
- Removes the reference from the Puppet.

---

## Reentrancy Safety

If a component's `Update()` calls `SetAction()`, `AddComponent()`, `RemoveComponent()`, or `ClearAction()`, the change is **deferred** to the end of the current tick. The updater finishes iterating all components for this Puppet, then applies pending changes.

This prevents:
- Destroying a component mid-iteration
- Dependency references going nil during another component's Update
- Unpredictable ordering when one component's Update triggers changes that affect another

---

## Error Isolation

Each component's `Update()` is wrapped in `pcall`. If one component throws, the updater warns with the error and continues to the next component. One broken component does not crash other components or other Puppets.

---

## Model Lifecycle

- `Puppet.new()` connects to `Model.Destroying`. If the Model is destroyed externally (by game code), the Puppet auto-cleans up — all components are destroyed, the Puppet is unregistered from the updater.
- `Puppet.new()` checks if a Puppet already exists for this Model. If so, errors: `[Puppet] A Puppet already exists for this Model. Destroy it first.`
- `Puppet.new()` validates that the Model has a `Humanoid` and `HumanoidRootPart`. If either is missing, errors immediately.

## Component Registration Validation

When `Puppet.registerComponent()` is called, the class is validated:

- Must have `Name` (string) and `Type` ("Core" or "Action").
- Must have `new` (function), `Init` (function), and `Destroy` (function).
- `Requires`, `Update`, and `SetConfig` are optional.
- If `Name` conflicts with a built-in component, errors: `[Puppet] Cannot override built-in component "Movement".`
- If `Name` is already registered as a custom component, errors: `[Puppet] Component "Dance" is already registered.`

## Target Destruction Handling

Components that reference external Models (Follow's `target`, or any custom component with a target reference) are responsible for handling target destruction gracefully. The Follow component connects to `target.Destroying` and calls `self._puppet:ClearAction()` when the target is destroyed. Custom components should follow the same pattern.

---

## Public API

### Module-Level

```lua
local Puppet = require(path.to.Puppet)

-- Create a new Puppet
Puppet.new(model: Model, config: table) -> Puppet

-- Register a custom component (call before using it in Puppet.new or AddComponent)
Puppet.registerComponent(name: string, componentClass: table)

-- Global updater config
Puppet.setTickRate(hz: number)       -- default: 30
Puppet.getTickRate() -> number
```

### Puppet Instance

```lua
-- Core component management
puppet:AddComponent(name: string, config: table?)
puppet:RemoveComponent(name: string)
puppet:GetComponent(name: string) -> Component?
puppet:HasComponent(name: string) -> boolean

-- Action management
puppet:SetAction(name: string, config: table?)
puppet:GetAction() -> Component?
puppet:ClearAction()

-- Bulk reconfiguration
puppet:Reconfigure(config: table)

-- Lifecycle
puppet:Destroy()

-- Properties
puppet.Model: Model           -- the Roblox Model
puppet.Humanoid: Humanoid     -- cached reference
puppet.RootPart: BasePart     -- cached HumanoidRootPart reference

-- Signals
puppet.ComponentAdded: Signal<string>          -- fires component name
puppet.ComponentRemoved: Signal<string>        -- fires component name
puppet.ActionChanged: Signal<string?, string?> -- fires (previousName, newName)
puppet.Destroyed: Signal<>
```

### Reconfigure Behavior

`puppet:Reconfigure(config)` diffs the new config against the current state:

1. **Core components in new config but not current** — `AddComponent` with config.
2. **Core components in current but not in new config** — `RemoveComponent` (respects dependency protection — errors if something depends on it).
3. **Core components in both** — calls `SetConfig()` with new values.
4. **Action changed** — `SetAction()` with the new action and its config.
5. **Action in current but not in new config** — `ClearAction()`.

Reconfigure processes removals first (in reverse dependency order), then updates, then additions (in dependency order), then the action last.

### Config Key Mapping

Config keys are **lowercase** and map to **PascalCase** component names:

| Config Key   | Component Name |
|-------------|---------------|
| `movement`   | `Movement`     |
| `perception` | `Perception`   |
| `patrol`     | `Patrol`       |
| `wander`     | `Wander`       |
| `idle`       | `Idle`         |
| `follow`     | `Follow`       |

Custom components registered via `Puppet.registerComponent("Dance", DanceClass)` use the config key `"dance"`.

---

## Built-In Components

### Movement (Core)

Wraps PathfindingService with polish for natural, efficient NPC movement.

**Features:**
- Direct movement for short distances (skips pathfinding when a straight line works)
- Waypoint skipping (doesn't stop-start at each point)
- Smart repathing when path is blocked or NPC drifts off-course
- Stuck detection with retry and exponential backoff
- Jump handling for elevation changes
- Path blocked detection and recovery

**Config:**
| Key            | Type   | Default | Description                        |
|---------------|--------|---------|-------------------------------------|
| `walkSpeed`    | number | 12      | Humanoid WalkSpeed                  |
| `runSpeed`     | number | 24      | Speed when running                  |
| `arrivalRadius`| number | 4       | Distance to consider "arrived"      |

**Public API:**
- `WalkTo(position: Vector3) -> boolean` — pathfind to position, returns success
- `Stop()` — cancel current movement
- `IsMoving() -> boolean`
- `IsStuck() -> boolean`
- `SetConfig(config)`

**Signals:**
- `ReachedDestination` — fired when NPC arrives at its WalkTo target
- `Stuck` — fired when stuck detection triggers

### Perception (Core)

Vision and hearing detection for NPCs.

**Features:**
- Vision: cone-based (configurable range + angle) with raycast occlusion
- Hearing: radius-based proximity check
- Throttled updates on a configurable interval (not every frame)
- Filters targets by CollectionService tags
- Tracks visible/lost targets between checks to fire signals accurately

**Config:**
| Key                 | Type     | Default      | Description                           |
|--------------------|----------|-------------- |----------------------------------------|
| `visionRange`       | number   | 60           | How far the NPC can see                |
| `visionAngle`       | number   | 120          | Field of view in degrees               |
| `hearingRange`      | number   | 40           | How far the NPC can hear               |
| `perceptionInterval`| number   | 0.2          | Seconds between perception checks      |
| `threatTags`        | {string} | `{"Player"}` | CollectionService tags to detect       |

**Public API:**
- `CanSee(model: Model) -> boolean` — instant check (not throttled)
- `CanHear(position: Vector3) -> boolean` — instant check
- `GetVisibleThreats() -> {Model}` — targets visible as of last check
- `SetConfig(config)`

**Signals:**
- `ThreatSpotted(target: Model)` — first frame a target becomes visible
- `ThreatLost(target: Model)` — first frame a previously visible target is no longer visible

### Patrol (Action)

Walks through a list of points in order, loops.

**Requires:** `Movement`

**Config:**
| Key        | Type      | Default | Description                          |
|-----------|-----------|---------|---------------------------------------|
| `points`   | {Vector3} | —       | Required. Waypoints to patrol between |
| `waitTime` | number    | 1.0     | Seconds to wait at each point         |

### Wander (Action)

Picks random points within a radius and walks to them. Validates candidate points with a ground raycast to avoid selecting positions inside walls or off edges.

**Requires:** `Movement`

**Config:**
| Key        | Type    | Default        | Description                           |
|-----------|---------|----------------|----------------------------------------|
| `origin`   | Vector3 | spawn position | Center point to wander around          |
| `radius`   | number  | 20             | Max distance from origin               |
| `waitTime` | number  | 2.0            | Seconds to wait at each point          |

### Idle (Action)

Stands still. Explicit "do nothing" state.

**Requires:** nothing

**Config:** none

### Follow (Action)

Follows a target Model, maintaining a specified distance.

**Requires:** `Movement`

**Config:**
| Key        | Type  | Default | Description                              |
|-----------|-------|---------|-------------------------------------------|
| `target`   | Model | —       | Required. The Model to follow             |
| `distance` | number| 8       | Distance to maintain from target          |

---

## Usage Examples

### Basic NPC

```lua
local Puppet = require(path.to.Puppet)

local guard = Puppet.new(workspace.GuardModel, {
    movement = { walkSpeed = 14 },
    perception = { visionRange = 60, visionAngle = 120 },
    patrol = {
        points = {
            Vector3.new(0, 0, 0),
            Vector3.new(20, 0, 0),
            Vector3.new(20, 0, 20),
        },
        waitTime = 1.5,
    },
})
```

### Developer-Orchestrated Behavior

```lua
local perception = guard:GetComponent("Perception")

perception.ThreatSpotted:Connect(function(target)
    guard:SetAction("Follow", { target = target, distance = 5 })
end)

perception.ThreatLost:Connect(function(target)
    guard:SetAction("Patrol", {
        points = { Vector3.new(0, 0, 0), Vector3.new(20, 0, 0) },
    })
end)
```

### Runtime Component Swapping

```lua
-- Disable perception mid-game
guard:RemoveComponent("Perception")

-- Re-enable with different config
guard:AddComponent("Perception", { visionRange = 100, visionAngle = 360 })
```

### Boss Phase Transformation

```lua
boss:Reconfigure({
    movement = { walkSpeed = 22, runSpeed = 36 },
    perception = { visionRange = 80, visionAngle = 360 },
    follow = { target = player.Character, distance = 3 },
})
```

### Custom Component

```lua
local Dance = {}
Dance.__index = Dance

Dance.Name = "Dance"
Dance.Type = "Action"
Dance.Requires = { "Movement" }

function Dance.new(puppet, config)
    local self = setmetatable({}, Dance)
    self._puppet = puppet
    self._duration = config.duration or 5
    self._elapsed = 0
    return self
end

function Dance:Init()
    self.Movement:Stop()
end

function Dance:Update(dt)
    self._elapsed += dt
    if self._elapsed >= self._duration then
        self._puppet:ClearAction()
    end
end

function Dance:Destroy() end

Puppet.registerComponent("Dance", Dance)

-- Use it
npc:SetAction("Dance", { duration = 3 })
```

---

## Out of Scope

These are explicitly NOT part of Puppet. They are game-specific and should be built by the developer using Puppet's components:

- **Combat** (damage, health, attacks)
- **Flee / Retreat** (buildable with Movement + Perception + game logic)
- **Hunt / Chase** (buildable with Follow + Perception + game logic)
- **Guard** (buildable with Patrol + Perception + Follow + game logic)
- **Animation** (game-specific rigs and animation sets)
- **Dialogue / Interaction** (UI/game-specific)
- **Spawn / Respawn** (game-specific lifecycle)
- **Movement styles** (stealth, sprint, parkour — game-specific modifiers)
