class_name FoeBrain
extends Node
## Moves its parent [Entity] along an entry [Curve2D] and then into a
## [Marker2D] formation slot; it also flies a dive curve on request.
## It is not an [EntityController]: it owns the Entity's position and rotation
## outright, which is why the Entity has no controller child.

signal entered_formation
signal dive_started
signal dive_finished

enum State { WAITING, ENTERING, SETTLING, FORMATION, DIVING, TRACTOR_BEAM }

## Inner phases of the tractor beam sequence.
enum BeamPhase { TURNING, EXTENDING, HOLDING, ALIGNING, PULLING, RETRACTING }

## Whether the captured ship has been committed (life lost) or is only pending.
enum Carry { NONE, PENDING, COMMITTED }

const EffectsScript = preload("res://scripts/effects/effects.gd")
const SNAP_DISTANCE: float = 1.0
const SNAP_ANGLE: float = 0.05
const REENTRY_Y: float = -64.0

@export var turn_rate: float = 8.0
@export var dive_speed_multiplier: float = 1.5
const DIVE_SCORE_MULTIPLIER: int = 2

var state: State = State.WAITING

var _entity: Entity = null
var _curve: Curve2D = null
var _dive_curve: Curve2D = null
var _dive_curves: Array[Curve2D] = []
var _slot: Marker2D = null
var _xform: Transform2D = Transform2D.IDENTITY
var _dive_xform: Transform2D = Transform2D.IDENTITY

## The brain controlling an active capture; null means none in progress.
static var _capturer: FoeBrain = null

var _entry_delay: float = 0.0
var _distance: float = 0.0

## Whether a tractor dive was planned at dive start.
var _beam_planned: bool = false
## Active beam phase (only meaningful when state == TRACTOR_BEAM).
var _beam_phase: BeamPhase = BeamPhase.TURNING
## Carry state: NONE when not carrying; PENDING while pulling/back; COMMITTED after formation.
var _carry: Carry = Carry.NONE
## The captured hero entity.
var _captured_hero: Entity = null
## The tractor beam node (child of the parent Entity).
var _beam: TractorBeam = null
## Timer for the current beam sub-phase.
var _beam_timer: float = 0.0
## Rider visual: a red-tinted polygon showing the captured hero docked on the foe.
var _rider: Polygon2D = null
## The scale of the hero at capture time, used for rider positioning after the hero is freed.
var _rider_hero_scale: float = 0.25
## Cached y of the Weapon muzzle in entity space; NAN until it is looked up.
var _muzzle_offset_y: float = NAN


static func is_capture_in_progress() -> bool:
	return is_instance_valid(_capturer)


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("FoeBrain must be a child of an Entity; processing disabled.")
		set_physics_process(false)
		return
	add_to_group(&"foe_brains")

	# Create the tractor beam only when enabled.
	if _entity != null and _entity.data != null and _entity.data.tractor_beam_enabled:
		_beam = preload("res://scripts/tractor_beam.gd").new() as TractorBeam
		_beam.name = "TractorBeam"
		_beam.visible = false
		if _entity.data != null:
			_beam.grow_duration = float(_entity.data.tractor_beam_grow_duration)
			_beam.cone_height = float(_entity.data.tractor_beam_height)
			_beam.cone_width = float(_entity.data.tractor_beam_width)
		_entity.add_child.call_deferred(_beam)
		_beam.fully_extended.connect(_on_beam_fully_extended)
		_beam.retracted.connect(_on_beam_retracted)

	# Connect to parent entity's death so we can release the hero.
	if _entity != null:
		_entity.died.connect(_on_entity_died)


func _physics_process(delta: float) -> void:
	if _entity == null or _entity.data == null:
		return
	if not is_instance_valid(_entity) or _entity.is_queued_for_deletion():
		if _capturer == self:
			_capturer = null
		return

	# Update rider position whenever we are carrying.
	if _carry != Carry.NONE:
		if _rider != null:
			var hero_scale: float = _rider_hero_scale
			var foe_scale: float = _entity.scale_aux
			var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
			_rider.global_position = _entity.to_global(Vector2(0.0, d))
			_rider.rotation = _entity.rotation + PI

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


