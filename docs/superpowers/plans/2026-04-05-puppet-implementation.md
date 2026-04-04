# Puppet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Puppet composition-based NPC system as specified in `docs/superpowers/specs/2026-04-05-puppet-design.md`.

**Architecture:** A self-contained Luau module with three layers — Puppet (container), Components (capabilities), and PuppetUpdater (centralized tick loop). Components are Core (stackable) or Action (exclusive). Dependencies are declared and injected at add-time. The developer orchestrates behavior through signals and game scripts.

**Tech Stack:** Luau, Roblox Engine APIs (PathfindingService, CollectionService, RunService), Rojo for file sync.

---

### Task 1: Project Setup

**Files:**
- Create: `.gitignore`
- Create: `default.project.json`
- Create: `src/Puppet/` (directory structure)
- Create: `test/` (directory)

- [ ] **Step 1: Initialize git repository**

```bash
cd /Users/Harvey/Documents/-Developer/Roblox/Portfolio/CompositionNPC
git init
```

- [ ] **Step 2: Create .gitignore**

```
*.rbxl
*.rbxlx
*.rbxm
*.rbxmx
.DS_Store
```

- [ ] **Step 3: Create Rojo project file**

`default.project.json`:
```json
{
    "name": "Puppet",
    "tree": {
        "$className": "DataModel",
        "ServerScriptService": {
            "Puppet": {
                "$path": "src/Puppet"
            },
            "PuppetTest": {
                "$path": "test/PuppetTest.server.luau"
            }
        }
    }
}
```

- [ ] **Step 4: Create directory structure**

```bash
mkdir -p src/Puppet/Packages
mkdir -p src/Puppet/Components
mkdir -p test
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore default.project.json
git commit -m "chore: project setup with Rojo config"
```

---

### Task 2: Signal Package

**Files:**
- Create: `src/Puppet/Packages/Signal.luau`

- [ ] **Step 1: Write Signal implementation**

`src/Puppet/Packages/Signal.luau`:
```lua
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
    -- Iterate backwards so disconnects during fire are safe
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
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Packages/Signal.luau
git commit -m "feat: add Signal package"
```

---

### Task 3: Trove Package

**Files:**
- Create: `src/Puppet/Packages/Trove.luau`

- [ ] **Step 1: Write Trove implementation**

`src/Puppet/Packages/Trove.luau`:
```lua
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
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Packages/Trove.luau
git commit -m "feat: add Trove package"
```

---

### Task 4: ComponentRegistry

**Files:**
- Create: `src/Puppet/ComponentRegistry.luau`

- [ ] **Step 1: Write ComponentRegistry**

`src/Puppet/ComponentRegistry.luau`:
```lua
-- Manages registration, validation, and lookup of component classes.
-- Built-in components are registered internally by init.luau.
-- Custom components are registered by the developer via Puppet.registerComponent().

local ComponentRegistry = {}

local builtInComponents = {}
local customComponents = {}
local configKeyMap = {} -- lowercase -> PascalCase

local BUILT_IN_NAMES = {
    Movement = true,
    Perception = true,
    Patrol = true,
    Wander = true,
    Idle = true,
    Follow = true,
}

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
            string.format("[Puppet] Component '%s' Requires must be a table", name))
        for _, req in componentClass.Requires do
            assert(type(req) == "string",
                string.format("[Puppet] Component '%s' Requires entries must be strings", name))
        end
    end
end

function ComponentRegistry._registerBuiltIn(name, componentClass)
    validateComponentClass(name, componentClass)
    builtInComponents[name] = componentClass
    configKeyMap[string.lower(name)] = name
end

function ComponentRegistry.register(name, componentClass)
    validateComponentClass(name, componentClass)

    if BUILT_IN_NAMES[name] then
        error(string.format("[Puppet] Cannot override built-in component '%s'", name))
    end

    if customComponents[name] then
        error(string.format("[Puppet] Component '%s' is already registered", name))
    end

    customComponents[name] = componentClass
    configKeyMap[string.lower(name)] = name
end

function ComponentRegistry.get(name)
    return builtInComponents[name] or customComponents[name]
end

function ComponentRegistry.resolveConfigKey(lowercaseKey)
    return configKeyMap[lowercaseKey]
end

return ComponentRegistry
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/ComponentRegistry.luau
git commit -m "feat: add ComponentRegistry with validation"
```

---

### Task 5: PuppetUpdater

**Files:**
- Create: `src/Puppet/PuppetUpdater.luau`

- [ ] **Step 1: Write PuppetUpdater**

`src/Puppet/PuppetUpdater.luau`:
```lua
-- Centralized update loop for all Puppet instances.
-- Single RunService.Heartbeat connection, fixed tick rate.
-- Internal module — developers never interact with this directly.

local RunService = game:GetService("RunService")

local PuppetUpdater = {}

local puppets = {} -- { [string]: PuppetObject }
local tickRate = 1 / 30
local accumulator = 0
local MAX_SUBSTEPS = 3

function PuppetUpdater.register(puppet)
    puppets[puppet._id] = puppet
end

function PuppetUpdater.unregister(puppet)
    puppets[puppet._id] = nil
end

function PuppetUpdater.setTickRate(hz)
    assert(type(hz) == "number" and hz > 0, "[Puppet] Tick rate must be a positive number")
    tickRate = 1 / hz
end

function PuppetUpdater.getTickRate()
    return math.round(1 / tickRate)
end

RunService.Heartbeat:Connect(function(dt)
    accumulator += dt

    local substeps = 0
    while accumulator >= tickRate and substeps < MAX_SUBSTEPS do
        accumulator -= tickRate
        substeps += 1

        for id, puppet in puppets do
            if puppet._destroyed then
                puppets[id] = nil
                continue
            end

            puppet._updating = true

            -- Update core components
            for _, component in puppet._components do
                if component.Update then
                    local ok, err = pcall(component.Update, component, tickRate)
                    if not ok then
                        warn(string.format("[Puppet] %s:Update() error on '%s': %s",
                            component.Name, puppet.Model.Name, tostring(err)))
                    end
                end
            end

            -- Update active action
            local action = puppet._action
            if action and action.Update then
                local ok, err = pcall(action.Update, action, tickRate)
                if not ok then
                    warn(string.format("[Puppet] %s:Update() error on '%s': %s",
                        action.Name, puppet.Model.Name, tostring(err)))
                end
            end

            puppet._updating = false

            -- Apply deferred changes
            puppet:_applyDeferred()
        end
    end

    -- Prevent unbounded accumulation
    if accumulator > tickRate then
        accumulator = tickRate
    end
end)

return PuppetUpdater
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/PuppetUpdater.luau
git commit -m "feat: add PuppetUpdater with centralized heartbeat loop"
```

