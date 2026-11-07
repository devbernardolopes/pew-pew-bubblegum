class_name DashAbility
extends Node
## A horizontal dash with invulnerability, configured by [member EntityData].
##
## The ability is a child of [Entity], so any Entity with [member
## EntityData.dash_enabled] can use it. On a fleet member, the dash moves the
## whole fleet through the same clamping path as normal movement, and the
## leader's ability controls every ship of the fleet at once.

## Position difference below this is treated as the clamp blocking the dash.
const POSITION_EPSILON: float = 0.001

var _entity: Entity = null
var _fleet: Fleet = null
var _dashing: bool = false
## Sign of the locked dash direction: -1 left, 1 right.
var _direction: int = 0
var _distance: float = 0.0
var _speed: float = 0.0
var _travelled: float = 0.0
var _cooldown: float = 0.0
## Ships moved and tinted by the current dash. It is only more than one for a
## fleet commanded by this ability's Entity.
var _dash_ships: Array[Entity] = []
## Alpha each ship had before the dash, restored when it ends.
var _saved_alpha: Dictionary = {}


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("DashAbility must be a child of an Entity; dash disabled.")
		set_physics_process(false)
		return
	_fleet = _find_fleet()
	if _fleet != null and not _fleet.return_started.is_connected(_on_fleet_return_started):
		_fleet.return_started.connect(_on_fleet_return_started)
	if not GameManager.stage_changed.is_connected(_on_stage_changed):
		GameManager.stage_changed.connect(_on_stage_changed)
	if not GameManager.game_over.is_connected(_on_game_over):
		GameManager.game_over.connect(_on_game_over)


func _exit_tree() -> void:
	# A freed Entity must never leave a peer dimmed or invulnerable.
	cancel()


func _physics_process(delta: float) -> void:
	if _entity == null or Engine.is_editor_hint():
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if not _dashing:
		return
	if not _can_continue():
		cancel()
		return
	var requested: float = minf(_speed * delta, _distance - _travelled)
	if requested <= POSITION_EPSILON:
		_finish_dash()
		return
	var moved: float = absf(_move_step(float(_direction) * requested))
	if moved < requested - POSITION_EPSILON:
		# The clamp at the screen edge stopped the block: end right here, so the
		# invincibility does not linger at the edge for the rest of the dash.
		_travelled += moved
		_apply_alpha_cue()
		_finish_dash()
		return
	_travelled += moved
	_apply_alpha_cue()
	if _travelled >= _distance - POSITION_EPSILON:
		_finish_dash()


## Starts a dash towards [param direction] (-1 left, 1 right). Returns false
## when the Entity cannot dash right now.
func try_dash(direction: int) -> bool:
	if direction == 0 or not can_dash():
		return false
	var locked_direction: int = 1 if direction > 0 else -1
	# A dash against the edge it already touches would start and end in the
	# same frame and still spend the cooldown, so reject it before starting.
	if _get_room(locked_direction) <= POSITION_EPSILON:
		return false
	_start_dash(locked_direction)
	return true


## Whether a dash is running. The Entity is invulnerable while this is true.
func is_dashing() -> bool:
	return _dashing


## Whether [method try_dash] would start a dash now.
func can_dash() -> bool:
	if _dashing or _entity == null or _entity.data == null:
		return false
	if not _entity.data.dash_enabled or _entity.data.dash_duration <= 0.0:
		return false
	if _cooldown > 0.0:
		return false
	if _entity.is_dead or _entity.is_queued_for_deletion():
		return false
	if _entity.capture_active or _entity.returning:
		return false
	if not is_inside_tree() or get_tree().paused:
		return false
	# During a rescue flight the level disables the Entities container; the
	# input controller is outside it, so stop the request here too.
	if not _entity.can_process() or GameManager.is_game_over:
		return false
	var fleet: Fleet = _find_fleet()
	if fleet != null and fleet.ships.has(_entity):
		if fleet.is_returning():
			return false
		# Only the leader commands a fleet dash. The Fleet routes try_dash here.
		if fleet.ships[0] != _entity:
			return false
	return true


## Ends the dash early, restoring the alpha cue and invulnerability.
func cancel() -> void:
	if _dashing:
		_finish_dash()


func _start_dash(direction: int) -> void:
	var entity_data: EntityData = _entity.data
	_dashing = true
	_direction = direction
	_distance = _get_dash_distance()
	_speed = _distance / entity_data.dash_duration
	_travelled = 0.0
	_dash_ships = _get_controlled_ships()
	_saved_alpha.clear()
	for ship: Entity in _dash_ships:
		if not is_instance_valid(ship):
			continue
		ship.invulnerable = true
		if ship.visual != null:
			_saved_alpha[ship] = ship.visual.modulate.a
			ship.visual.modulate.a = entity_data.dash_alpha
		_connect_guards(ship)
		ship.dash_started.emit(direction)


