class_name FoeBrain
extends Node
## Moves its parent [Entity] along an entry [Curve2D] and then into a
## [Marker2D] formation slot; it also flies a dive curve on request.
## It is not an [EntityController]: it owns the Entity's position and rotation
## outright, which is why the Entity has no controller child.

signal entered_formation
signal dive_started
signal dive_finished
## Emitted when a carried hero's carrier is killed after the ship was committed.
signal captured_ship_rescued(world_position: Vector2)

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
		if _entity != null:
			var muzzle_offset: Vector2 = Vector2.ZERO
			for child in _entity.get_children():
				if child is Weapon:
					muzzle_offset = (child as Weapon).muzzle_offset
			_beam.position = Vector2.UP * Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux + muzzle_offset
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

	# Update rider position whenever we are carrying, in any state.
	if _carry != Carry.NONE and _captured_hero != null and is_instance_valid(_captured_hero):
		if _rider == null:
			_create_rider()
		if _rider != null:
			# Rider is top-level and follows the foe.
			var hero_scale: float = _captured_hero.scale_aux
			var foe_scale: float = _entity.scale_aux
			# Distance between the centers when docked on the back.
			var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
			# With the foe facing down (PI), the back is straight up (local UP rotated by PI = world UP).
			# Wait: rotation PI means the nose points down (positive y). The back is opposite: negative y locally.
			# So the rider should sit above the foe (negative world y when rotation = PI).
			# Actually, the prompt says: "with the foe at rotation = PI, the rider sits directly above it, nose up".
			# That means rotation = PI + PI = 0 for the rider? Let's re-read...
			# "The rider is upright while the foe faces down in formation and rotates with the foe during dives,
			# i.e. it stays docked on the foe's back."
			# "Place it at the muzzle: local Vector2.UP * ..." for the beam. The rider should follow the foe.
			# With the foe at rotation PI, the back is in the direction of rotation + PI = 0 (world UP).
			# So rider position = foe.to_global(Vector2.UP * d) when rotation=PI? No.
			# If the rider follows the foe, and the foe's back is opposite to its nose, then:
			# rider_world_pos = foe.global_position + Vector2.UP.rotated(foe.rotation + PI) * d
			# But with rotation=PI: UP.rotated(2*PI) = UP = (0, -1) = world UP.
			# That puts the rider above the foe. But the prompt says "pulled up above it" during the pull,
			# and then "carried back to formation" with the rider above.
			# Actually, looking at the old description: "pulled up above it", then "carried back".
			# The rider should be above the foe (negative y when foe is facing down).
			# But wait: the prompt says for rider placement: "place it at foe.to_global(Vector2(0, d)) with rotation = foe.rotation + PI".
			# Let me use that exact formula.
			var rider_offset: Vector2 = Vector2(0.0, d)
			var rider_world_pos: Vector2 = _entity.to_global(rider_offset)
			_rider.global_position = rider_world_pos
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


func dive(mirror: bool) -> bool:
	if state != State.FORMATION or _slot == null or _entity == null:
		return false
	if _carry != Carry.NONE:
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


func _can_start_beam() -> bool:
	if is_capture_in_progress():
		return false
	if _carry != Carry.NONE:
		return false
	# The hero must exist and be capturable.
	var hero_nodes: Array = get_tree().get_nodes_in_group(&"friend")
	for node: Node in hero_nodes:
		if node is Entity:
			var ent: Entity = node as Entity
			if ent == null or not is_instance_valid(ent):
				continue
			if ent.is_dead or ent.is_queued_for_deletion():
				continue
			if ent.capture_active or ent.auto_descending:
				continue
			# Found a capturable hero.
			return true
	return false


func _start_beam() -> void:
	_beam_planned = false
	_capturer = self
	_beam_phase = BeamPhase.TURNING
	_beam_timer = 0.0
	_entity.score_multiplier = 1
	dive_finished.emit()
	state = State.TRACTOR_BEAM
	if _beam != null:
		_beam.extend()


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

	# If the hero was captured, update rider each frame.
	if _carry != Carry.NONE and _captured_hero != null and is_instance_valid(_captured_hero):
		if _rider == null:
			_create_rider()
		if _rider != null:
			var hero_scale: float = _captured_hero.scale_aux
			var foe_scale: float = _entity.scale_aux
			var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
			_rider.global_position = _entity.to_global(Vector2(0.0, d))
			_rider.rotation = _entity.rotation + PI

	# Phase: TURNING
	if _beam_phase == BeamPhase.TURNING:
		_entity.rotation = lerp_angle(_entity.rotation, PI, 1.0 - exp(-turn_rate * delta))
		if absf(angle_difference(_entity.rotation, PI)) < SNAP_ANGLE:
			_entity.rotation = PI
			_beam_phase = BeamPhase.EXTENDING
			if _beam != null:
				_beam.extend()
		return

	# Phase: EXTENDING
	if _beam_phase == BeamPhase.EXTENDING:
		# Wait for fully_extended signal (handled in _on_beam_fully_extended).
		# While extending, keep facing down.
		_entity.rotation = PI
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

		if hero != null:
			# Capture succeeded.
			_captured_hero = hero
			_carry = Carry.PENDING
			hero.begin_capture()
			if hero.data != null and hero.data.sound_profile != null:
				hero.play_sound("tractor_beam_capture")
			_beam_timer = 0.0
			_beam_phase = BeamPhase.ALIGNING
			# Retract the cone; the hero is frozen.
			if _beam != null:
				_beam.retract()
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
				_capturer = null
		return


