extends Node2D
## Test level: spawns waves of foes, manages hero lives and respawn, and shows
## the HUD.

const HERO_SCENE: PackedScene = preload("res://scenes/entities/hero.tscn")
## Time after hero death before a respawn is allowed, in seconds.
const RESPAWN_DELAY: float = 1.5

@onready var center_line: Line2D = $Backgrounds/CenterLine
@onready var dive_director: DiveDirector = $DiveDirector
@onready var hero_spawn: Marker2D = $HeroSpawn
@onready var entities: Node2D = $Entities
@onready var projectiles: Node2D = $Projectiles

var hero: Entity = null
var _respawn_timer: float = 0.0
var _is_waiting_to_respawn: bool = false


func _ready() -> void:
	if center_line:
		center_line.visible = false
	spawn_hero()

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
	if _is_waiting_to_respawn:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			if _is_safe_to_respawn() and not FoeBrain.is_capture_in_progress():
				_is_waiting_to_respawn = false
				GameManager.use_reserve_ship()
				spawn_hero()


## Instantiates the hero, places it at the spawn point and connects its death.
func spawn_hero() -> void:
	hero = HERO_SCENE.instantiate() as Entity
	entities.add_child(hero)
	hero.global_position = hero_spawn.global_position
	hero.home_y = hero_spawn.global_position.y
	hero.died.connect(_on_hero_died)
	hero.capture_started.connect(_on_hero_capture_started)
	hero.capture_committed.connect(_on_hero_capture_committed)
	hero.capture_released.connect(_on_hero_capture_released)
	dive_director.enabled = true


## Called when the hero dies. The run statistics are recorded, dives are
## disabled, and either a respawn is scheduled or the game ends.
func _on_hero_died(entity: Entity) -> void:
	GameManager.record_shots(entity.shots_fired, entity.shots_hit)
	dive_director.enabled = false
	if GameManager.has_reserve_ship():
		_respawn_timer = RESPAWN_DELAY
		_is_waiting_to_respawn = true
	else:
		GameManager.end_game()


## Returns false when any foe is diving or any foe-team projectile is alive.
func _on_hero_capture_started(_entity: Entity) -> void:
	dive_director.enabled = false


func _on_hero_capture_committed(entity: Entity) -> void:
	_on_hero_died(entity)
	entity.queue_free()


func _on_hero_capture_released(_entity: Entity) -> void:
	dive_director.enabled = true


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
