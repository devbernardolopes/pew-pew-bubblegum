class_name FoeShooter
extends Node
## Shoots at the hero while its parent [Entity] dives, and, when its
## [WaveData] allows it, while the foe flies its entry curve or sits in
## formation. Every shot is aimed where the hero is at the moment of firing and
## clamped to a downward cone.
## [br]Dives are driven by the sibling [FoeBrain]'s [signal FoeBrain.dive_started]
## and [signal FoeBrain.dive_finished]. Entry shots are local to the foe: it fires
## a few of them until its first arrival in formation. Formation shots are
## scheduled by the level's [FireDirector], which calls
## [method fire_from_formation]; this node never schedules them on its own.

## Number of shots fired per dive.
@export var shots_per_dive: int = 2
## Shortest delay between two shots, in seconds.
@export var shot_delay_min: float = 0.4
## Longest delay between two shots, in seconds.
@export var shot_delay_max: float = 0.8
## Maximum angle a shot may be aimed away from straight down, in degrees.
@export var max_aim_angle_deg: float = 60.0
## Minimum height above the hero the foe must be to fire, in pixels.
@export var min_height_above_hero: float = 64.0

var _entity: Entity = null
var _brain: FoeBrain = null
var _shots_left: int = 0
var _timer: float = 0.0
## Whether [method configure] enabled entry fire for this wave.
var _fire_on_entry: bool = false
## Whether the [FireDirector] may pick this foe while it sits in formation.
var _fire_in_formation: bool = false
## Whether the foe already arrived in formation once: entry fire ends there.
var _has_entered: bool = false
var _entry_shots_left: int = 0
var _entry_timer: float = 0.0


func _ready() -> void:
	set_physics_process(false)
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("FoeShooter must be a child of an Entity; shooting disabled.")
		return
	_brain = _entity.get_node_or_null(^"FoeBrain") as FoeBrain
	if _brain == null:
		push_error("FoeShooter needs a sibling FoeBrain; shooting disabled.")
		return
	_brain.dive_started.connect(_on_dive_started)
	_brain.dive_finished.connect(_on_dive_finished)
	_brain.entered_formation.connect(_on_entered_formation)


func _physics_process(delta: float) -> void:
	if _shots_left > 0:
		_tick_dive(delta)
		return
	_tick_entry(delta)


func _tick_dive(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	# Conditions not met or the weapon busy: keep _timer <= 0 to retry next frame.
	if not _try_fire():
		return
	_shots_left -= 1
	_timer = _random_delay()
	if _shots_left <= 0:
		set_physics_process(false)


func _tick_entry(delta: float) -> void:
	if _has_entered or _entry_shots_left <= 0:
		return
	# The entry timer only runs once the foe actually starts moving.
	if _brain.state != FoeBrain.State.ENTERING and _brain.state != FoeBrain.State.SETTLING:
		return
	_entry_timer -= delta
	if _entry_timer > 0.0:
		return
	# Conditions not met or the weapon busy: keep _entry_timer <= 0 to retry.
	if not _try_fire():
		return
	_entry_shots_left -= 1
	_entry_timer = _random_delay()
	if _entry_shots_left <= 0:
		set_physics_process(false)


## Applies the firing flags of [param wave]. [StageDirector] calls it once, right
## after [method FoeBrain.setup], so the entry shots start as the foe sets off.
func configure(wave: WaveData) -> void:
	if wave == null or _entity == null or _brain == null:
		return
	_fire_on_entry = wave.fire_on_entry
	_fire_in_formation = wave.fire_in_formation
	_entry_shots_left = wave.entry_shots if _fire_on_entry else 0
	_entry_timer = _random_delay()
	if _entry_shots_left > 0:
		set_physics_process(true)


## Whether the [FireDirector] may pick this foe for a formation shot right now.
func can_fire_in_formation() -> bool:
	if not _fire_in_formation or not _has_entered:
		return false
	if _brain == null or _brain.state != FoeBrain.State.FORMATION:
		return false
	if _entity == null or _entity.is_queued_for_deletion() or _entity.is_dead:
		return false
	return _entity.weapon != null


## Fires one aimed shot from the formation. The [FireDirector] decides the when;
## returns false when nothing was fired, so the caller may try another foe.
func fire_from_formation() -> bool:
	return can_fire_in_formation() and _try_fire()


func _on_dive_started() -> void:
	_shots_left = shots_per_dive
	_timer = _random_delay()
	set_physics_process(true)


func _on_dive_finished() -> void:
	_shots_left = 0
	set_physics_process(false)


## The first arrival in formation ends entry fire; later arrivals (after a dive)
## keep it off.
func _on_entered_formation() -> void:
	_has_entered = true
	_entry_shots_left = 0
	if _shots_left <= 0:
		set_physics_process(false)


## Fires at the nearest ship in play when it is in the line of sight. Returns
## false when nothing was fired, so the caller retries on the next frame.
func _try_fire() -> bool:
	# The Entity finds its Weapon in its own _ready(), which runs after the
	# children, so the weapon is read here instead of being cached in _ready().
	var weapon: Weapon = _entity.weapon
	var hero: Entity = _find_target()
	if weapon == null or hero == null:
		return false
	if _brain != null and _brain.state == FoeBrain.State.TRACTOR_BEAM:
		return false
	var pos: Vector2 = _entity.global_position
	if pos.y < 0.0 or pos.y > hero.global_position.y - min_height_above_hero:
		return false
	var to_hero: Vector2 = hero.global_position - pos
	var max_angle: float = deg_to_rad(max_aim_angle_deg)
	var angle: float = clampf(Vector2.DOWN.angle_to(to_hero), -max_angle, max_angle)
	return weapon.fire(Vector2.DOWN.rotated(angle))


## The closest friend that is in play: a returning or captured ship is not a
## target, because it is not where the player is.
func _find_target() -> Entity:
	var target: Entity = null
	var best_distance: float = INF
	var origin: Vector2 = _entity.global_position
	for node: Node in get_tree().get_nodes_in_group(&"friend"):
		var hero: Entity = node as Entity
		if hero == null or not hero.is_capturable():
			continue
		var distance: float = origin.distance_squared_to(hero.global_position)
		if distance < best_distance:
			best_distance = distance
			target = hero
	return target


func _random_delay() -> float:
	return randf_range(minf(shot_delay_min, shot_delay_max), maxf(shot_delay_min, shot_delay_max))
