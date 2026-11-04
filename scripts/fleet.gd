class_name Fleet
extends Node
## Owns the player's ships: one or two [Entity]s that move, clamp and fire as a
## single block, as the dual fighter of the original game does.
##
## The Fleet sets the members' global positions itself, so the ships have no
## controller and never clamp on their own; the split is the same [FoeBrain]
## uses for a foe. A ship grabbed by a tractor beam leaves the fleet, and when
## it is freed it flies back to the free docking slot and rejoins.

const EffectsScript = preload("res://scripts/effects/effects.gd")
const HERO_SCENE: PackedScene = preload("res://scenes/entities/hero.tscn")

## Emitted when a member is destroyed, right before it leaves the tree.
signal member_died(ship: Entity)
## Emitted when the last member is gone, so the level must respawn it.
signal emptied
## Emitted when a ship joins the fleet, so the level can wire its own signals.
signal member_added(ship: Entity)
## Emitted when the first freed ship starts flying home and when the last one
## docks. The level freezes the action in between.
signal return_started
signal return_finished

## Most ships the fleet can hold at once.
const MAX_SHIPS: int = 2
## Seconds a freed ship takes to fly back to its docking slot.
const RETURN_DURATION: float = 1.0

## Container the ship instances are added to.
@export var ships_root: Node2D = null
## Where a ship goes when the fleet is empty (the hero spawn point).
@export var home_position: Vector2 = Vector2.ZERO

## The ships in play, the leader first.
var ships: Array[Entity] = []

var _controller: EntityController = null
var _returning: Entity = null
var _return_start: Vector2 = Vector2.ZERO
var _return_target: Vector2 = Vector2.ZERO
var _return_elapsed: float = 0.0
## Ships freed while another one was already flying home: they wait their turn
## so two flights never target the same slot.
var _pending_returns: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(&"fleet")
	_controller = PlayerController.new()
	add_child(_controller)


func _process(delta: float) -> void:
	if _returning == null:
		return
	if not is_instance_valid(_returning):
		_returning = null
		_advance_return_queue()
		return
	_return_elapsed += delta
	var progress: float = clampf(_return_elapsed / RETURN_DURATION, 0.0, 1.0)
	_returning.global_position = _return_start.lerp(_return_target, ease(progress, -2.0))
	if progress >= 1.0:
		_dock_returning()


func _physics_process(delta: float) -> void:
	if ships.is_empty() or _returning != null or _controller == null:
		return
	var leader: Entity = ships[0]
	if leader == null or not is_instance_valid(leader) or leader.data == null:
		return
	var dir: float = _controller.get_direction_h()
	var wants_fire: bool = _controller.wants_fire()
	if dir != 0.0:
		var speed: float = leader.data.base_speed * leader.speed_multiplier
		_place(_clamped_x(leader.global_position.x + dir * speed * delta))
	for ship: Entity in ships:
		if is_instance_valid(ship):
			ship.drive(dir, wants_fire, delta)


func _exit_tree() -> void:
	_returning = null
	_pending_returns.clear()


## Adds a new ship at [param at] and returns it; null when the fleet is full.
func spawn_ship(at: Vector2) -> Entity:
	if _reserved_slots() >= MAX_SHIPS:
		return null
	var ship: Entity = _create_ship(at)
	if ship == null:
		return null
	ships.append(ship)
	_place(at.x)
	member_added.emit(ship)
	return ship


## Removes [param ship] from the fleet without treating it as a loss, because a
## tractor beam grabbed it.
func drop_ship(ship: Entity) -> void:
	if not ships.has(ship):
		return
	ships.erase(ship)
	if not ships.is_empty():
		_place(ships[0].global_position.x)


## Flies a freed ship from [param from] to the free docking slot and makes it a
## member again when it arrives. Returns false when the fleet cannot take it.
func recruit(ship: Entity, from: Vector2) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	if _reserved_slots() >= MAX_SHIPS:
		return false
	_queue_return(ship, from)
	return true


## Spawns a fresh ship at [param from] (the rider of a committed capture) and
## flies it to the free docking slot. Returns null when it cannot be added.
func recruit_new(from: Vector2) -> Entity:
	if GameManager.is_game_over:
		return null
	if _reserved_slots() >= MAX_SHIPS:
		return null
	var ship: Entity = _create_ship(from)
	if ship == null:
		return null
	_queue_return(ship, from)
	return ship