---

### Task 6: PuppetObject

**Files:**
- Create: `src/Puppet/PuppetObject.luau`

This is the core module. It handles construction, component management, action management, reentrancy safety, signals, reconfiguration, and destruction.

- [ ] **Step 1: Write PuppetObject**

`src/Puppet/PuppetObject.luau`:
```lua
-- The Puppet class. Container for components, manages lifecycle.

local HttpService = game:GetService("HttpService")

local Signal = require(script.Parent.Packages.Signal)
local Trove = require(script.Parent.Packages.Trove)
local ComponentRegistry = require(script.Parent.ComponentRegistry)
local PuppetUpdater = require(script.Parent.PuppetUpdater)

local PuppetObject = {}
PuppetObject.__index = PuppetObject

-- Track active puppets per model to prevent duplicates
local activePuppets = {}

function PuppetObject.new(model, config)
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

    -- Signals
    self.ComponentAdded = Signal.new()
    self.ComponentRemoved = Signal.new()
    self.ActionChanged = Signal.new()
    self.Destroyed = Signal.new()

    -- Auto-cleanup on model destruction
    self._trove:Add(model.Destroying:Connect(function()
        self:Destroy()
    end))

    -- Track for duplicate prevention
    activePuppets[model] = self

    -- Register with updater
    PuppetUpdater.register(self)

    -- Process config
    if config then
        self:_processConfig(config)
    end

    return self
end

-- ── Config Processing ─────────────────────────────────────────────────────

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

    -- Create cores in dependency order
    self:_createCoresInOrder(coreEntries)

    -- Create action
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

    -- Inject dependencies
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

-- ── Component Management ──────────────────────────────────────────────────

function PuppetObject:AddComponent(name, config)
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

function PuppetObject:RemoveComponent(name)
    if self._destroyed then
        warn("[Puppet] Cannot RemoveComponent on a destroyed Puppet")
        return
    end

    local component = self._components[name]
    if not component then
        warn(string.format('[Puppet] Component "%s" is not on this Puppet', name))
        return
    end

    -- Dependency protection: check if action depends on this component
    if self._action then
        local actionRequires = self._action.Requires or {}
        for _, req in actionRequires do
            if req == name then
                error(string.format(
                    '[Puppet] Cannot remove "%s" — required by action "%s". Remove the action first.',
                    name, self._action.Name))
            end
        end
    end

    -- Dependency protection: check if another core depends on this component
    for otherName, otherComponent in self._components do
        if otherName ~= name then
            local otherRequires = otherComponent.Requires or {}
            for _, req in otherRequires do
                if req == name then
                    error(string.format(
                        '[Puppet] Cannot remove "%s" — required by "%s". Remove "%s" first.',
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

function PuppetObject:GetComponent(name)
    return self._components[name]
end

function PuppetObject:HasComponent(name)
    return self._components[name] ~= nil
end

-- ── Action Management ─────────────────────────────────────────────────────

function PuppetObject:SetAction(name, config)
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

    -- Destroy current action
    if self._action then
        self._action:Destroy()
        self._action = nil
    end

    -- Create new action
    local component = componentClass.new(self, config or {})

    -- Inject dependencies
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

function PuppetObject:GetAction()
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

-- ── Reconfigure ───────────────────────────────────────────────────────────

function PuppetObject:Reconfigure(config)
    if self._destroyed then
        warn("[Puppet] Cannot Reconfigure a destroyed Puppet")
        return
    end

    -- Parse new config
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

    -- Step 1: Clear action first (avoids dependency issues during core removal)
    local currentActionName = self._action and self._action.Name or nil
    self:ClearAction()

    -- Step 2: Remove cores not in new config
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

    -- Step 3: Update existing cores
    for name, newConfig in newCores do
        local existing = self._components[name]
        if existing and existing.SetConfig then
            existing:SetConfig(newConfig)
        end
    end

    -- Step 4: Add new cores in dependency order
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

    -- Step 5: Set new action
    if newActionName then
        self:SetAction(newActionName, newActionConfig)
    end
end

-- ── Reentrancy ────────────────────────────────────────────────────────────

function PuppetObject:_applyDeferred()
    if #self._deferredChanges == 0 then return end

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

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function PuppetObject:Destroy()
    if self._destroyed then return end
    self._destroyed = true

    -- Destroy action first
    if self._action then
        self._action:Destroy()
        self._action = nil
    end

    -- Destroy all core components
    for _, component in self._components do
        component:Destroy()
    end
    table.clear(self._components)

    -- Unregister
    PuppetUpdater.unregister(self)
    if self.Model then
        activePuppets[self.Model] = nil
    end

    -- Fire destroyed signal before cleaning up signals
    self.Destroyed:Fire()

    -- Cleanup connections and signals
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
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/PuppetObject.luau
git commit -m "feat: add PuppetObject with full component lifecycle"
```