func _finish_dash() -> void:
	if not _dashing:
		return
	_dashing = false
	var entity_data: EntityData = _entity.data if is_instance_valid(_entity) else null
	_cooldown = maxf(entity_data.dash_cooldown, 0.0) if entity_data != null else 0.0
	for ship: Entity in _dash_ships:
		if not is_instance_valid(ship):
			continue
		ship.invulnerable = false
		if ship.visual != null:
			# Restore the alpha channel only: RGB belongs to the other effects.
			ship.visual.modulate.a = float(_saved_alpha.get(ship, 1.0))
		_disconnect_guards(ship)
		ship.dash_ended.emit()
	_dash_ships.clear()
	_saved_alpha.clear()
	_direction = 0
	_travelled = 0.0


## Whether the dash can keep running; death, capture, a return flight and a
## rescue freeze all end it immediately.
func _can_continue() -> bool:
	if _entity == null or not is_instance_valid(_entity) or _entity.is_dead:
		return false
	if _entity.data == null or not _entity.data.dash_enabled:
		return false
	if _entity.capture_active or _entity.returning:
		return false
	var fleet: Fleet = _find_fleet()
	if fleet != null and fleet.ships.has(_entity) and fleet.is_returning():
		return false
	return true


## Room left towards [param direction] for the whole fleet when this Entity
## is its leader, or just for this Entity.
func _get_room(direction: int) -> float:
	var fleet: Fleet = _find_fleet()
	if fleet != null and not fleet.ships.is_empty() and fleet.ships[0] == _entity:
		return fleet.get_room(direction)
	return _entity.get_room_horizontal(direction)


## Moves the whole fleet when this Entity is its leader, or just this Entity.
## Returns the horizontal progress actually granted by the clamp.
func _move_step(delta_x: float) -> float:
	var fleet: Fleet = _find_fleet()
	if fleet != null and not fleet.ships.is_empty() and fleet.ships[0] == _entity:
		return fleet.move_block(delta_x)
	return _entity.move_horizontal(delta_x)


func _get_controlled_ships() -> Array[Entity]:
	var result: Array[Entity] = []
	var fleet: Fleet = _find_fleet()
	if fleet != null and not fleet.ships.is_empty() and fleet.ships[0] == _entity:
		for ship: Entity in fleet.ships:
			if is_instance_valid(ship):
				result.append(ship)
	else:
		result.append(_entity)
	return result


func _get_dash_distance() -> float:
	var ships: float = _entity.data.dash_distance_ships
	if ships <= 0.0:
		ships = float(Fleet.MAX_SHIPS)
	var ship_width: float = _entity.get_width()
	var fleet: Fleet = _find_fleet()
	if fleet != null and not fleet.ships.is_empty() and is_instance_valid(fleet.ships[0]):
		# The fleet's clamping uses the leader's width; keep one source of truth.
		ship_width = fleet.ships[0].get_width()
	return ships * ship_width


## Keeps the alpha cue applied every frame, so another effect that writes the
## visual's modulate cannot make the dashing ship opaque.
func _apply_alpha_cue() -> void:
	if _entity == null or _entity.data == null:
		return
	for ship: Entity in _dash_ships:
		if is_instance_valid(ship) and ship.visual != null:
			ship.visual.modulate.a = _entity.data.dash_alpha


func _connect_guards(ship: Entity) -> void:
	if not ship.died.is_connected(_on_ship_interrupted):
		ship.died.connect(_on_ship_interrupted)
	if not ship.capture_started.is_connected(_on_ship_interrupted):
		ship.capture_started.connect(_on_ship_interrupted)
	if not ship.capture_released.is_connected(_on_ship_interrupted):
		ship.capture_released.connect(_on_ship_interrupted)


func _disconnect_guards(ship: Entity) -> void:
	if ship.died.is_connected(_on_ship_interrupted):
		ship.died.disconnect(_on_ship_interrupted)
	if ship.capture_started.is_connected(_on_ship_interrupted):
		ship.capture_started.disconnect(_on_ship_interrupted)
	if ship.capture_released.is_connected(_on_ship_interrupted):
		ship.capture_released.disconnect(_on_ship_interrupted)


func _on_ship_interrupted(_ship: Entity) -> void:
	cancel()


func _on_fleet_return_started() -> void:
	cancel()


func _on_stage_changed(_stage: int) -> void:
	cancel()


func _on_game_over() -> void:
	cancel()


func _find_fleet() -> Fleet:
	if _fleet != null and is_instance_valid(_fleet):
		return _fleet
	if not is_inside_tree():
		return null
	_fleet = get_tree().get_first_node_in_group(&"fleet") as Fleet
	return _fleet
