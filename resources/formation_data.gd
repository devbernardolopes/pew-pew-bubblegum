class_name FormationData
extends Resource
## Layout of an immutable formation grid. Every stage wave that points at the
## same resource shares one [Formation] instance and sways in unison.

## Number of slots per row.
@export_range(1, 32) var columns: int = 8
## Number of rows of slots; rows extend downwards from the formation's origin.
@export var rows: int = 2
## Distance between two neighboring slots, in pixels.
@export var spacing: Vector2 = Vector2(48, 40)
## Width of the horizontal sway, in pixels.
@export var sway_amplitude: float = 40.0
## Angular speed of the sway, in radians per second.
@export var sway_speed: float = 1.2


## Peak horizontal speed of a slot, in pixels per second. It must stay below a
## foe's [member EntityData.base_speed], or settling foes can never catch it.
func get_peak_slot_speed() -> float:
	return sway_amplitude * sway_speed


## Half the width of a row of slots, in pixels, without the sway.
func get_half_width() -> float:
	return (columns - 1) * spacing.x / 2.0