---

### Task 7: Entry Point

**Files:**
- Create: `src/Puppet/init.luau`

- [ ] **Step 1: Write init.luau**

`src/Puppet/init.luau`:
```lua
-- Puppet — Composition-Based NPC System
-- Entry point. Registers built-in components and exposes public API.

local PuppetObject = require(script.PuppetObject)
local PuppetUpdater = require(script.PuppetUpdater)
local ComponentRegistry = require(script.ComponentRegistry)

-- Register built-in components
local Components = script.Components
ComponentRegistry._registerBuiltIn("Movement", require(Components.Movement))
ComponentRegistry._registerBuiltIn("Perception", require(Components.Perception))
ComponentRegistry._registerBuiltIn("Idle", require(Components.Idle))
ComponentRegistry._registerBuiltIn("Patrol", require(Components.Patrol))
ComponentRegistry._registerBuiltIn("Wander", require(Components.Wander))
ComponentRegistry._registerBuiltIn("Follow", require(Components.Follow))

local Puppet = {}

function Puppet.new(model, config)
    return PuppetObject.new(model, config)
end

function Puppet.registerComponent(name, componentClass)
    ComponentRegistry.register(name, componentClass)
end

function Puppet.setTickRate(hz)
    PuppetUpdater.setTickRate(hz)
end

function Puppet.getTickRate()
    return PuppetUpdater.getTickRate()
end

return Puppet
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/init.luau
git commit -m "feat: add Puppet entry point with built-in registration"
```

**Note:** This will not run yet because the component modules don't exist. Tasks 8-13 create them. Build all components before testing.

---

### Task 8: Idle Component

**Files:**
- Create: `src/Puppet/Components/Idle.luau`

- [ ] **Step 1: Write Idle component**

`src/Puppet/Components/Idle.luau`:
```lua
-- Idle: stands still. Explicit "do nothing" action.

local Idle = {}
Idle.__index = Idle

Idle.Name = "Idle"
Idle.Type = "Action"

function Idle.new(puppet, config)
    local self = setmetatable({}, Idle)
    self._puppet = puppet
    return self
end

function Idle:Init() end

function Idle:Destroy() end

return Idle
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Idle.luau
git commit -m "feat: add Idle component"
```

---

### Task 9: Movement Component

**Files:**
- Create: `src/Puppet/Components/Movement.luau`

- [ ] **Step 1: Write Movement component**