func _process_diving(delta: float) -> void:
	if not is_instance_valid(_slot):
		return
	var speed: float = _get_speed() * dive_speed_multiplier

	# Check for tractor beam trigger.
	if _entity != null and _entity.data != null and _entity.data.tractor_beam_enabled:
		if _beam_planned and not is_capture_in_progress() and _can_start_beam():
			# Re-check when on screen.
			if _entity.global_position.y >= Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux:
				# Check if cone bottom reaches hero.
				var hero_nodes: Array = get_tree().get_nodes_in_group(&"friend")
				for node: Node in hero_nodes:
					if node is Entity:
						var hero: Entity = node as Entity
						if hero == null or not is_instance_valid(hero) or hero.is_dead:
							continue
						if hero.capture_active or hero.auto_descending:
							continue
						# Compute beam origin at muzzle when facing down.
						var muzzle_offset_y: float = 0.0
						for child in _entity.get_children():
							if child is Weapon:
								muzzle_offset_y = (child as Weapon).muzzle_offset.y
						var origin_y: float = _entity.global_position.y + Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux - muzzle_offset_y
						var cone_height: float = float(_entity.data.tractor_beam_height) if _entity.data != null else 400.0
						# Trigger when the cone's far end reaches or passes the hero's center.
						if origin_y + cone_height >= hero.global_position.y:
							_start_beam()
							return

	if not _follow_curve(_dive_curve, _dive_xform, speed, delta):
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
			_capturer = null
		else:
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
	_capturer = null


func _on_entity_died() -> void:
	if _capturer == self:
		_capturer = null

	if _carry == Carry.PENDING:
		# Carrier killed before commit: release hero with no life cost.
		if _captured_hero != null and is_instance_valid(_captured_hero):
			var rider_world_pos: Vector2 = Vector2.ZERO
			if _rider != null:
				rider_world_pos = _rider.global_position
			else:
				rider_world_pos = _entity.global_position
			_captured_hero.release_from_capture(rider_world_pos)
		_carry = Carry.NONE
		_captured_hero = null

	if _carry == Carry.COMMITTED:
		# Carrier killed after commit: award rescue bonus and emit signal.
		if _entity != null and _entity.data != null:
			GameManager.add_score(int(_entity.data.tractor_beam_rescue_bonus))
			var rider_world_pos: Vector2 = Vector2.ZERO
			if _rider != null:
				rider_world_pos = _rider.global_position
			else:
				rider_world_pos = _entity.global_position
			EffectsScript.score_popup(rider_world_pos, int(_entity.data.tractor_beam_rescue_bonus), true)
			# Pop effect on rider.
			if _entity.data != null:
				EffectsScript.explode(_entity.data.visual, _entity.scale_aux, rider_world_pos, TractorBeam.CAPTURED_SHIP_COLOR, 0.3)
			captured_ship_rescued.emit(rider_world_pos)
		_carry = Carry.NONE
		_captured_hero = null


func _create_rider() -> void:
	if _captured_hero == null or not is_instance_valid(_captured_hero) or _captured_hero.data == null:
		return
	_rider = Polygon2D.new()
	_rider.top_level = true
	_rider.color = TractorBeam.CAPTURED_SHIP_COLOR
	_rider.polygon = Helpers.get_polygon(_captured_hero.data.visual)
	_rider.scale = Vector2.ONE * _captured_hero.scale_aux
	# Center the polygon like the entity's visual.
	_rider.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * _captured_hero.scale_aux * -1.0
	# Place initially at the rider position (above the foe).
	var hero_scale: float = _captured_hero.scale_aux
	var foe_scale: float = _entity.scale_aux
	var d: float = Helpers.ENTITY_HALF_WIDTH * (foe_scale + hero_scale) + 2.0
	_rider.global_position = _entity.to_global(Vector2(0.0, d))
	_rider.rotation = _entity.rotation + PI
	get_tree().current_scene.add_child(_rider)


func _free_rider() -> void:
	if _rider != null:
		_rider.queue_free()
		_rider = null


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


func _warn_if_dive_ends_on_screen() -> void:
	var end: Vector2 = _dive_xform * _dive_curve.sample_baked(_dive_curve.get_baked_length(), true)
	var bottom: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_height"))
	if end.y < bottom + Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux:
		push_warning("FoeBrain.dive(): the dive curve ends too high (", end.y, "), the foe will pop back above the screen (", bottom, ").")
