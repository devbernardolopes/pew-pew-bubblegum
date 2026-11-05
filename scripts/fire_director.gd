class_name FireDirector
extends Node
## Decides when a foe sitting in formation shoots. It picks a foe at random
## among those whose [WaveData] allows formation fire, every so often, and keeps
## a global cap on the foe bullets alive.
## [FoeShooter] never schedules formation shots on its own: the director only
## decides who and when. Entry and dive shots are local to each foe and ignore
## the cap.

## When false no new formation shots start.
@export var enabled: bool = true
## Shortest delay between two formation shots, in seconds.
@export var interval_min: float = 1.0
## Longest delay between two formation shots, in seconds.
@export var interval_max: float = 2.5
## Live foe bullets, dive and entry shots included, at which no formation shot
## starts any more.
@export var max_foe_bullets: int = 6

var _countdown: float = 0.0


func _ready() -> void:
	_countdown = _random_interval()


func _physics_process(delta: float) -> void:
	if not enabled or FoeBrain.is_capture_in_progress():
		return
	_countdown -= delta
	if _countdown > 0.0:
		return
	_countdown = _random_interval()
	if _count_foe_bullets() >= max_foe_bullets:
		return
	# A busy weapon or an impossible shot just moves on to the next candidate.
	var candidates: Array[FoeShooter] = _get_candidates()
	candidates.shuffle()
	for shooter: FoeShooter in candidates:
		if shooter.fire_from_formation():
			return


## The shooters of every foe in formation whose wave allows formation fire.
func _get_candidates() -> Array[FoeShooter]:
	var shooters: Array[FoeShooter] = []
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		if not is_instance_valid(node):
			continue
		var brain: FoeBrain = node as FoeBrain
		if brain == null:
			continue
		var entity: Entity = brain.get_parent() as Entity
		if entity == null:
			continue
		var shooter: FoeShooter = entity.get_node_or_null(^"FoeShooter") as FoeShooter
		if shooter != null and shooter.can_fire_in_formation():
			shooters.append(shooter)
	return shooters


## Counts every live projectile of the foe team, wherever it came from.
func _count_foe_bullets() -> int:
	var container: Node = get_tree().get_first_node_in_group(&"projectiles")
	if container == null:
		return 0
	var count: int = 0
	for node: Node in container.get_children():
		var projectile: Projectile = node as Projectile
		if projectile != null and projectile.team == Helpers.TEAM.FOE:
			count += 1
	return count


func _random_interval() -> float:
	return randf_range(minf(interval_min, interval_max), maxf(interval_min, interval_max))