`src/Puppet/Components/Movement.luau`:
```lua
-- Movement: pathfinding, direct movement, stuck detection, repathing.
-- Core component — actions use this to move the NPC.

local PathfindingService = game:GetService("PathfindingService")
local Signal = require(script.Parent.Parent.Packages.Signal)

local Movement = {}
Movement.__index = Movement

Movement.Name = "Movement"
Movement.Type = "Core"

local DEFAULTS = {
    walkSpeed = 12,
    runSpeed = 24,
    arrivalRadius = 4,
}

-- Internal tuning
local DIRECT_MOVE_MAX_DISTANCE = 12
local DIRECT_MOVE_FALLBACK_MAX_DISTANCE = 42
local DIRECT_MOVE_VERTICAL_LIMIT = 4.5
local DIRECT_MOVE_RAY_HEIGHT = 2

local PATH_AGENT_RADIUS = 2
local PATH_AGENT_HEIGHT = 5
local PATH_WAYPOINT_SPACING = 4

local REPATH_COOLDOWN = 0.5
local MOVE_COMMAND_INTERVAL = 0.05

local STUCK_TIME_THRESHOLD = 2.0
local STUCK_DISTANCE_PER_TICK = 0.1 -- if NPC moves less than this per tick, it's not progressing
local STUCK_MAX_RETRIES = 3

local WAYPOINT_JUMP_VERTICAL_MIN = 1.5

function Movement.new(puppet, config)
    local self = setmetatable({}, Movement)
    self._puppet = puppet

    -- Config
    self._walkSpeed = config.walkSpeed or DEFAULTS.walkSpeed
    self._runSpeed = config.runSpeed or DEFAULTS.runSpeed
    self._arrivalRadius = config.arrivalRadius or DEFAULTS.arrivalRadius

    -- Movement state
    self._isMoving = false
    self._isStuck = false
    self._destination = nil
    self._currentPath = nil
    self._waypoints = {}
    self._waypointIndex = 1

    -- Stuck detection state
    self._stuckTime = 0
    self._stuckRetryCount = 0
    self._lastPosition = nil

    -- Throttling state
    self._lastPathCompute = 0
    self._lastMoveCommand = 0
    self._lastMoveTarget = nil

    -- Signals
    self.ReachedDestination = Signal.new()
    self.Stuck = Signal.new()

    -- Apply walk speed to humanoid
    puppet.Humanoid.WalkSpeed = self._walkSpeed

    return self
end

function Movement:Init()
    -- No dependencies to wire
end

function Movement:Update(dt)
    if not self._isMoving then
        self._stuckTime = 0
        self._lastPosition = nil
        return
    end

    self:_advanceWaypoints()
    self:_issueMovement()
    self:_detectStuck(dt)
end

function Movement:WalkTo(position)
    if self._puppet._destroyed then return false end
    if typeof(position) ~= "Vector3" then
        warn("[Puppet:Movement] WalkTo position must be a Vector3")
        return false
    end

    local rootPart = self._puppet.RootPart
    if not rootPart or not rootPart.Parent then return false end

    self._destination = position

    -- Throttle path recomputation
    local now = tick()
    if self._isMoving and (now - self._lastPathCompute) < REPATH_COOLDOWN then
        return true
    end
    self._lastPathCompute = now

    -- Try direct move for short distances
    local distance = (position - rootPart.Position).Magnitude
    if distance <= DIRECT_MOVE_MAX_DISTANCE and self:_canDirectMove(position) then
        return self:_setDirectWaypoint(position)
    end

    -- Full pathfinding
    local ok = self:_computePath(position)
    if not ok then
        -- Fallback to direct move at longer range
        if distance <= DIRECT_MOVE_FALLBACK_MAX_DISTANCE and self:_canDirectMove(position) then
            return self:_setDirectWaypoint(position)
        end
    end
    return ok
end

function Movement:Stop()
    self._isMoving = false
    self._destination = nil
    self._currentPath = nil
    table.clear(self._waypoints)
    self._waypointIndex = 1
    self._isStuck = false
    self._stuckTime = 0
    self._stuckRetryCount = 0
    self._lastPosition = nil
    self._lastMoveTarget = nil

    local humanoid = self._puppet.Humanoid
    local rootPart = self._puppet.RootPart
    if humanoid and rootPart and rootPart.Parent then
        humanoid:MoveTo(rootPart.Position)
    end
end

function Movement:IsMoving()
    return self._isMoving
end

function Movement:IsStuck()
    return self._isStuck
end

function Movement:SetConfig(config)
    if config.walkSpeed ~= nil then
        self._walkSpeed = config.walkSpeed
        if not self._isMoving then
            self._puppet.Humanoid.WalkSpeed = self._walkSpeed
        end
    end
    if config.runSpeed ~= nil then
        self._runSpeed = config.runSpeed
    end
    if config.arrivalRadius ~= nil then
        self._arrivalRadius = config.arrivalRadius
    end
end

function Movement:Destroy()
    self:Stop()
    self.ReachedDestination:Destroy()
    self.Stuck:Destroy()
end

-- ── Private: Pathfinding ──────────────────────────────────────────────────

function Movement:_canDirectMove(position)
    local origin = self._puppet.RootPart.Position
    local verticalDelta = math.abs(position.Y - origin.Y)
    if verticalDelta > DIRECT_MOVE_VERTICAL_LIMIT then
        return false
    end

    local travel = position - origin
    if travel.Magnitude < 1e-3 then return true end

    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { self._puppet.Model }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(
        origin + Vector3.new(0, DIRECT_MOVE_RAY_HEIGHT, 0),
        travel,
        rayParams
    )
    return result == nil
end

function Movement:_setDirectWaypoint(position)
    self._currentPath = nil
    self._waypoints = { { Position = position, Action = Enum.PathWaypointAction.Walk } }
    self._waypointIndex = 1
    self._isMoving = true
    self._stuckRetryCount = 0
    return true
end

function Movement:_computePath(position)
    local path = PathfindingService:CreatePath({
        AgentRadius = PATH_AGENT_RADIUS,
        AgentHeight = PATH_AGENT_HEIGHT,
        AgentCanJump = true,
        WaypointSpacing = PATH_WAYPOINT_SPACING,
    })

    local ok, err = pcall(function()
        path:ComputeAsync(self._puppet.RootPart.Position, position)
    end)

    if not ok then
        warn("[Puppet:Movement] Path computation error: " .. tostring(err))
        self._isMoving = false
        return false
    end

    if path.Status ~= Enum.PathStatus.Success then
        self._isMoving = false
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then
        self._isMoving = false
        return false
    end

    self._currentPath = path
    self._waypoints = waypoints
    self._waypointIndex = if #waypoints >= 2 then 2 else 1
    self._isMoving = true
    self._stuckRetryCount = 0

    return true
end

-- ── Private: Waypoint Progress ────────────────────────────────────────────

function Movement:_advanceWaypoints()
    local waypoints = self._waypoints
    local count = #waypoints
    if count == 0 then
        self._isMoving = false
        return
    end

    local index = self._waypointIndex
    local rootPos = self._puppet.RootPart.Position

    -- Skip past reached waypoints
    while index <= count do
        local wp = waypoints[index]
        if not wp then break end
        if self:_horizontalDistance(rootPos, wp.Position) <= self._arrivalRadius then
            index += 1
        else
            break
        end
    end
    self._waypointIndex = index

    -- Past all waypoints — check if we reached the destination
    if index > count then
        local dest = self._destination
        if dest and self:_horizontalDistance(rootPos, dest) <= self._arrivalRadius then
            self._isMoving = false
            self._destination = nil
            self.ReachedDestination:Fire()
        elseif dest then
            -- Overshot waypoints but not at destination — repath
            self._lastPathCompute = 0
            self:WalkTo(dest)
        else
            self._isMoving = false
        end
    end
end

-- ── Private: Movement Commands ────────────────────────────────────────────

function Movement:_issueMovement()
    if not self._isMoving then return end

    local waypoint = self._waypoints[self._waypointIndex]
    if not waypoint then return end

    -- Handle jump waypoints
    if waypoint.Action == Enum.PathWaypointAction.Jump then
        local verticalDelta = waypoint.Position.Y - self._puppet.RootPart.Position.Y
        if verticalDelta >= WAYPOINT_JUMP_VERTICAL_MIN then
            self._puppet.Humanoid.Jump = true
        end
    end

    -- Throttle MoveTo commands
    local now = tick()
    local targetPos = waypoint.Position
    local targetChanged = not self._lastMoveTarget
        or (self._lastMoveTarget - targetPos).Magnitude > 0.2

    if targetChanged or (now - self._lastMoveCommand >= MOVE_COMMAND_INTERVAL) then
        self._puppet.Humanoid:MoveTo(targetPos)
        self._lastMoveCommand = now
        self._lastMoveTarget = targetPos
    end
end

-- ── Private: Stuck Detection ──────────────────────────────────────────────

function Movement:_detectStuck(dt)
    if not self._isMoving then
        self._isStuck = false
        self._stuckTime = 0
        return
    end

    local rootPos = self._puppet.RootPart.Position

    if self._lastPosition then
        local moved = (rootPos - self._lastPosition).Magnitude
        if moved < STUCK_DISTANCE_PER_TICK then
            self._stuckTime += dt
        else
            self._stuckTime = 0
            self._stuckRetryCount = 0
        end
    end

    self._lastPosition = rootPos
    self._isStuck = self._stuckTime > STUCK_TIME_THRESHOLD

    if self._isStuck then
        self._stuckRetryCount += 1
        self._stuckTime = 0

        if self._stuckRetryCount > STUCK_MAX_RETRIES then
            self:Stop()
            self.Stuck:Fire()
            return
        end

        -- Try jumping
        self._puppet.Humanoid.Jump = true

        -- Force repath
        if self._destination then
            self._lastPathCompute = 0
            self:WalkTo(self._destination)
        end
    end
end

-- ── Private: Utility ──────────────────────────────────────────────────────

function Movement:_horizontalDistance(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

return Movement
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Movement.luau
git commit -m "feat: add Movement component with pathfinding and stuck detection"
```

