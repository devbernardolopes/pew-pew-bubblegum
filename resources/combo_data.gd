class_name ComboData
extends Resource
## A sequence of Input Map actions that fires a weapon when completed.
## [ComboDetector] watches the steps; [member EntityData.combos] holds the
## combos an Entity knows. Tune [member max_step_delay] / [member step_delays]
## by playing with [member EntityData.input_debug] on.

## Identity of this combo, used in debug prints.
@export var id: StringName = &""
## Input Map actions, in order. At least two steps are required.
@export var steps: Array[StringName] = [&"down", &"up", &"fire"]
## Maximum seconds between two consecutive steps.
@export var max_step_delay: float = 0.35
## Optional per-gap override: entry i is the maximum gap before step i + 1.
## Missing entries fall back to [member max_step_delay].
@export var step_delays: PackedFloat32Array = []
## Minimum seconds between two consecutive steps. Zero disables it; a press
## sooner than this after the previous step is ignored, to reject mashing.
@export var min_step_delay: float = 0.0
## When true, any other monitored combo action pressed in between resets
## the combo. [code]left[/code], [code]right[/code] and [code]dash[/code]
## never break a combo.
@export var strict: bool = true
## The weapon fired when the combo completes.
@export var weapon_id: StringName = &"missile"
## Seconds after a completion before this combo can fire again.
@export var cooldown: float = 0.0


## The maximum gap allowed before step [param step_index] (which is at least 1).
func get_gap_before(step_index: int) -> float:
	var gap_index: int = step_index - 1
	if gap_index >= 0 and gap_index < step_delays.size():
		return step_delays[gap_index]
	return max_step_delay
