# Troubleshooting

---

### "A Puppet already exists for this Model"

You're calling `Puppet.new` on a Model that already has a Puppet. Destroy the existing one first:

```lua
-- Wrong: creating a second Puppet on the same Model
Puppet.new(npcModel, { ... })
Puppet.new(npcModel, { ... }) -- errors

-- Right: destroy the old one first
local npc = Puppet.new(npcModel, { ... })
npc:Destroy()
local npc2 = Puppet.new(npcModel, { ... }) -- works
```

---

### NPC doesn't move

**Check the Humanoid.** The Model must have a `Humanoid` and a `HumanoidRootPart`. Verify both exist and the Humanoid's `WalkSpeed` isn't 0.

**Check the position.** If the NPC spawns inside a wall or below the floor, pathfinding can fail. Make sure the spawn position is valid.

**Check for errors.** Movement wraps path computation in `pcall`. Look in the Output window for `[Puppet:Movement]` warnings.

---

### NPC gets stuck

Movement has built-in stuck detection. After 2 seconds of no progress, it retries with a jump + repath. After 3 failed retries, it fires `Movement.Stuck` and stops.

Listen for it:

```lua
local movement = npc:GetComponent("Movement")
movement.Stuck:Connect(function()
    -- teleport back, pick a new destination, etc.
end)
```

---

### Perception doesn't detect players

1. **Are players tagged?** Perception uses `CollectionService` tags. Make sure player characters have the tag you specified in `threatTags`:

```lua
CollectionService:AddTag(character, "Player")
```

2. **Is the NPC facing the target?** Initial detection uses a cone (`visionAngle`). A target behind the NPC won't be detected until it enters the cone. Once spotted, the wider `trackingAngle` keeps them tracked.

3. **Is something blocking line of sight?** Perception raycasts between the NPC and the target. Transparent parts still block if they're `CanCollide = true`.

---

### "Cannot remove X — required by Y"

You're trying to remove a component that another component depends on:

```lua
-- This errors because Patrol requires Movement
npc:RemoveComponent("Movement") -- "required by Patrol"
```

Remove or clear the dependent component/action first:

```lua
npc:ClearAction() -- removes Patrol
npc:RemoveComponent("Movement") -- now safe
```

---

### SetAction during an Update causes deferred behavior

If you call `SetAction`, `ClearAction`, `AddComponent` or `RemoveComponent` while components are being updated (inside an `Update` call), the change is **deferred** — it queues up and applies after the current update cycle finishes.

This is automatic and usually invisible. But if you need a change to apply immediately (like `Reconfigure` for boss phases), use `Reconfigure` — it bypasses deferral.

---

### NPC keeps patrolling/wandering after I call ClearAction

Make sure you're calling it on the right Puppet instance. `ClearAction` destroys the active action and calls `Movement:Stop()`. If the NPC keeps moving, check that:

1. You have the correct reference to the Puppet
2. Nothing else is calling `SetAction` again (like a signal handler)

---

### Memory leaks / NPCs not cleaning up

Puppet auto-destroys when:
- `Model.Destroying` fires
- `Humanoid.Died` fires
- `Humanoid.Health` reaches 0

If you're creating NPCs dynamically, make sure dead models are eventually destroyed. The Puppet cleans itself up, but the Model stays in the workspace unless you remove it:

```lua
npc.Destroyed:Connect(function()
    if model.Parent then model:Destroy() end
end)
```