---

### Task 10: Perception Component

**Files:**
- Create: `src/Puppet/Components/Perception.luau`

- [ ] **Step 1: Write Perception component**

`src/Puppet/Components/Perception.luau`:
```lua
-- Perception: vision cone, hearing radius, threat tracking with signals.
-- Core component — game scripts use ThreatSpotted/ThreatLost to orchestrate behavior.

local CollectionService = game:GetService("CollectionService")
local Signal = require(script.Parent.Parent.Packages.Signal)

local Perception = {}
Perception.__index = Perception

Perception.Name = "Perception"
Perception.Type = "Core"

local DEFAULTS = {
    visionRange = 60,
    visionAngle = 120,
    hearingRange = 40,
    perceptionInterval = 0.2,
    threatTags = { "Player" },
}

function Perception.new(puppet, config)
    local self = setmetatable({}, Perception)
    self._puppet = puppet

    -- Config
    self._visionRange = config.visionRange or DEFAULTS.visionRange
    self._visionAngle = config.visionAngle or DEFAULTS.visionAngle
    self._hearingRange = config.hearingRange or DEFAULTS.hearingRange
    self._perceptionInterval = config.perceptionInterval or DEFAULTS.perceptionInterval
    self._threatTags = config.threatTags or table.clone(DEFAULTS.threatTags)

    -- State
    self._lastCheck = tick() - (math.random() * self._perceptionInterval) -- stagger checks
    self._visibleThreats = {}
    self._previousThreats = {}

    -- Signals
    self.ThreatSpotted = Signal.new()
    self.ThreatLost = Signal.new()

    return self
end

function Perception:Init() end

function Perception:Update(dt)
    local now = tick()
    if now - self._lastCheck < self._perceptionInterval then return end
    self._lastCheck = now

    -- Gather candidates from tagged models
    local candidates = self:_getCandidates()

    -- Check visibility for each candidate
    local currentThreats = {}
    for _, candidate in candidates do
        if self:CanSee(candidate) then
            table.insert(currentThreats, candidate)
        end
    end

    -- Build lookup of previous threats
    local previousSet = {}
    for _, threat in self._previousThreats do
        previousSet[threat] = true
    end

    -- Fire ThreatSpotted for newly visible targets
    local currentSet = {}
    for _, threat in currentThreats do
        currentSet[threat] = true
        if not previousSet[threat] then
            self.ThreatSpotted:Fire(threat)
        end
    end

    -- Fire ThreatLost for targets no longer visible
    for _, threat in self._previousThreats do
        if not currentSet[threat] then
            self.ThreatLost:Fire(threat)
        end
    end

    self._visibleThreats = currentThreats
    self._previousThreats = currentThreats
end

function Perception:CanSee(target)
    if self._puppet._destroyed then return false end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not targetRoot:IsA("BasePart") then return false end

    local selfPos = self._puppet.RootPart.Position
    local toTarget = targetRoot.Position - selfPos
    local distance = toTarget.Magnitude

    -- Range check
    if distance > self._visionRange then return false end
    if distance < 1e-3 then return true end

    -- Angle check (vision cone)
    local forward = self._puppet.RootPart.CFrame.LookVector
    local direction = toTarget.Unit
    local dot = forward:Dot(direction)
    local halfAngle = math.rad(self._visionAngle / 2)
    if dot < math.cos(halfAngle) then return false end

    -- Raycast occlusion check
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { self._puppet.Model, target }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(selfPos, toTarget, rayParams)
    return result == nil
end

function Perception:CanHear(position)
    if self._puppet._destroyed then return false end
    if typeof(position) ~= "Vector3" then return false end
    return (self._puppet.RootPart.Position - position).Magnitude <= self._hearingRange
end

function Perception:GetVisibleThreats()
    return self._visibleThreats
end

function Perception:SetConfig(config)
    if config.visionRange ~= nil then self._visionRange = config.visionRange end
    if config.visionAngle ~= nil then self._visionAngle = config.visionAngle end
    if config.hearingRange ~= nil then self._hearingRange = config.hearingRange end
    if config.perceptionInterval ~= nil then self._perceptionInterval = config.perceptionInterval end
    if config.threatTags ~= nil then self._threatTags = config.threatTags end
end

function Perception:Destroy()
    table.clear(self._visibleThreats)
    table.clear(self._previousThreats)
    self.ThreatSpotted:Destroy()
    self.ThreatLost:Destroy()
end

-- ── Private ───────────────────────────────────────────────────────────────

function Perception:_getCandidates()
    local candidates = {}
    for _, tag in self._threatTags do
        for _, tagged in CollectionService:GetTagged(tag) do
            if tagged:IsA("Model") and tagged ~= self._puppet.Model then
                local humanoid = tagged:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    table.insert(candidates, tagged)
                end
            end
        end
    end
    return candidates
end

return Perception
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Perception.luau
git commit -m "feat: add Perception component with vision cone and threat signals"
```

