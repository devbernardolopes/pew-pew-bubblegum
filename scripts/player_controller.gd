class_name PlayerController
extends EntityController

## Remaining time of a dash press made without a direction.
var _dash_buffer: float = 0.0
## The Fleet (normal case) or the Entity this controller reads input for.
var _target: Node = null


func _ready() -> void:
	# Read the dash before the owner moves, so a dash and walking never both
	# move the same block on the triggering frame.
	process_physics_priority = -10
	var parent: Node = get_parent()
	if parent is Fleet or parent is Entity:
		_target = parent


func _physics_process(delta: float) -> void:
	if _target == null or get_tree().paused:
		return
	var left: bool = Input.is_action_pressed("left")
	var right: bool = Input.is_action_pressed("right")
	var direction: int = 0
	if left != right:
		direction = -1 if left else 1

	if Input.is_action_just_pressed("dash"):
		if direction != 0:
			_dash_buffer = 0.0
			_try_dash(direction)
		elif not left and not right and _get_dash_input_buffer() > 0.0:
			_dash_buffer = _get_dash_input_buffer()
		else:
			# Both directions held (or buffering disabled): no dash.
			_dash_buffer = 0.0
	elif _dash_buffer > 0.0:
		_dash_buffer = maxf(_dash_buffer - delta, 0.0)
		if direction != 0 and _try_dash(direction):
			_dash_buffer = 0.0


func get_direction_h() -> float:
	return Input.get_axis("left", "right")


func wants_fire() -> bool:
	return Input.is_action_just_pressed("fire")


func _try_dash(direction: int) -> bool:
	var fleet: Fleet = _target as Fleet
	if fleet != null:
		return fleet.try_dash(direction)
	var entity: Entity = _target as Entity
	# A fleet member has a controller in its scene, but the Fleet owns it.
	if entity == null or entity.externally_driven:
		return false
	return entity.try_dash(direction)


func _get_dash_input_buffer() -> float:
	var fleet: Fleet = _target as Fleet
	if fleet != null:
		return fleet.get_dash_input_buffer()
	var entity: Entity = _target as Entity
	if entity == null or entity.externally_driven:
		return 0.0
	return entity.get_dash_input_buffer()