## Like [method setup] for a foe that already is where it should start: it goes
## straight to [code]SETTLING[/code] towards [param slot] without a curve and
## without the null-curve [method push_error]. Used for boss pieces, which spawn
## inside their parent's shape and fly to their anchors.
func setup_settle(slot: Marker2D) -> void:
	_curve = null
	_slot = slot
	_entry_delay = 0.0
	_dive_curves = []
	_distance = 0.0
	_xform = Transform2D.IDENTITY
	state = State.WAITING
	if _entity == null:
		return
	if _slot == null:
		push_error("FoeBrain.setup_settle(): slot is null, the foe will wait forever.")
		return
	state = State.SETTLING


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

	# Plan the beam at dive start.
	_beam_planned = false
	if _entity != null and _entity.data != null and _entity.data.tractor_beam_enabled:
		if _can_start_beam():
			_beam_planned = randf() < float(_entity.data.tractor_beam_chance)

	_warn_if_dive_ends_on_screen()
	state = State.DIVING
	_entity.score_multiplier = DIVE_SCORE_MULTIPLIER
	dive_started.emit()
	return true


func has_dive_curves() -> bool:
	for curve: Curve2D in _dive_curves:
		if curve != null:
			return true
	return false


func _pick_dive_curve() -> Curve2D:
	var usable: Array[Curve2D] = []
	for curve: Curve2D in _dive_curves:
		if curve != null:
			usable.append(curve)
	if usable.is_empty():
		return null
	return usable.pick_random()


func _fleet_allows_capture() -> bool:
	var fleet: Fleet = get_tree().get_first_node_in_group(&"fleet") as Fleet
	if fleet == null:
		return true
	return fleet.allows_capture()


func _can_start_beam() -> bool:
	if is_capture_in_progress():
		return false
	if _carry != Carry.NONE:
		return false
	if not _fleet_allows_capture():
		return false
	# The hero must exist and be capturable.
	return _get_capturable_hero() != null


## Returns the first hero the beam may capture, or null when none is available.
func _get_capturable_hero() -> Entity:
	for node: Node in get_tree().get_nodes_in_group(&"friend"):
		var hero: Entity = node as Entity
		if hero == null or not is_instance_valid(hero):
			continue
		if hero.is_capturable():
			return hero
	return null


func _start_beam() -> void:
	if is_capture_in_progress():
		return
	_beam_planned = false
	_capturer = self
	_beam_phase = BeamPhase.TURNING
	_beam_timer = 0.0
	_entity.score_multiplier = 1
	dive_finished.emit()
	state = State.TRACTOR_BEAM


func _on_beam_fully_extended() -> void:
	if state == State.TRACTOR_BEAM and _beam_phase == BeamPhase.EXTENDING:
		_beam_timer = 0.0
		_beam_phase = BeamPhase.HOLDING


func _on_beam_retracted() -> void:
	if state == State.TRACTOR_BEAM and _beam_phase == BeamPhase.RETRACTING:
		_beam_timer = 0.0
		_beam_phase = BeamPhase.RETRACTING  # finished retracting
		# After retract, either go to formation (if committed) or to settling (if no capture).
		if _carry == Carry.PENDING:
			# Hero was captured; now pulling and retracting. Actually retracting happens after pulling.
			# The phase transition from PULLING -> RETRACTING happens when pull is done.
			pass