---

### Task 11: Patrol Component

**Files:**
- Create: `src/Puppet/Components/Patrol.luau`

- [ ] **Step 1: Write Patrol component**

`src/Puppet/Components/Patrol.luau`:
```lua
-- Patrol: walks through a list of points in order, loops.
-- Listens to Movement signals for arrival and stuck recovery.

local Patrol = {}
Patrol.__index = Patrol

Patrol.Name = "Patrol"
Patrol.Type = "Action"
Patrol.Requires = { "Movement" }

local DEFAULTS = {
    waitTime = 1.0,
}

function Patrol.new(puppet, config)
    local self = setmetatable({}, Patrol)
    self._puppet = puppet

    assert(type(config.points) == "table" and #config.points > 0,
        "[Puppet:Patrol] Config must include 'points' with at least one Vector3")

    self._points = config.points
    self._waitTime = config.waitTime or DEFAULTS.waitTime
    self._currentIndex = 1
    self._waiting = false
    self._waitElapsed = 0

    -- Set by dependency injection
    self.Movement = nil

    -- Connections (set in Init)
    self._reachedConn = nil
    self._stuckConn = nil

    return self
end

function Patrol:Init()
    self._reachedConn = self.Movement.ReachedDestination:Connect(function()
        self._waiting = true
        self._waitElapsed = 0
    end)

    self._stuckConn = self.Movement.Stuck:Connect(function()
        -- Skip to next point on stuck
        self:_advance()
        self.Movement:WalkTo(self._points[self._currentIndex])
    end)

    self.Movement:WalkTo(self._points[self._currentIndex])
end

function Patrol:Update(dt)
    if self._waiting then
        self._waitElapsed += dt
        if self._waitElapsed >= self._waitTime then
            self._waiting = false
            self._waitElapsed = 0
            self:_advance()
            self.Movement:WalkTo(self._points[self._currentIndex])
        end
        return
    end

    -- Re-issue walk if movement stopped unexpectedly
    if not self.Movement:IsMoving() and not self._waiting then
        self.Movement:WalkTo(self._points[self._currentIndex])
    end
end

function Patrol:Destroy()
    if self._reachedConn then self._reachedConn:Disconnect() end
    if self._stuckConn then self._stuckConn:Disconnect() end
    self.Movement:Stop()
end

function Patrol:_advance()
    self._currentIndex += 1
    if self._currentIndex > #self._points then
        self._currentIndex = 1
    end
end

return Patrol
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Patrol.luau
git commit -m "feat: add Patrol component"
```

---

### Task 12: Wander Component

**Files:**
- Create: `src/Puppet/Components/Wander.luau`

- [ ] **Step 1: Write Wander component**

`src/Puppet/Components/Wander.luau`:
```lua
-- Wander: picks random points within a radius, walks to them.
-- Validates candidate points with ground raycasts.

local Wander = {}
Wander.__index = Wander

Wander.Name = "Wander"
Wander.Type = "Action"
Wander.Requires = { "Movement" }

local DEFAULTS = {
    radius = 20,
    waitTime = 2.0,
}

local MAX_POINT_ATTEMPTS = 10
local GROUND_RAY_START_HEIGHT = 50
local GROUND_RAY_DISTANCE = 100
local GROUND_OFFSET = 3

function Wander.new(puppet, config)
    local self = setmetatable({}, Wander)
    self._puppet = puppet

    self._origin = config.origin or puppet.RootPart.Position
    self._radius = config.radius or DEFAULTS.radius
    self._waitTime = config.waitTime or DEFAULTS.waitTime
    self._waiting = false
    self._waitElapsed = 0

    self.Movement = nil
    self._reachedConn = nil
    self._stuckConn = nil

    return self
end

function Wander:Init()
    self._reachedConn = self.Movement.ReachedDestination:Connect(function()
        self._waiting = true
        self._waitElapsed = 0
    end)

    self._stuckConn = self.Movement.Stuck:Connect(function()
        self:_pickRandomPoint()
    end)

    self:_pickRandomPoint()
end

function Wander:Update(dt)
    if self._waiting then
        self._waitElapsed += dt
        if self._waitElapsed >= self._waitTime then
            self._waiting = false
            self._waitElapsed = 0
            self:_pickRandomPoint()
        end
        return
    end

    if not self.Movement:IsMoving() and not self._waiting then
        self:_pickRandomPoint()
    end
end

function Wander:Destroy()
    if self._reachedConn then self._reachedConn:Disconnect() end
    if self._stuckConn then self._stuckConn:Disconnect() end
    self.Movement:Stop()
end

function Wander:_pickRandomPoint()
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { self._puppet.Model }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    for _ = 1, MAX_POINT_ATTEMPTS do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * self._radius
        local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
        local candidate = self._origin + offset

        -- Ground raycast to validate the point
        local ground = workspace:Raycast(
            candidate + Vector3.new(0, GROUND_RAY_START_HEIGHT, 0),
            Vector3.new(0, -GROUND_RAY_DISTANCE, 0),
            rayParams
        )

        if ground then
            local target = ground.Position + Vector3.new(0, GROUND_OFFSET, 0)
            if self.Movement:WalkTo(target) then
                return
            end
        end
    end

    -- Fallback: walk back to origin
    self.Movement:WalkTo(self._origin)
end

return Wander
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Wander.luau
git commit -m "feat: add Wander component with ground validation"
```

