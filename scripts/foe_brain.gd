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
enum State { WAITING, ENTERING, SETTLING, FORMATION, DIVING, TRACTOR_BEAM }

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
## The dive curves of the wave this foe belongs to; one is picked per dive.
var _dive_curves: Array[Curve2D] = []
var _slot: Marker2D = null
var _xform: Transform2D = Transform2D.IDENTITY
var _dive_xform: Transform2D = Transform2D.IDENTITY
## Whether any foe brain has an active capture, blocking new triggers.
static var _global_capture_active: bool = false

var _entry_delay: float = 0.0
var _distance: float = 0.0
## Whether this brain is currently running the tractor beam.
var _tractor_active: bool = false
## Time since the cone was fully extended.
var _tractor_hold_timer: float = 0.0
## Whether the hero has been captured by this brain.
var _capture_done: bool = false


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("FoeBrain must be a child of an Entity; processing disabled.")
		set_physics_process(false)
		return
	add_to_group(&"foe_brains")
	# Create the tractor cone child; it only becomes visible during the beam.
	var cone_script: GDScript = load("res://scripts/tractor_cone.gd")
	if cone_script != null:
		var cone: Polygon2D = cone_script.new() as Polygon2D
		cone.name = "TractorCone"
		cone.visible = false
		cone.color.a = 0.25
		if _entity != null and _entity.data != null:
			if "tractor_beam_height" in _entity.data:
				cone.cone_height = float(_entity.data.get("tractor_beam_height"))
		add_child(cone)


func _physics_process(delta: float) -> void:
	if _entity == null or _entity.data == null:
		return
	# If the parent entity is being removed (e.g. destroyed), release the global lock.
	if not is_instance_valid(_entity) or _entity.is_queued_for_deletion():
		FoeBrain._global_capture_active = false
		_tractor_active = false
		_capture_done = false
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
		State.TRACTOR_BEAM:
			_process_tractor_beam(delta)


## Sends the foe along [param curve] and then into [param slot].
## The foe is placed at the start of the path right away, so it waits off-screen.
## [param entry_delay] is in seconds; the foe starts moving once it reaches zero.
## [param dive_curves] are the curves of the foe's wave; [method dive] picks one.
## The slot belongs to a formation that lives for the whole stage, so it stays
## valid for the rest of the foe's life.
func setup(curve: Curve2D, mirror: bool, slot: Marker2D, entry_delay: float, dive_curves: Array[Curve2D] = []) -> void:
	_curve = curve
	_slot = slot
	_entry_delay = entry_delay
	_dive_curves = dive_curves
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


## Starts a dive along one of the wave's curves, picked at random, anchored at
## the foe's current position. Returns false, and does nothing, unless the foe
## is in FORMATION and its wave has at least one dive curve.
func dive(mirror: bool) -> bool:
	if state != State.FORMATION or _slot == null or _entity == null:
		return false
	var curve: Curve2D = _pick_dive_curve()
	if curve == null:
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


## Tells whether this foe has anything to dive along, so the [DiveDirector] can
## skip waves that never dive instead of picking a foe that cannot move.
func has_dive_curves() -> bool:
	for curve: Curve2D in _dive_curves:
		if curve != null:
			return true
	return false


## Returns one of the wave's dive curves at random, or null when it has none.
func _pick_dive_curve() -> Curve2D:
	var usable: Array[Curve2D] = []
	for curve: Curve2D in _dive_curves:
		if curve != null:
			usable.append(curve)
	if usable.is_empty():
		return null
	return usable.pick_random()


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
	if not is_instance_valid(_slot):
		return
	_entity.global_position = _slot.global_position
	_entity.rotation = PI