func _process_beam(delta: float) -> void:
	if _entity == null:
		return

	# Phase: TURNING
	if _beam_phase == BeamPhase.TURNING:
		_entity.rotation = lerp_angle(_entity.rotation, PI, 1.0 - exp(-turn_rate * delta))
		if absf(angle_difference(_entity.rotation, PI)) < SNAP_ANGLE:
			_entity.rotation = PI
			_beam_phase = BeamPhase.EXTENDING
			if _entity != null and _entity.data != null and _entity.data.sound_profile != null:
				_entity.play_sound("tractor_beam_grow")
			if _beam != null:
				_beam.extend()
		return

	# Phase: EXTENDING
	if _beam_phase == BeamPhase.EXTENDING:
		# While extending, keep facing down.
		_entity.rotation = PI
		if not _fleet_allows_capture():
			if _beam != null:
				_beam.retract()
			_beam_timer = 0.0
			_beam_phase = BeamPhase.RETRACTING
		return

	# Phase: HOLDING
	if _beam_phase == BeamPhase.HOLDING:
		_entity.rotation = PI
		_beam_timer += delta
		var duration: float = 3.0
		if _entity.data != null:
			duration = float(_entity.data.tractor_beam_open_duration)

		var hero: Entity = null
		if _beam != null:
			hero = _beam.get_touching_hero()

		if not _fleet_allows_capture():
			_beam_timer = 0.0
			_beam_phase = BeamPhase.RETRACTING
			if _beam != null:
				_beam.retract()
			return

		if hero != null:
			# Capture succeeded.
			_captured_hero = hero
			_carry = Carry.PENDING
			hero.begin_capture()
			if _entity != null and _entity.data != null and _entity.data.sound_profile != null:
				_entity.play_sound("tractor_beam_capture")
			_beam_timer = 0.0
			_beam_phase = BeamPhase.ALIGNING
			return

		if _beam_timer >= duration:
			# Timeout: no capture.
			_beam_timer = 0.0
			_beam_phase = BeamPhase.RETRACTING
			if _beam != null:
				_beam.retract()
			# After retract, clear lock and go back to formation.
			return

		# Continue holding.
		return

	# Phase: ALIGNING
	if _beam_phase == BeamPhase.ALIGNING:
		if _captured_hero == null or not is_instance_valid(_captured_hero):
			# Hero was lost; abort.
			_abort_beam_no_capture()
			return
		_entity.rotation = PI
		if _captured_hero != null:
			var target_x: float = _entity.global_position.x
			var dx: float = target_x - _captured_hero.global_position.x
			if absf(dx) < 2.0:
				_captured_hero.global_position.x = target_x
				_beam_phase = BeamPhase.PULLING
			else:
				var dir: float = signf(dx)
				var speed: float = float(_entity.data.tractor_beam_align_speed) if _entity.data != null else 120.0
				_captured_hero.global_position.x += dir * speed * delta
		return

	# Phase: PULLING
	if _beam_phase == BeamPhase.PULLING:
		if _captured_hero == null or not is_instance_valid(_captured_hero):
			_abort_beam_no_capture()
			return
		_entity.rotation = PI

		# Pull the hero up to the rider position.
		var hero_scale: float = _captured_hero.scale_aux
		var foe_scale: float = _entity.scale_aux
		var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
		var target_pos: Vector2 = _entity.to_global(Vector2(0.0, d))
		var pull_speed: float = float(_entity.data.tractor_beam_pull_speed) if _entity.data != null else 90.0
		_captured_hero.global_position = _captured_hero.global_position.move_toward(target_pos, pull_speed * delta)

		# When close enough, park the hero.
		if _captured_hero.global_position.distance_to(target_pos) < 2.0:
			_captured_hero.global_position = target_pos
			_captured_hero.park_captured()
			_create_rider()
			# Retract the cone.
			_beam_timer = 0.0
			_beam_phase = BeamPhase.RETRACTING
			if _beam != null:
				_beam.retract()
		return

	# Phase: RETRACTING
	if _beam_phase == BeamPhase.RETRACTING:
		_entity.rotation = PI
		# Wait for the retracted signal; the rest is handled by the phase transition after signal.
		# But if the beam is already fully retracted (e.g., if signal fired), transition to formation or settling.
		if _beam == null or _beam.is_retracted():
			if _carry == Carry.PENDING:
				# Capture complete; go to formation with rider.
				state = State.SETTLING
				# The formation settling will commit the capture.
			else:
				# No capture; return to formation.
				state = State.SETTLING
				if _capturer == self:
					_capturer = null
		return


