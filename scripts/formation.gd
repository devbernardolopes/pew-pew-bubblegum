class_name Formation
extends Node2D
## A grid of [Marker2D] slots that sways horizontally.
## Foes read the slots every frame instead of being parented to them, so a
## slot never scales or rotates along with a foe.

## Peak speed of a slot, in pixels per second. It must stay well below a foe's
## [member EntityData.base_speed], or settling foes can never catch their slot.
const MAX_SLOT_SPEED: float = 128.0

## Number of slots per row.
@export var columns: int = 8
## Number of rows of slots; rows extend downwards from the Formation's origin.
@export var rows: int = 2
## Distance between two neighboring slots, in pixels.
@export var spacing: Vector2 = Vector2(48, 40)
## Width of the horizontal sway, in pixels.
@export var sway_amplitude: float = 40.0
## Angular speed of the sway, in radians per second.
@export var sway_speed: float = 1.2

var _center_x: float = 0.0
var _time: float = 0.0
var _slots: Array[Marker2D] = []


func _ready() -> void:
	_center_x = position.x
	_create_slots()
	if sway_amplitude * sway_speed >= MAX_SLOT_SPEED:
		push_warning("Formation slots are too fast: lowering sway_amplitude or sway_speed lets foes catch them.")


func _physics_process(delta: float) -> void:
	_time += delta
	position.x = _center_x + sin(_time * sway_speed) * sway_amplitude


## Returns the slot at [param row] and [param col], or [code]null[/code] when
## either index is out of range.
func get_slot(row: int, col: int) -> Marker2D:
	if row < 0 or row >= rows or col < 0 or col >= columns:
		return null
	return _slots[row * columns + col]


func _create_slots() -> void:
	var half_width: float = (columns - 1) * spacing.x / 2.0
	for row: int in rows:
		for col: int in columns:
			var slot: Marker2D = Marker2D.new()
			slot.name = "Slot_%d_%d" % [row, col]
			slot.position = Vector2(col * spacing.x - half_width, row * spacing.y)
			add_child(slot)
			_slots.append(slot)