---

### Task 13: Follow Component

**Files:**
- Create: `src/Puppet/Components/Follow.luau`

- [ ] **Step 1: Write Follow component**

`src/Puppet/Components/Follow.luau`:
```lua
-- Follow: follows a target Model, maintaining a specified distance.
-- Handles target destruction gracefully.

local Follow = {}
Follow.__index = Follow

Follow.Name = "Follow"
Follow.Type = "Action"
Follow.Requires = { "Movement" }

local DEFAULTS = {
    distance = 8,
}

local REPATH_THRESHOLD = 3

function Follow.new(puppet, config)
    local self = setmetatable({}, Follow)
    self._puppet = puppet

    assert(config.target and typeof(config.target) == "Instance" and config.target:IsA("Model"),
        "[Puppet:Follow] Config must include 'target' (a Model)")

    self._target = config.target
    self._distance = config.distance or DEFAULTS.distance
    self._lastTargetPosition = nil

    self.Movement = nil
    self._destroyConn = nil

    return self
end

function Follow:Init()
    -- Auto-clear action if target is destroyed
    self._destroyConn = self._target.Destroying:Connect(function()
        self._puppet:ClearAction()
    end)
end

function Follow:Update(dt)
    local target = self._target
    if not target or not target.Parent then
        self._puppet:ClearAction()
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not targetRoot:IsA("BasePart") then return end

    local targetPos = targetRoot.Position
    local selfPos = self._puppet.RootPart.Position
    local distance = (selfPos - targetPos).Magnitude

    -- Close enough — stop
    if distance <= self._distance then
        if self.Movement:IsMoving() then
            self.Movement:Stop()
        end
        return
    end

    -- Only repath if target moved significantly or we stopped
    local shouldRepath = not self._lastTargetPosition
        or (targetPos - self._lastTargetPosition).Magnitude > REPATH_THRESHOLD
        or not self.Movement:IsMoving()

    if shouldRepath then
        local direction = (targetPos - selfPos).Unit
        local goalPos = targetPos - direction * self._distance
        self.Movement:WalkTo(goalPos)
        self._lastTargetPosition = targetPos
    end
end

function Follow:Destroy()
    if self._destroyConn then
        self._destroyConn:Disconnect()
    end
    self.Movement:Stop()
end

return Follow
```

- [ ] **Step 2: Commit**

```bash
git add src/Puppet/Components/Follow.luau
git commit -m "feat: add Follow component with target destruction handling"
```

---

### Task 14: Integration Test

**Files:**
- Create: `test/PuppetTest.server.luau`

- [ ] **Step 1: Write integration test script**