func _process_diving(delta: float) -> void:
	if not is_instance_valid(_slot):
		return
	var speed: float = _get_speed() * dive_speed_multiplier

	var reached_end: bool = _follow_curve(_dive_curve, _dive_xform, speed, delta)

	# Check for tractor beam trigger with the foe already moved for this frame,
	# so the cone's far end lands exactly on the hero's bottom edge.
	if not reached_end and _entity.data.tractor_beam_enabled:
		if _beam_planned and not is_capture_in_progress() and _can_start_beam():
			# Re-check when on screen.
			if _entity.global_position.y >= Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux:
				var hero: Entity = _get_capturable_hero()
				if hero != null:
					var overshoot: float = _get_beam_far_end_y() - _get_hero_bottom_y(hero)
					if overshoot >= 0.0:
						_entity.global_position.y -= minf(overshoot, speed * delta)
						_start_beam()
						return

	if not reached_end:
		return
	# End of dive: return to formation.
	_entity.global_position = Vector2(_slot.global_position.x, REENTRY_Y)
	_entity.rotation = PI
	_entity.score_multiplier = 1
	state = State.SETTLING
	dive_finished.emit()


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
		if _carry == Carry.PENDING:
			_carry = Carry.COMMITTED
			if _captured_hero != null and is_instance_valid(_captured_hero):
				_captured_hero.commit_capture()
			if _capturer == self:
				_capturer = null
		else:
			if _capturer == self:
				_capturer = null
		state = State.FORMATION
		entered_formation.emit()


func _process_formation() -> void:
	if not is_instance_valid(_slot):
		return
	_entity.global_position = _slot.global_position
	_entity.rotation = PI


func _process_tractor_beam(delta: float) -> void:
	_process_beam(delta)


func _abort_beam_no_capture() -> void:
	# No hero captured: retract, clear, and go back to formation.
	_beam_timer = 0.0
	_beam_phase = BeamPhase.RETRACTING
	if _beam != null:
		_beam.retract()
	_carry = Carry.NONE
	_captured_hero = null
	if _capturer == self:
		_capturer = null
	_free_rider()


func _on_entity_died(_entity_arg: Entity) -> void:
	if _capturer == self:
		_capturer = null

	if _carry == Carry.PENDING:
		# Carrier killed before commit: send the hero home, no life cost.
		if _captured_hero != null and is_instance_valid(_captured_hero):
			var release_pos: Vector2 = _captured_hero.global_position
			if _rider != null:
				release_pos = _rider.global_position
			_captured_hero.begin_return()
			_return_ship(_captured_hero, release_pos)
		_carry = Carry.NONE
		_captured_hero = null
		_free_rider()

	if _carry == Carry.COMMITTED:
		# Carrier killed after commit: pay the rescue bonus and fly a fresh ship
		# home. The captured one was already freed when the capture committed.
		if _entity != null and _entity.data != null:
			GameManager.add_score(int(_entity.data.tractor_beam_rescue_bonus))
			var rider_world_pos: Vector2 = _entity.global_position
			if _rider != null:
				rider_world_pos = _rider.global_position
			EffectsScript.score_popup(rider_world_pos, int(_entity.data.tractor_beam_rescue_bonus), true)
			_return_new_ship(rider_world_pos)
		_carry = Carry.NONE
		_captured_hero = null
		_free_rider()


