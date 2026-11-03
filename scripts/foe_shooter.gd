class_name FoeShooter
extends Node
## Shoots at the hero while its parent [Entity] dives.
## It reacts to the sibling [FoeBrain]'s [signal FoeBrain.dive_started] and
## [signal FoeBrain.dive_finished]: a few shots per dive, aimed where the hero
## is at the moment of firing and clamped to a downward cone.

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


func _physics_process(delta: float) -> void:
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


func _on_dive_started() -> void:
	_shots_left = shots_per_dive
	_timer = _random_delay()
	set_physics_process(true)


func _on_dive_finished() -> void:
	_shots_left = 0
	set_physics_process(false)


## Fires at the hero when it is in the line of sight. Returns false when
## nothing was fired, so the caller retries on the next frame.
func _try_fire() -> bool:
	# The Entity finds its Weapon in its own _ready(), which runs after the
	# children, so the weapon is read here instead of being cached in _ready().
	var weapon: Weapon = _entity.weapon
	var hero: Entity = get_tree().get_first_node_in_group(&"friend") as Entity
	if weapon == null or hero == null or hero.is_dead:
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


func _random_delay() -> float:
	return randf_range(minf(shot_delay_min, shot_delay_max), maxf(shot_delay_min, shot_delay_max))