## Returns the docking position closest to [param from_x] that still fits on
## screen, or [member home_position] when the fleet is empty.
func free_slot_for(from_x: float) -> Vector2:
	if ships.is_empty():
		return home_position
	var leader: Entity = ships[0]
	var offset: float = _dock_offset()
	var half: float = Helpers.ENTITY_HALF_WIDTH * leader.scale_aux
	var left: Vector2 = leader.global_position - Vector2(offset, 0.0)
	var right: Vector2 = leader.global_position + Vector2(offset, 0.0)
	var left_fits: bool = left.x - half >= 0.0
	var right_fits: bool = right.x + half <= Helpers.get_game_width()
	if left_fits and not right_fits:
		return left
	if right_fits and not left_fits:
		return right
	return left if absf(left.x - from_x) <= absf(right.x - from_x) else right


## Whether a tractor beam may capture: false when two ships are in play or one
## is flying home (a rescue in flight will make two).
func allows_capture() -> bool:
	return _reserved_slots() < MAX_SHIPS


## Whether a freed ship is still on its way home.
func is_returning() -> bool:
	return _returning != null


func _create_ship(at: Vector2) -> Entity:
	if ships_root == null:
		push_error("Fleet: ships_root is null; the ship cannot be created.")
		return null
	var ship: Entity = HERO_SCENE.instantiate() as Entity
	if ship == null:
		push_error("Fleet: the hero scene does not instantiate an Entity.")
		return null
	ships_root.add_child(ship)
	ship.global_position = at
	ship.externally_driven = true
	ship.died.connect(_on_member_died)
	return ship


func _queue_return(ship: Entity, from: Vector2) -> void:
	ship.global_position = from
	ship.rotation = 0.0
	ship.visible = true
	ship.returning = true
	ship.externally_driven = true
	ship.set_deferred("monitorable", false)
	if _returning == null:
		_start_return(ship, from)
	else:
		_pending_returns.append({"ship": ship, "from": from})


func _start_return(ship: Entity, from: Vector2) -> void:
	_returning = ship
	_return_start = from
	_return_target = free_slot_for(from.x)
	_return_elapsed = 0.0
	return_started.emit()


func _dock_returning() -> void:
	var ship: Entity = _returning
	_returning = null
	if ship != null and is_instance_valid(ship):
		ship.global_position = _return_target
		ship.returning = false
		ship.set_deferred("monitorable", true)
		# Docking on the left makes the newcomer the leader, so the block never
		# moves to make room for it.
		if ships.is_empty() or ship.global_position.x < ships[0].global_position.x:
			ships.insert(0, ship)
		else:
			ships.append(ship)
		_place(ships[0].global_position.x)
		member_added.emit(ship)
	_advance_return_queue()


func _advance_return_queue() -> void:
	if _pending_returns.is_empty():
		return_finished.emit()
		return
	var next: Dictionary = _pending_returns.pop_front()
	_start_return(next["ship"], next["from"])


func _on_member_died(ship: Entity) -> void:
	if not ships.has(ship):
		return
	ships.erase(ship)
	if not ships.is_empty():
		# The survivor stays where it is and becomes the leader.
		_place(ships[0].global_position.x)
	member_died.emit(ship)
	if ships.is_empty():
		emptied.emit()
		EffectsScript.screen_shake(1.0, 0.3)


## Number of slots already taken in play or reserved by a ship flying home.
func _reserved_slots() -> int:
	var count: int = ships.size()
	if _returning != null:
		count += 1
	return count + _pending_returns.size()


## Places the block with the leader's centre at [param origin_x].
func _place(origin_x: float) -> void:
	if ships.is_empty():
		return
	var offset: float = _dock_offset()
	var row_y: float = ships[0].global_position.y
	for i: int in ships.size():
		var ship: Entity = ships[i]
		if is_instance_valid(ship):
			ship.global_position = Vector2(origin_x + float(i) * offset, row_y)


## Keeps the whole block on screen, using the combined width of the ships.
func _clamped_x(x: float) -> float:
	if ships.is_empty():
		return x
	var half: float = Helpers.ENTITY_HALF_WIDTH * ships[0].scale_aux
	var block_left: float = half
	var block_right: float = Helpers.get_game_width() - _dock_offset() * float(ships.size() - 1) - half
	return clampf(x, block_left, block_right)


## Distance between two adjacent ship centres, so their boxes touch.
func _dock_offset() -> float:
	if ships.is_empty():
		return Helpers.ENTITY_WIDTH * 0.25
	return Helpers.ENTITY_WIDTH * ships[0].scale_aux
