class_name PlayerController
extends EntityController
## Reads the player's input once per physics frame and caches the result, so
## [Fleet] and [Entity] can read it any number of times in the same frame
## without consuming it twice. It owns the fire state machine: a plain press
## fires the primary, holding fire charges a shot fired on release when
## [member EntityData.charge_enabled] is on, and a completed [ComboData]
## sequence fires its weapon and consumes the final press. All timing uses
## physics [param delta], so it freezes with the tree; dashing does not cancel
## a charge, but death, capture, rescue flight, stage change, game over and a
## release while paused do.

## Emitted when a charge starts.
signal charge_started
## Emitted once when a charge reaches its threshold.
signal charge_ready
## Emitted when a charge is cancelled with no shot.
signal charge_cancelled
## Emitted when a charge ends on release; [param was_ready] tells whether the
## threshold was reached. Nothing consumes these signals yet.
signal charge_released(was_ready: bool)

## Remaining time of a dash press made without a direction.
var _dash_buffer: float = 0.0
## The Fleet (normal case) or the Entity this controller reads input for.
var _target: Node = null
## Weapon to fire this frame, or [code]&""[/code]. Valid only for the frame
## this controller's [method _physics_process] computed it in.
var _fire_request: StringName = &""
## Whether a charge is currently held, and its physics time and progress.
var _charging: bool = false
var _held_time: float = 0.0
var _charge_progress: float = 0.0
## Whether [signal charge_ready] already fired for the current charge.
var _ready_emitted: bool = false
var _combo_detector: ComboDetector = ComboDetector.new()


func _ready() -> void:
	# Read the dash before the owner moves, so a dash and walking never both
	# move the same block on the triggering frame.
	process_physics_priority = -10
	# Run while paused so a release during a pause cancels the charge instead
	# of firing on the resume frame; everything else is gated on the pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var parent: Node = get_parent()
	if parent is Fleet or parent is Entity:
		_target = parent
	if not GameManager.stage_changed.is_connected(_on_stage_changed):
		GameManager.stage_changed.connect(_on_stage_changed)
	if not GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.connect(_on_game_over)


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	if get_tree().paused:
		# Pausing freezes the charge; a release in between cancels it.
		if _charging and not Input.is_action_pressed("fire"):
			_cancel_charge()
		_fire_request = &""
		return
	_fire_request = &""
	var data: EntityData = _get_data()
	var debug: bool = data != null and data.input_debug
	if not _can_control_fire():
		_cancel_charge()
		_combo_detector.reset()
	else:
		var completed: ComboData = null
		if data != null and not data.combos.is_empty():
			completed = _combo_detector.update(delta, data.combos, debug)
		if completed != null:
			# The completing press is consumed: no regular shot, no charge.
			_fire_request = completed.weapon_id
			if debug:
				print("combo %s: completed, fired %s" % [completed.id, completed.weapon_id])
		_update_charge(delta, data, completed, debug)
	_handle_dash(delta)


func get_direction_h() -> float:
	return Input.get_axis("left", "right")


func wants_fire() -> bool:
	return _fire_request == &"primary"


func get_fire_request() -> StringName:
	return _fire_request


func get_charge_progress() -> float:
	return _charge_progress


func is_charge_ready() -> bool:
	return _charging and _charge_progress >= 1.0


## Advances the charge state machine for this frame. [param completed] is the
## combo completed by this frame's press, if any, whose press is consumed.
func _update_charge(delta: float, data: EntityData, completed: ComboData, debug: bool) -> void:
	if _charging:
		if data == null:
			_cancel_charge()
			return
		if not Input.is_action_pressed("fire"):
			_release_charge(data, debug, completed)
			return
		_held_time += delta
		_charge_progress = clampf(_held_time / data.charge_time, 0.0, 1.0) if data.charge_time > 0.0 else 1.0
		if _charge_progress >= 1.0 and not _ready_emitted:
			_ready_emitted = true
			charge_ready.emit()
			if debug:
				print("charge: ready")
		return
	if completed != null or not Input.is_action_just_pressed("fire"):
		return
	if data != null and data.charge_enabled:
		# A fresh press is required: holding fire from before never reaches
		# this, because [code]is_action_just_pressed[/code] is false for it.
		_charging = true
		_held_time = 0.0
		_charge_progress = 0.0
		_ready_emitted = false
		charge_started.emit()
		if debug:
			print("charge: started")
	else:
		# Charging off: fire the primary on press, as before.
		_fire_request = &"primary"


## Ends the charge on release: early release requests the primary, release at
## the threshold requests the charge weapon (with the primary fallback per
## ship). The request is cached for this frame only.
func _release_charge(data: EntityData, debug: bool, completed: ComboData) -> void:
	var was_ready: bool = _charge_progress >= 1.0
	charge_released.emit(was_ready)
	if debug:
		print("charge: released, ready=%s" % was_ready)
	# A combo completed by this frame's press keeps its request.
	if completed == null:
		_fire_request = data.charge_weapon_id if was_ready and data != null else &"primary"
	_charging = false
	_held_time = 0.0
	_charge_progress = 0.0
	_ready_emitted = false


## Cancels the charge with no shot and cleans up its state.
func _cancel_charge() -> void:
	if not _charging:
		return
	_charging = false
	_held_time = 0.0
	_charge_progress = 0.0
	_ready_emitted = false
	charge_cancelled.emit()


## The dash input handling, unchanged: a rejected press never starts a dash
## later without a fresh press or a buffered press still inside its window.
func _handle_dash(delta: float) -> void:
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


## The [EntityData] of the controlled ship: the leader's for a fleet.
func _get_data() -> EntityData:
	var fleet: Fleet = _target as Fleet
	if fleet != null:
		if fleet.ships.is_empty():
			return null
		var leader: Entity = fleet.ships[0]
		return leader.data if leader != null and is_instance_valid(leader) else null
	var entity: Entity = _target as Entity
	return entity.data if entity != null else null


## Whether input may drive firing and combos right now: a live ship in play.
## Dashing does not affect this; death, capture, rescue flight, a frozen
## fleet and game over all do.
func _can_control_fire() -> bool:
	if GameManager.is_game_over:
		return false
	var fleet: Fleet = _target as Fleet
	if fleet != null:
		if fleet.ships.is_empty() or fleet.is_returning():
			return false
		var leader: Entity = fleet.ships[0]
		return _is_live_ship(leader)
	var entity: Entity = _target as Entity
	if entity == null or entity.externally_driven:
		return false
	return _is_live_ship(entity)


func _is_live_ship(ship: Entity) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if ship.is_dead or ship.is_queued_for_deletion():
		return false
	if ship.capture_active or ship.returning:
		return false
	# During a rescue flight the level disables the Entities container; the
	# input controller is outside it, so stop the request here too.
	return ship.can_process()


func _on_stage_changed(_stage: int) -> void:
	_cancel_charge()
	_combo_detector.reset()


func _on_game_over() -> void:
	_cancel_charge()
	_combo_detector.reset()