func _process_diving(delta: float) -> void:
	if not is_instance_valid(_slot):
		return
	var speed: float = _get_speed() * dive_speed_multiplier
	# Check for tractor beam trigger at a point along the dive.
	if _entity != null and _entity.data != null and _entity.data.tractor_beam_enabled:
		if not FoeBrain._global_capture_active:
			var total_len: float = _dive_curve.get_baked_length() if _dive_curve != null else 0.0
			if total_len > 0.0 and _distance / total_len > 0.25 and not _tractor_active:
				if randf() < 1.0:
				#if randf() < 0.01:
					var hero: Node = get_tree().get_first_node_in_group("friend")
					#var hero: Node = get_tree().get_first_node_in_group("hero")
					if hero != null and hero is Entity:
						var hero_pos: Vector2 = hero.global_position
						var foe_pos: Vector2 = _entity.global_position
						var vertical_dist: float = hero_pos.y - foe_pos.y
						if vertical_dist > 0.0:
							# Dynamic target: cone bottom (foe_pos + cone_height) reaches hero polygon bottom (hero_pos + 64 * hero.scale_aux)
							var cone_height: float = 400.0
							if _entity != null and _entity.data != null and "tractor_beam_height" in _entity.data:
								cone_height = float(_entity.data.get("tractor_beam_height"))
							var hero_scale: float = hero.scale_aux if hero is Entity else 0.25
							var foe_scale: float = _entity.scale_aux if _entity != null else 0.25
							# Muzzle is at center - 64*scale_aux (+ muzzle_offset.y); cone grows downward from muzzle.
							var muzzle_offset_y: float = 0.0
							if _entity != null:
								for child in _entity.get_children():
									if child is Weapon:
										muzzle_offset_y = child.muzzle_offset.y
							var target_dist: float = cone_height - 64.0 * hero_scale - (64.0 * foe_scale - muzzle_offset_y)
							# Only trigger when vertical distance is near the exact target and the curve still has distance to cover.
							if abs(vertical_dist - target_dist) < 30.0 and (total_len - _distance) > 10.0:
								FoeBrain._global_capture_active = true
								_tractor_active = true
								state = State.TRACTOR_BEAM
	if not _follow_curve(_dive_curve, _dive_xform, speed, delta):
		return
	# The foe is off-screen both before and after the teleport, so snapping the
	# rotation causes no visible pop.
	_entity.global_position = Vector2(_slot.global_position.x, REENTRY_Y)
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


func _process_tractor_beam(delta: float) -> void:
	if not is_instance_valid(_slot):
		return

	# Once capture is done, ride back to formation (like settling).
	if _capture_done:
		_entity.global_position = _entity.global_position.move_toward(
				_slot.global_position, _get_speed() * delta)
		_entity.rotation = lerp_angle(_entity.rotation, PI, 1.0 - exp(-turn_rate * delta))
		var is_on_slot: bool = _entity.global_position.distance_to(_slot.global_position) < SNAP_DISTANCE
		var is_facing_down: bool = absf(angle_difference(_entity.rotation, PI)) < SNAP_ANGLE
		if is_on_slot and is_facing_down:
			_entity.global_position = _slot.global_position
			_entity.rotation = PI
			_capture_done = false
			_tractor_active = false
			_global_capture_active = false
			# The hero entity's capture_active should be cleared by the scene.
		return

	var cone: Polygon2D = get_node_or_null("TractorCone") as Polygon2D
	if cone == null:
		return

	# Foe holds straight down; position stays at current dive point.
	_entity.rotation = PI

	if not _tractor_active:
		_tractor_active = true
		_tractor_hold_timer = 0.0

	# Only capture once the cone has fully grown.
	if cone.is_full():
		_tractor_hold_timer += delta
		var duration: float = 3.0
		if _entity != null and _entity.data != null and "tractor_beam_open_duration" in _entity.data:
			duration = float(_entity.data.get("tractor_beam_open_duration"))

		# Check hero overlap when the cone is fully extended.
		var hero_nodes: Array = get_tree().get_nodes_in_group("hero")
		if not hero_nodes.is_empty():
			var hero_node: Node = hero_nodes[0]
			if is_instance_valid(hero_node) and hero_node is Entity:
				var hero_entity: Entity = hero_node as Entity
				if not hero_entity.is_dead and not hero_entity.is_queued_for_deletion() and not hero_entity.capture_active:
					var dx: float = absf(hero_entity.global_position.x - _entity.global_position.x)
					var dy: float = hero_entity.global_position.y - _entity.global_position.y
					if dy > 10.0 and dx < 50.0 and dy < 500.0:
						# Capture succeeded. The hero freezes and loses one life.
						_capture_done = true
						_global_capture_active = false
						if is_instance_valid(hero_entity):
							hero_entity.capture_active = true
						# Play capture sound if assigned.
						var audio_player: AudioStreamPlayer = get_node_or_null("TractorAudio") as AudioStreamPlayer
						if audio_player != null and _entity.data != null and _entity.data.sound_profile != null:
							var profile: SoundProfile = _entity.data.sound_profile
							if profile.tractor_beam_capture != null:
								audio_player.stream = profile.tractor_beam_capture
								audio_player.play()
						GameManager.use_reserve_ship()

			# Hero no longer valid; abort the beam.
			var hero_dead_or_gone: bool = false
			if hero_nodes.is_empty() or not is_instance_valid(hero_node):
				hero_dead_or_gone = true
			elif hero_node is Entity:
				var ent: Entity = hero_node as Entity
				if ent.is_queued_for_deletion() or ent.is_dead:
					hero_dead_or_gone = true
			if hero_dead_or_gone:
				_capture_done = false
				_tractor_active = false
				_global_capture_active = false

		# Retract / end the beam after the set open duration.
		if _tractor_hold_timer >= duration and not _capture_done:
			_capture_done = false
			_tractor_active = false
			_global_capture_active = false
			# Return to formation after abort.
			state = State.SETTLING


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
