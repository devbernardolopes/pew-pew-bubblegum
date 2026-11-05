class_name Formation
extends Node2D
## An immutable grid of [Marker2D] slots that sways horizontally.
## Foes read the slots every frame instead of being parented to them, so a
## slot never scales or rotates along with a foe.
##
## A [Formation] is built once from its [member data] and never rebuilt while
## its stage runs, so every slot reference stays valid for a foe's whole life.

## The layout to build. It must be assigned before the node enters the tree.
@export var data: FormationData = null

## Number of slots per row, read from [member data].
var columns: int:
	get:
		return data.get_column_count() if data != null else 0

## Number of rows of slots, read from [member data].
var rows: int:
	get:
		return data.get_row_count() if data != null else 0

var _center_x: float = 0.0
var _time: float = 0.0
var _slots: Array[Marker2D] = []


func _ready() -> void:
	_center_x = position.x
	if data == null:
		push_error("Formation: data is null; no slots were created.")
		return
	_create_slots()


func _physics_process(delta: float) -> void:
	if data == null:
		return
	_time += delta
	position.x = _center_x + sin(_time * data.sway_speed) * data.sway_amplitude


## Returns the slot at [param row] and [param col], or [code]null[/code] when
## either index is out of range or the cell is a hole of the layout.
func get_slot(row: int, col: int) -> Marker2D:
	if row < 0 or row >= rows or col < 0 or col >= columns:
		return null
	return _slots[row * columns + col]


## Creates a [Marker2D] at the center of a rectangle of cells, for a boss
## footprint. It is not a slot, so [method get_slot] is unaffected, but it is a
## child of the formation and therefore sways with it.
## Returns null when there is no [member data] or the span is invalid.
func create_anchor(row: int, col: int, row_span: int, col_span: int) -> Marker2D:
	if data == null:
		push_error("Formation.create_anchor(): data is null.")
		return null
	if row_span < 1 or col_span < 1:
		push_error("Formation.create_anchor(): the spans must be at least 1.")
		return null
	var anchor: Marker2D = Marker2D.new()
	anchor.name = "Anchor_%d_%d" % [row, col]
	var half_width: float = data.get_half_width()
	anchor.position = Vector2(
			(float(col) + (float(col_span) - 1.0) / 2.0) * data.spacing.x - half_width,
			(float(row) + (float(row_span) - 1.0) / 2.0) * data.spacing.y)
	add_child(anchor)
	return anchor


func _create_slots() -> void:
	var half_width: float = data.get_half_width()
	for row: int in rows:
		for col: int in columns:
			# Holes keep their place in _slots so the index stays row * columns + col.
			if not data.has_cell(row, col):
				_slots.append(null)
				continue
			var slot: Marker2D = Marker2D.new()
			slot.name = "Slot_%d_%d" % [row, col]
			slot.position = Vector2(col * data.spacing.x - half_width, row * data.spacing.y)
			add_child(slot)
			_slots.append(slot)
