@tool
class_name BossPhaseData
extends Resource
## One health phase of a [BossData]: where the boss moves, how it fires and how
## fast. Phases are listed from full health down and never go back up.

enum FirePattern {
	NONE,
	STRAIGHT,
	AIMED,
	SPREAD,
}

## The phase starts once health / max_health is at or below this value.
## The first phase should be 1.0; phases must be in strictly descending order.
@export_range(0.0, 1.0) var health_below: float = 1.0
## Where the boss goes in this phase, in pixels relative to its home position.
@export var offset: Vector2 = Vector2.ZERO
## Seconds the boss takes to reach the offset.
@export var move_duration: float = 1.0
## How the muzzles fire in this phase.
@export var fire_pattern: FirePattern = FirePattern.STRAIGHT
## Seconds between two volleys.
@export var fire_interval: float = 1.5
## Indices into the boss's Muzzles children that fire in this phase; empty means all.
@export var muzzle_indices: PackedInt32Array = []
## Fire one muzzle per volley, cycling through the active ones, instead of all at once.
@export var alternate_muzzles: bool = false
## SPREAD: bullets per muzzle and the angle they are fanned across, in degrees.
@export_range(1, 9) var spread_count: int = 3
@export_range(0.0, 120.0, 0.5, "suffix:°") var spread_angle_deg: float = 40.0
## AIMED: the largest angle from the muzzle's own direction a shot may turn, in degrees.
@export_range(0.0, 89.0, 0.5, "suffix:°") var aim_cone_deg: float = 60.0