## Hands a freed ship to the fleet so it flies back to its docking slot.
func _return_ship(ship: Entity, from: Vector2) -> void:
	var fleet: Fleet = get_tree().get_first_node_in_group(&"fleet") as Fleet
	if fleet == null:
		# No fleet in this scene: leave the ship playable where it was freed.
		ship.global_position = from
		ship.returning = false
		ship.set_deferred("monitorable", true)
		return
	if not fleet.recruit(ship, from):
		push_warning("FoeBrain: recruit() failed for freed ship; freeing it.")
		ship.queue_free()


## Spawns the ship rescued from a committed capture and sends it home.
func _return_new_ship(from: Vector2) -> void:
	var fleet: Fleet = get_tree().get_first_node_in_group(&"fleet") as Fleet
	if fleet == null:
		return
	var new_ship: Entity = fleet.recruit_new(from)
	if new_ship == null:
		push_warning("FoeBrain: recruit_new() returned null; no rescue ship created.")


func _create_rider() -> void:
	if _rider != null:
		return
	if _captured_hero == null or not is_instance_valid(_captured_hero) or _captured_hero.data == null:
		return
	_rider_hero_scale = _captured_hero.scale_aux
	_rider = Polygon2D.new()
	_rider.top_level = true
	_rider.color = TractorBeam.CAPTURED_SHIP_COLOR
	var points: PackedVector2Array = _captured_hero.data.get_polygon().duplicate()
	# Center polygon around origin so it pivots at its centre like the entity.
	var offset: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * -1.0
	for i in range(points.size()):
		points[i] += offset
	_rider.polygon = points
	_rider.scale = Vector2.ONE * _rider_hero_scale
	# Place initially at the rider position (above the foe).
	var hero_scale: float = _rider_hero_scale
	var foe_scale: float = _entity.scale_aux
	var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
	_rider.global_position = _entity.to_global(Vector2(0.0, d))
	_rider.rotation = _entity.rotation + PI
	get_tree().current_scene.add_child(_rider)


func _free_rider() -> void:
	if _rider != null:
		_rider.queue_free()
		_rider = null


func _exit_tree() -> void:
	if _capturer == self:
		_capturer = null
	_free_rider()


func _follow_curve(curve: Curve2D, xform: Transform2D, speed: float, delta: float) -> bool:
	_distance += speed * delta
	var length: float = curve.get_baked_length()
	var d: float = minf(_distance, length)
	var pos: Vector2 = xform * curve.sample_baked(d, true)
	var ahead: Vector2 = xform * curve.sample_baked(minf(d + 4.0, length), true)
	_entity.global_position = pos
	var heading: Vector2 = ahead - pos
	if heading.length_squared() > 0.0001:
		_entity.rotation = heading.angle() + PI / 2.0
	return _distance >= length


func _get_speed() -> float:
	return _entity.data.base_speed * _entity.speed_multiplier


## Returns the y of the Weapon muzzle relative to the entity centre, cached so
## the children are only scanned once.
func _get_muzzle_offset_y() -> float:
	if not is_nan(_muzzle_offset_y):
		return _muzzle_offset_y
	_muzzle_offset_y = 0.0
	for child: Node in _entity.get_children():
		var weapon: Weapon = child as Weapon
		if weapon != null:
			_muzzle_offset_y = weapon.muzzle_offset.y
			break
	return _muzzle_offset_y


## Returns the world y of the cone's far end when the foe faces down.
func _get_beam_far_end_y() -> float:
	return _entity.global_position.y + Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux - _get_muzzle_offset_y() + _entity.data.tractor_beam_height


## Returns the world y of the bottom edge of the hero's polygon.
func _get_hero_bottom_y(hero: Entity) -> float:
	return hero.global_position.y + Helpers.ENTITY_HALF_WIDTH * hero.scale_aux


func _warn_if_dive_ends_on_screen() -> void:
	var end: Vector2 = _dive_xform * _dive_curve.sample_baked(_dive_curve.get_baked_length(), true)
	var bottom: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_height"))
	if end.y < bottom + Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux:
		push_warning("FoeBrain.dive(): the dive curve ends too high (", end.y, "), the foe will pop back above the screen (", bottom, ").")
