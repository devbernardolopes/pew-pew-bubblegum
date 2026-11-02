class_name FoeBrain
extends Node
## Moves its parent [Entity] along an entry [Curve2D] and then into a
## [Marker2D] formation slot; it also flies a dive curve on request.
## It is not an [EntityController]: it owns the Entity's position and rotation
## outright, which is why the Entity has no controller child.

## Emitted once the foe has settled into its formation slot.
signal entered_formation
## Emitted when a dive starts.
signal dive_started
## Emitted when a dive ends, right before the foe flies back to its slot.
signal dive_finished

## WAITING for the entry delay, ENTERING along the curve, SETTLING into the
## slot, FORMATION for the rest of its life, or DIVING along a dive curve.
enum State { WAITING, ENTERING, SETTLING, FORMATION, DIVING }

## How close the foe must be to its slot to snap into it, in pixels.
const SNAP_DISTANCE: float = 1.0
## How close the foe's rotation must be to facing down to snap into the slot,
## in radians.
const SNAP_ANGLE: float = 0.05
## Height above the screen where a returning foe reappears, in pixels.
const REENTRY_Y: float = -64.0

## How fast the foe turns towards its formation heading, in radians per second.
@export var turn_rate: float = 8.0
## Multiplier applied to the foe's speed while diving.
@export var dive_speed_multiplier: float = 1.5
## Score multiplier applied while diving.
const DIVE_SCORE_MULTIPLIER: int = 2

var state: State = State.WAITING

var _entity: Entity = null
var _curve: Curve2D = null
var _dive_curve: Curve2D = null
var _slot: Marker2D = null
var _xform: Transform2D = Transform2D.IDENTITY
var _dive_xform: Transform2D = Transform2D.IDENTITY
var _entry_delay: float = 0.0
var _distance: float = 0.0


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("FoeBrain must be a child of an Entity; processing disabled.")
		set_physics_process(false)
		return
	add_to_group(&"foe_brains")


func _physics_process(delta: float) -> void:
	if _entity == null or _entity.data == null:
		return
	match state:
		State.WAITING:
			_process_waiting(delta)
		State.ENTERING:
			_process_entering(delta)
		State.SETTLING:
			_process_settling(delta)
		State.FORMATION:
			_process_formation()
		State.DIVING:
			_process_diving(delta)


## Sends the foe along [param curve] and then into [param slot].
## The foe is placed at the start of the path right away, so it waits off-screen.
## [param entry_delay] is in seconds; the foe starts moving once it reaches zero.
func setup(curve: Curve2D, mirror: bool, slot: Marker2D, entry_delay: float) -> void:
	_curve = curve
	_slot = slot
	_entry_delay = entry_delay
	_distance = 0.0
	_xform = Transform2D.IDENTITY
	state = State.WAITING
	if _entity == null:
		return
	if _slot == null:
		push_error("FoeBrain.setup(): slot is null, the foe will wait forever.")
		return
	if _curve == null:
		push_error("FoeBrain.setup(): curve is null, settling into the slot directly.")
		state = State.SETTLING
		return
	if mirror:
		var viewport_width: float = Helpers.get_game_width()
		_xform = Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(viewport_width, 0))
	_entity.global_position = _xform * _curve.sample_baked(0.0, true)


## Starts a dive along [param curve], anchored at the foe's current position.
## Returns false, and does nothing, unless the foe is in FORMATION.
func dive(curve: Curve2D, mirror: bool) -> bool:
	if state != State.FORMATION or curve == null or _slot == null or _entity == null:
		return false
	var origin: Vector2 = _entity.global_position
	var side: float = -1.0 if mirror else 1.0
	var p0: Vector2 = curve.sample_baked(0.0, true)
	_dive_xform = Transform2D(Vector2(side, 0.0), Vector2(0.0, 1.0), origin - Vector2(side * p0.x, p0.y))
	_dive_curve = curve
	_distance = 0.0
	_warn_if_dive_ends_on_screen()
	state = State.DIVING
	_entity.score_multiplier = DIVE_SCORE_MULTIPLIER
	dive_started.emit()
	return true


func _process_waiting(delta: float) -> void:
	if _slot == null:
		return
	_entry_delay -= delta
	if _entry_delay > 0.0:
		return
	_distance = 0.0
	state = State.ENTERING


func _process_entering(delta: float) -> void:
	if _follow_curve(_curve, _xform, _get_speed(), delta):
		state = State.SETTLING


func _process_settling(delta: float) -> void:
	if not is_instance_valid(_slot):
		# The formation slot was rebuilt (e.g., new wave started); snap to current position and settle.
		state = State.FORMATION
		entered_formation.emit()
		return
	var speed: float = _get_speed()
	_entity.global_position = _entity.global_position.move_toward(_slot.global_position, speed * delta)
	_entity.rotation = lerp_angle(_entity.rotation, PI, 1.0 - exp(-turn_rate * delta))
	var is_on_slot: bool = _entity.global_position.distance_to(_slot.global_position) < SNAP_DISTANCE
	var is_facing_down: bool = absf(angle_difference(_entity.rotation, PI)) < SNAP_ANGLE
	if is_on_slot and is_facing_down:
		_entity.global_position = _slot.global_position
		_entity.rotation = PI
		state = State.FORMATION
		entered_formation.emit()


func _process_formation() -> void:
	if is_instance_valid(_slot):
		_entity.global_position = _slot.global_position
		_entity.rotation = PI


func _process_diving(delta: float) -> void:
	var speed: float = _get_speed() * dive_speed_multiplier
	if not _follow_curve(_dive_curve, _dive_xform, speed, delta):
		return
	# The foe is off-screen both before and after the teleport, so snapping the
	# rotation causes no visible pop.
	_entity.global_position = Vector2(_slot.global_position.x if is_instance_valid(_slot) else _entity.global_position.x, REENTRY_Y)
	_entity.rotation = PI
	_entity.score_multiplier = 1
	state = State.SETTLING
	dive_finished.emit()


## Advances the foe along [param curve] by [param speed] * [param delta] and
## faces it along its heading. Returns true once the end of the curve is reached.
func _follow_curve(curve: Curve2D, xform: Transform2D, speed: float, delta: float) -> bool:
	_distance += speed * delta
	var length: float = curve.get_baked_length()
	var d: float = minf(_distance, length)
	var pos: Vector2 = xform * curve.sample_baked(d, true)
	var ahead: Vector2 = xform * curve.sample_baked(minf(d + 4.0, length), true)
	_entity.global_position = pos
	# Transforming the samples before subtracting keeps the heading right when
	# the path is mirrored. At the end of the curve ahead == pos, so the last
	# rotation is kept on purpose.
	var heading: Vector2 = ahead - pos
	if heading.length_squared() > 0.0001:
		_entity.rotation = heading.angle() + PI / 2.0
	return _distance >= length


func _warn_if_dive_ends_on_screen() -> void:
	var end: Vector2 = _dive_xform * _dive_curve.sample_baked(_dive_curve.get_baked_length(), true)
	# The editor viewport is not the game viewport, so read the project setting.
	#var bottom: float = get_viewport().get_visible_rect().size.y
	var bottom: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_height"))

	if end.y < bottom + Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux:
		push_warning("FoeBrain.dive(): the dive curve ends too high (", 
				end.y, "), the foe will pop back above the screen (", bottom, ").")


func _get_speed() -> float:
	return _entity.data.base_speed * _entity.speed_multiplier
