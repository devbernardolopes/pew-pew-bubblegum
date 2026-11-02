class_name WaveData
extends Resource
## A single wave of foes for a stage.

## The foe scene to spawn (e.g. foe_01.tscn, foe_02.tscn).
@export var foe_scene: PackedScene = null
## The entry curve for this wave.
@export var entry_curve: Curve2D = null
## The formation row this wave fills.
@export var row: int = 0
## Seconds between two foes entering from the same side.
@export var spacing: float = 0.25
## Seconds after the previous wave started before this one begins.
@export var delay: float = 0.0
