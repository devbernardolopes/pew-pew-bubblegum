extends Node2D
## Test level: spawns waves of foes, manages hero lives and respawn, and shows
## the HUD.

const FOE_SCENE: PackedScene = preload("res://scenes/entities/foe_01.tscn")
const HERO_SCENE: PackedScene = preload("res://scenes/entities/hero.tscn")
## Delay between two foes of the same side entering, in seconds.
const ENTRY_SPACING: float = 0.25
## Number of foes launched from each side; placeholder until waves are authored.
const COLUMNS_PER_SIDE: int = 4
## Time after hero death before a respawn is allowed, in seconds.
const RESPAWN_DELAY: float = 1.5

@onready var formation: Formation = $Formation
@onready var entry_path: Path2D = $EntryPath
@onready var dive_director: DiveDirector = $DiveDirector
@onready var hero_spawn: Marker2D = $HeroSpawn
@onready var entities: Node2D = $Entities
@onready var projectiles: Node2D = $Projectiles

var hero: Entity = null
var _respawn_timer: float = 0.0
var _is_waiting_to_respawn: bool = false


func _ready() -> void:
	spawn_hero()
	var left_slots: Array[Marker2D] = []
	var right_slots: Array[Marker2D] = []
	for col: int in COLUMNS_PER_SIDE:
		left_slots.append(formation.get_slot(0, col))
		right_slots.append(formation.get_slot(0, col + COLUMNS_PER_SIDE))
	spawn_wave(FOE_SCENE, entry_path.curve, false, left_slots, ENTRY_SPACING)
	spawn_wave(FOE_SCENE, entry_path.curve, true, right_slots, ENTRY_SPACING)


func _physics_process(delta: float) -> void:
	if _is_waiting_to_respawn:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			if _is_safe_to_respawn():
				_is_waiting_to_respawn = false
				GameManager.use_reserve_ship()
				spawn_hero()


## Instantiates the hero, places it at the spawn point and connects its death.
func spawn_hero() -> void:
	hero = HERO_SCENE.instantiate() as Entity
	entities.add_child(hero)
	hero.global_position = hero_spawn.global_position
	hero.died.connect(_on_hero_died)
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
func _is_safe_to_respawn() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		var brain: FoeBrain = node as FoeBrain
		if brain == null:
			continue
		if brain.state == FoeBrain.State.DIVING:
			return false
	for proj: Node in projectiles.get_children():
		var p: Projectile = proj as Projectile
		if p == null:
			continue
		if p.team == Helpers.TEAM.FOE and not p.is_queued_for_deletion():
			return false
	return true


## Instantiates one foe per slot and starts it along [param curve].
func spawn_wave(foe_scene: PackedScene, curve: Curve2D, mirror: bool, slots: Array[Marker2D], spacing: float) -> void:
	for index: int in slots.size():
		var foe: Entity = foe_scene.instantiate() as Entity
		entities.add_child(foe)
		var brain: FoeBrain = foe.get_node(^"FoeBrain") as FoeBrain
		brain.setup(curve, mirror, slots[index], index * spacing)
