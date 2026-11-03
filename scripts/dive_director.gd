class_name DiveDirector
extends Node
## Decides when and who dives. It waits until the whole wave is in formation,
## then picks a foe at random every so often.
## [FoeBrain] never schedules its own dives, and the curves come from the foe's
## [WaveData]: the director only decides who and when.

## When false no new dives start; later phases can pause dives with it.
@export var enabled: bool = true
## Maximum number of foes diving at the same time.
@export var max_divers: int = 2
## Shortest delay between two dives, in seconds.
@export var interval_min: float = 1.5
## Longest delay between two dives, in seconds.
@export var interval_max: float = 3.0

var _countdown: float = 0.0


func _ready() -> void:
	_countdown = _random_interval()


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var brains: Array[FoeBrain] = _get_brains()
	if brains.is_empty():
		return
	for brain: FoeBrain in brains:
		if brain.state == FoeBrain.State.WAITING or brain.state == FoeBrain.State.ENTERING:
			return
	_countdown -= delta
	if _countdown > 0.0:
		return
	_countdown = _random_interval()
	var divers: int = 0
	var candidates: Array[FoeBrain] = []
	for brain: FoeBrain in brains:
		match brain.state:
			FoeBrain.State.DIVING:
				divers += 1
			FoeBrain.State.FORMATION:
				if brain.has_dive_curves():
					candidates.append(brain)
	if divers >= max_divers or candidates.is_empty():
		return
	var chosen: FoeBrain = candidates.pick_random()
	chosen.dive(_is_on_right_half(chosen))


func _get_brains() -> Array[FoeBrain]:
	var brains: Array[FoeBrain] = []
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		if is_instance_valid(node):
			var brain: FoeBrain = node as FoeBrain
			if brain != null:
				brains.append(brain)
	return brains


func _random_interval() -> float:
	return randf_range(minf(interval_min, interval_max), maxf(interval_min, interval_max))


## Right-half foes dive on the mirrored curve.
func _is_on_right_half(brain: FoeBrain) -> bool:
	var entity: Entity = brain.get_parent() as Entity
	if entity == null:
		return false
	return entity.global_position.x > Helpers.get_game_width() / 2.0
