--[[
	Custom types for Puppet
	- Provides intellisense for modules with public api

	Note: When adding custom components under the Components folder,
		  declare custom types here.
]]

local Signal = require(script.Parent.Packages.Signal)

type Signal = Signal.Signal<any>

export type Movement = {
	WalkTo: (self: Movement, position: Vector3) -> boolean,
	Stop: (self: Movement) -> (),
	IsMoving: (self: Movement) -> boolean,
	IsStuck: (self: Movement) -> boolean,
	SetConfig: (self: Movement, config: {
		walkSpeed: number?,
		runSpeed: number?,
		arrivalRadius: number?,
	}) -> (),
	ReachedDestination: Signal,
	Stuck: Signal,
}

export type Perception = {
	CanSee: (self: Perception, target: Model, overrideAngle: number?) -> boolean,
	CanHear: (self: Perception, position: Vector3) -> boolean,
	GetVisibleThreats: (self: Perception) -> { Model },
	SetConfig: (self: Perception, config: {
		visionRange: number?,
		visionAngle: number?,
		hearingRange: number?,
		perceptionInterval: number?,
		threatTags: { string }?,
		maxChecks: number?,
		trackingAngle: number?,
	}) -> (),
	ThreatSpotted: Signal,
	ThreatLost: Signal,
}

export type PuppetObject = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,

	AddComponent: (self: PuppetObject, name: string, config: { [string]: any }?) -> (),
	RemoveComponent: (self: PuppetObject, name: string) -> (),
	GetComponent: (self: PuppetObject, name: string) -> any?,
	HasComponent: (self: PuppetObject, name: string) -> boolean,
	SetAction: (self: PuppetObject, name: string, config: { [string]: any }?) -> (),
	GetAction: (self: PuppetObject) -> any?,
	ClearAction: (self: PuppetObject) -> (),
	Reconfigure: (self: PuppetObject, config: { [string]: any }) -> (),
	Destroy: (self: PuppetObject) -> (),

	ComponentAdded: Signal,
	ComponentRemoved: Signal,
	ActionChanged: Signal,
	Destroyed: Signal,
}

return {}
