class_name TractorBeam
extends Area2D
## A tractor beam that grows downward from the muzzle of its parent Entity.
## The visual and collision polygons are scaled by progress; the collision is
## disabled except while fully extended.

signal fully_extended
signal retracted

const CAPTURED_SHIP_COLOR: Color = Color(1.0, 0.3, 0.3, 1.0)

@export var grow_duration: float = 1.0
@export var cone_height: float = 400.0
@export var cone_width: float = 80.0

var _timer: float = 0.0
var _phase: String = "idle"  # idle, extending, extended, holding, retracting, retracted
var _full: bool = false

var _visual: Polygon2D = null
var _collision: CollisionPolygon2D = null


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	monitorable = false
	collision_layer = 0
	collision_mask = PhysicsLayers.FRIEND

	# Position at the muzzle in local space, inheriting the entity's rotation.
	var parent: Entity = get_parent() as Entity
	if parent != null:
		var muzzle_offset: Vector2 = Vector2.ZERO
		for child in parent.get_children():
			if child is Weapon:
				muzzle_offset = (child as Weapon).muzzle_offset
		position = Vector2.UP * Helpers.ENTITY_HALF_WIDTH * parent.scale_aux + muzzle_offset

	_visual = Polygon2D.new()
	_visual.show_behind_parent = true
	if parent != null:
		_visual.color = Color(parent.color.r, parent.color.g, parent.color.b, 0.25)
	else:
		_visual.color = Color(1.0, 1.0, 1.0, 0.25)
	add_child(_visual)

	_collision = CollisionPolygon2D.new()
	_collision.disabled = true
	add_child(_collision)

	_refresh_polygons(0.0)


func extend() -> void:
	_timer = 0.0
	_phase = "extending"
	_full = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func retract() -> void:
	_timer = 0.0
	_phase = "retracting"
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT

func is_fully_extended() -> bool:
	return _phase == "extended" or _phase == "holding"

func is_retracted() -> bool:
	return _phase == "retracted"

## Returns the first overlapping Entity that is a live friend, not dead,
## not already captured, and not auto-descending.
func get_touching_hero() -> Entity:
	if not is_fully_extended():
		return null
	var overlapping: Array[Area2D] = get_overlapping_areas()
	for area: Area2D in overlapping:
		if area is Entity:
			var ent: Entity = area as Entity
			if ent == null or not is_instance_valid(ent):
				continue
			if ent.data == null:
				continue
			if ent.data.team != Helpers.TEAM.FRIEND:
				continue
			if ent.is_dead:
				continue
			if ent.capture_active:
				continue
			if ent.auto_descending:
				continue
			return ent
	return null

func _process(delta: float) -> void:
	if _phase == "idle" or _phase == "retracted":
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	_timer += delta

	if _phase == "extending":
		var progress: float = clampf(_timer / grow_duration, 0.0, 1.0)
		_refresh_polygons(progress)
		if progress >= 1.0:
			_timer = 0.0
			_phase = "extended"
			_full = true
			_collision.disabled = false
			fully_extended.emit()
		return

	if _phase == "retracting":
		var progress: float = 1.0 - clampf(_timer / grow_duration, 0.0, 1.0)
		_refresh_polygons(progress)
		if progress <= 0.0:
			_timer = 0.0
			_phase = "retracted"
			_full = false
			_collision.disabled = true
			visible = false
			process_mode = Node.PROCESS_MODE_DISABLED
			retracted.emit()
		return


func _refresh_polygons(progress: float) -> void:
	var height: float = progress * cone_height
	var top_w: float = 4.0
	var bot_w: float = cone_width * progress
	var polygon_points: PackedVector2Array = [
		Vector2(-top_w / 2.0, 0.0),
		Vector2(top_w / 2.0, 0.0),
		Vector2(bot_w / 2.0, height),
		Vector2(-bot_w / 2.0, height),
	]
	_visual.polygon = polygon_points
	_collision.polygon = polygon_points
