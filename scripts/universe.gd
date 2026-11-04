extends Node2D
## Test level: spawns waves of foes, owns the player's [Fleet], manages lives
## and respawn, and shows the HUD.

## Time after the fleet empties before a respawn is allowed, in seconds.
const RESPAWN_DELAY: float = 1.5

@onready var center_line: Line2D = $Backgrounds/CenterLine
@onready var dive_director: DiveDirector = $DiveDirector
@onready var hero_spawn: Marker2D = $HeroSpawn
@onready var entities: Node2D = $Entities
@onready var projectiles: Node2D = $Projectiles

## The player's ships. Lives are the ships in play plus the reserve icons.
var fleet: Fleet = null

var _respawn_timer: float = 0.0
var _is_waiting_to_respawn: bool = false


func _ready() -> void:
	if center_line:
		center_line.visible = false
	_create_fleet()
	fleet.spawn_ship(hero_spawn.global_position)

	# Connect stage banner to starfield warp effect.
	var hud: Hud = get_node_or_null("Hud") as Hud
	if hud != null:
		hud.stage_banner_started.connect(_on_stage_banner_started)
		hud.stage_banner_finished.connect(_on_stage_banner_finished)


func _on_stage_banner_started() -> void:
	for layer: StarfieldLayer in [$Backgrounds/Starfield, $Backgrounds/StarfieldMid, $Backgrounds/StarfieldNear]:
		if is_instance_valid(layer):
			layer.apply_boost()


func _on_stage_banner_finished() -> void:
	for layer: StarfieldLayer in [$Backgrounds/Starfield, $Backgrounds/StarfieldMid, $Backgrounds/StarfieldNear]:
		if is_instance_valid(layer):
			layer.clear_boost()


func _physics_process(delta: float) -> void:
	if not _is_waiting_to_respawn:
		return
	_respawn_timer -= delta
	if _respawn_timer > 0.0:
		return
	if not _is_safe_to_respawn() or FoeBrain.is_capture_in_progress():
		return
	_is_waiting_to_respawn = false
	GameManager.use_reserve_ship()
	fleet.spawn_ship(hero_spawn.global_position)


## Creates the fleet and wires everything the level needs from it.
func _create_fleet() -> void:
	fleet = Fleet.new()
	fleet.name = "Fleet"
	fleet.ships_root = entities
	fleet.home_position = hero_spawn.global_position
	fleet.member_added.connect(_on_fleet_member_added)
	fleet.member_died.connect(_on_fleet_member_died)
	fleet.emptied.connect(_on_fleet_emptied)
	fleet.return_started.connect(_on_fleet_return_started)
	fleet.return_finished.connect(_on_fleet_return_finished)
	add_child(fleet)


func _on_fleet_member_added(ship: Entity) -> void:
	ship.capture_started.connect(_on_ship_capture_started)
	ship.capture_committed.connect(_on_ship_capture_committed)
	dive_director.enabled = true


## Called when a ship is destroyed. The run statistics are recorded here; the
## fleet emits [signal Fleet.emptied] once the last one is gone.
func _on_fleet_member_died(ship: Entity) -> void:
	GameManager.record_shots(ship.shots_fired, ship.shots_hit)


func _on_fleet_emptied() -> void:
	_schedule_respawn_or_end()


## The ship leaves the fleet while the beam carries it; the life is only lost
## when the capture is committed.
func _on_ship_capture_started(entity: Entity) -> void:
	dive_director.enabled = false
	fleet.drop_ship(entity)


## A committed capture removes the ship for good. When it was the last one, it
## costs a life like any other death.
func _on_ship_capture_committed(entity: Entity) -> void:
	GameManager.record_shots(entity.shots_fired, entity.shots_hit)
	fleet.drop_ship(entity)
	entity.queue_free()
	if fleet.ships.is_empty():
		_schedule_respawn_or_end()
	else:
		dive_director.enabled = true


## A freed ship is flying home: the flight replaces the respawn delay, so no
## reserve ship is spent.
func _on_fleet_return_started() -> void:
	_is_waiting_to_respawn = false
	_respawn_timer = 0.0
	_set_action_frozen(true)


func _on_fleet_return_finished() -> void:
	_set_action_frozen(false)
	dive_director.enabled = true


func _schedule_respawn_or_end() -> void:
	dive_director.enabled = false
	if GameManager.has_reserve_ship():
		_respawn_timer = RESPAWN_DELAY
		_is_waiting_to_respawn = true
	else:
		GameManager.end_game()


## Freezes everything that takes part in the fight while a rescued ship flies
## home, without pausing the tree: backgrounds, effects, HUD and music keep
## running.
func _set_action_frozen(frozen: bool) -> void:
	var mode: Node.ProcessMode = (
		Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	)
	for node: Node in [$Entities, $Projectiles, $Formations, $DiveDirector, $StageDirector]:
		node.set_deferred("process_mode", mode)


## Returns false when any foe is diving or any foe-team projectile is alive.
func _is_safe_to_respawn() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		var brain: FoeBrain = node as FoeBrain
		if brain == null:
			continue
		if brain.state == FoeBrain.State.DIVING or brain.state == FoeBrain.State.TRACTOR_BEAM:
			return false
	for proj: Node in projectiles.get_children():
		var p: Projectile = proj as Projectile
		if p == null:
			continue
		if p.team == Helpers.TEAM.FOE and not p.is_queued_for_deletion():
			return false
	return true
