# Puppet

A composition-based NPC framework for Roblox.

Puppet is an NPC framework where at its base, provides the basic capabilities that most NPCs share — movement, pathfinding, perception, patrol, wander and follow. You compose behaviors from these components and orchestrate them to fit your game's specific needs.

---

## What does it solve?

- **Avoids god scripts and hardcoding.** Instead of writing one massive script per NPC type and hardcoding logic between them, you reuse preset behaviors and swap them out depending on what the NPC needs to do.
- **Doesn't tightly couple your game logic into the NPC system.** Many frameworks couple decision-making into the NPC itself. These systems work well, but they require the user to account for every possible path and combination of actions an NPC might take. Puppet takes a different approach by practicing IoC — it provides tools but never makes game decisions - your game script handles that.


---

## How it works

The framework separates behavior components into two types — **Core** and **Action**.

**Core** components are foundational capabilities like movement and perception — they're stackable, meaning an NPC can have multiple core components active at the same time.

**Action** components are task-driven behaviors like patrolling or following a target — only one can be active at a time.

### Components

Puppet already covers the common behavioral components most NPCs might need:

| Component | Type | What it does |
|-----------|------|-------------|
| **Movement** | <span class="type-badge type-core">CORE</span> | Pathfinding, WalkTo, stuck detection |
| **Perception** | <span class="type-badge type-core">CORE</span> | Vision cone, threat tracking, hearing |
| **Patrol** | <span class="type-badge type-action">ACTION</span> | Loops through waypoints |
| **Wander** | <span class="type-badge type-action">ACTION</span> | Picks random points in a radius |
| **Follow** | <span class="type-badge type-action">ACTION</span> | Tails a target model |
| **Idle** | <span class="type-badge type-action">ACTION</span> | Does nothing (placeholder action) |

Components can declare dependencies and automatically inject them. Patrol, Wander and Follow all require Movement — they use it to move the NPC. Components communicate through [Signals](https://sleitnick.github.io/RbxUtil/api/Signal/) — your code listens and decides what to do.

### Centralized updates

All NPCs share a single `RunService.Heartbeat` connection running at 30hz (configurable via `Puppet.setTickRate`). No per-NPC connections. Component updates are wrapped in `pcall` so one broken NPC can't crash others.

---

## Quick start

```lua
local Puppet = require(path.to.Puppet)

-- Create an NPC from any R15/R6 model with a Humanoid
local npc = Puppet.new(npcModel, {
    movement = { walkSpeed = 14 },
    patrol = {
        points = { pointA, pointB, pointC },
        waitTime = 1.5,
    },
})
```

That's it. The NPC patrols between the three points.

Want it to notice intruders? Add perception:

```lua
npc:AddComponent("Perception", { visionRange = 40, threatTags = { "Player" } })
```

Want it to chase them? Swap the action:

```lua
npc:SetAction("Follow", { target = intruder, distance = 5 })
```