`test/PuppetTest.server.luau`:
```lua
-- Integration test for Puppet system.
-- Run in Roblox Studio (Play mode). Spawns NPCs and exercises all features.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Puppet = require(game.ServerScriptService.Puppet)

local PASS = 0
local FAIL = 0

local function log(msg)
    print("[PuppetTest] " .. msg)
end

local function check(condition, name)
    if condition then
        PASS += 1
        log("PASS: " .. name)
    else
        FAIL += 1
        warn("[PuppetTest] FAIL: " .. name)
    end
end

local function createDummy(name, position)
    local desc = Instance.new("HumanoidDescription")
    local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
    model.Name = name
    model:PivotTo(CFrame.new(position))
    model.Parent = workspace
    return model
end

-- ── Test: Basic Construction ──────────────────────────────────────────────

log("=== Basic Construction ===")

local model1 = createDummy("TestNPC_1", Vector3.new(0, 5, 0))
local npc1 = Puppet.new(model1, {
    movement = { walkSpeed = 16 },
})

check(npc1 ~= nil, "Puppet.new returns a puppet")
check(npc1.Model == model1, "puppet.Model is set")
check(npc1.Humanoid ~= nil, "puppet.Humanoid is set")
check(npc1.RootPart ~= nil, "puppet.RootPart is set")
check(npc1:HasComponent("Movement"), "Movement component added via config")
check(not npc1:HasComponent("Perception"), "Perception not added (not in config)")
check(npc1:GetAction() == nil, "No action by default")

-- ── Test: Duplicate Prevention ────────────────────────────────────────────

log("=== Duplicate Prevention ===")

local dupOk = pcall(function()
    Puppet.new(model1, {})
end)
check(not dupOk, "Cannot create duplicate Puppet for same Model")

-- ── Test: Action Management ───────────────────────────────────────────────

log("=== Action Management ===")

npc1:SetAction("Idle")
check(npc1:GetAction() ~= nil, "SetAction sets an action")
check(npc1:GetAction().Name == "Idle", "Action is Idle")

npc1:ClearAction()
check(npc1:GetAction() == nil, "ClearAction removes action")

-- ── Test: Component Type Enforcement ──────────────────────────────────────

log("=== Type Enforcement ===")

local addActionOk = true
npc1:AddComponent("Patrol", { points = { Vector3.new(0, 0, 0) } })
-- This should warn, not error — Patrol is an Action
check(not npc1:HasComponent("Patrol"), "AddComponent rejects Action types")

-- ── Test: Dependency Protection ───────────────────────────────────────────

log("=== Dependency Protection ===")

npc1:SetAction("Patrol", {
    points = { Vector3.new(0, 5, 0), Vector3.new(20, 5, 0) },
})
check(npc1:GetAction().Name == "Patrol", "Patrol action set")

local removeOk = pcall(function()
    npc1:RemoveComponent("Movement")
end)
check(not removeOk, "Cannot remove Movement while Patrol depends on it")
check(npc1:HasComponent("Movement"), "Movement still exists after failed remove")

-- ── Test: Full NPC with Patrol ────────────────────────────────────────────

log("=== Full Patrol NPC ===")

local model2 = createDummy("TestNPC_Patrol", Vector3.new(30, 5, 0))
local npc2 = Puppet.new(model2, {
    movement = { walkSpeed = 14 },
    perception = { visionRange = 50, visionAngle = 140 },
    patrol = {
        points = {
            Vector3.new(30, 5, 0),
            Vector3.new(50, 5, 0),
            Vector3.new(50, 5, 20),
            Vector3.new(30, 5, 20),
        },
        waitTime = 1.0,
    },
})

check(npc2:HasComponent("Movement"), "NPC2 has Movement")
check(npc2:HasComponent("Perception"), "NPC2 has Perception")
check(npc2:GetAction().Name == "Patrol", "NPC2 action is Patrol")

-- ── Test: Action Swap ─────────────────────────────────────────────────────

log("=== Action Swap ===")

npc2:SetAction("Wander", {
    origin = Vector3.new(30, 5, 0),
    radius = 15,
})
check(npc2:GetAction().Name == "Wander", "Swapped to Wander")

npc2:SetAction("Idle")
check(npc2:GetAction().Name == "Idle", "Swapped to Idle")

-- ── Test: Signals ─────────────────────────────────────────────────────────

log("=== Signals ===")

local addedSignalFired = false
local removedSignalFired = false

npc2.ComponentAdded:Connect(function(name)
    if name == "Perception" then addedSignalFired = true end
end)
npc2.ComponentRemoved:Connect(function(name)
    if name == "Perception" then removedSignalFired = true end
end)

npc2:RemoveComponent("Perception")
task.wait(0.1) -- Signals fire via task.spawn
check(removedSignalFired, "ComponentRemoved signal fired")

npc2:AddComponent("Perception", { visionRange = 100 })
task.wait(0.1)
check(addedSignalFired, "ComponentAdded signal fired")

-- ── Test: Reconfigure ─────────────────────────────────────────────────────

log("=== Reconfigure ===")

npc2:Reconfigure({
    movement = { walkSpeed = 22, runSpeed = 36 },
    follow = { target = model1, distance = 5 },
})
check(npc2:HasComponent("Movement"), "Movement survived Reconfigure")
check(not npc2:HasComponent("Perception"), "Perception removed by Reconfigure")
check(npc2:GetAction().Name == "Follow", "Action changed to Follow")

-- ── Test: Destroy ─────────────────────────────────────────────────────────

log("=== Destroy ===")

local destroyedFired = false
npc1.Destroyed:Connect(function()
    destroyedFired = true
end)

npc1:Destroy()
task.wait(0.1)
check(destroyedFired, "Destroyed signal fired")

local recreateOk = pcall(function()
    Puppet.new(model1, { movement = {} })
end)
check(recreateOk, "Can create new Puppet after Destroy")

-- ── Test: Model Destruction Auto-Cleanup ──────────────────────────────────

log("=== Model Destruction ===")

local model3 = createDummy("TestNPC_AutoClean", Vector3.new(60, 5, 0))
local npc3 = Puppet.new(model3, { movement = {} })
local autoDestroyFired = false
npc3.Destroyed:Connect(function()
    autoDestroyFired = true
end)

model3:Destroy()
task.wait(0.1)
check(autoDestroyFired, "Puppet auto-destroyed when Model destroyed")

-- ── Test: Perception Threat Signals ───────────────────────────────────────

log("=== Perception Signals (manual verification) ===")

-- Tag players for perception
local function tagPlayer(character)
    CollectionService:AddTag(character, "Player")
end

for _, player in Players:GetPlayers() do
    if player.Character then tagPlayer(player.Character) end
    player.CharacterAdded:Connect(tagPlayer)
end
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(tagPlayer)
    if player.Character then tagPlayer(player.Character) end
end)

local model4 = createDummy("TestNPC_Perception", Vector3.new(0, 5, 30))
local npc4 = Puppet.new(model4, {
    movement = { walkSpeed = 14 },
    perception = { visionRange = 50, visionAngle = 180, threatTags = { "Player" } },
    patrol = {
        points = {
            Vector3.new(0, 5, 30),
            Vector3.new(20, 5, 30),
            Vector3.new(20, 5, 50),
            Vector3.new(0, 5, 50),
        },
    },
})

local perception = npc4:GetComponent("Perception")
perception.ThreatSpotted:Connect(function(target)
    log("ThreatSpotted: " .. target.Name .. " — walk near TestNPC_Perception to trigger")
end)
perception.ThreatLost:Connect(function(target)
    log("ThreatLost: " .. target.Name)
end)

-- ── Summary ───────────────────────────────────────────────────────────────

log(string.format("=== Results: %d passed, %d failed ===", PASS, FAIL))
```

- [ ] **Step 2: Verify in Studio**

1. Run `rojo serve` in the project directory.
2. Connect Roblox Studio to the Rojo server.
3. Press Play in Studio.
4. Check the Output window for test results.
5. Walk near `TestNPC_Perception` to verify ThreatSpotted/ThreatLost signals.
6. Observe `TestNPC_Patrol` patrolling between its points.

Expected: All automated checks show PASS. Patrol NPC visibly walks between waypoints.

- [ ] **Step 3: Commit**

```bash
git add test/PuppetTest.server.luau
git commit -m "feat: add integration test script"
```

- [ ] **Step 4: Final commit with all files**

```bash
git add -A
git commit -m "feat: Puppet v1.0 — composition-based NPC system"
```
