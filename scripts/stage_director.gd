class_name StageDirector
extends Node
## Spawns waves in order from a [StageData] resource and manages the stage
## lifecycle: intro, spawning, playing, cleared, and game-over stop.

## The stage definition (list of waves).
@export var stage_data: StageData = null
## Formation node that holds the slots.
@export var formation: Formation = null
## Entities container where foes are spawned.
@export var entities: Node2D = null
## Dive director to adjust difficulty and disable dives on game over.
@export var dive_director: DiveDirector = null

## Duration of the "STAGE N" banner before the first wave starts.
const INTRO_DURATION: float = 2.0
## Pause after the last foe dies before advancing to the next stage.
const CLEAR_DELAY: float = 1.5
## Maximum concurrent divers at any stage.
const MAX_DIVERS_CAP: int = 4
## How many stages pass before one extra diver is allowed.
const STAGES_PER_EXTRA_DIVER: int = 2
## Per-stage interval shrink factor applied to the dive interval range.
const INTERVAL_SHRINK_PER_STAGE: float = 0.1
## Minimum factor applied to the base interval range (stops shrinking here).
const INTERVAL_MIN_FACTOR: float = 0.5

var _base_max_divers: int = 2
var _base_interval_min: float = 1.5
var _base_interval_max: float = 3.0

var _state: int = 0  # 0=INTRO, 1=SPAWNING, 2=PLAYING, 3=CLEARED, 4=STOPPED
var _wave_index: int = 0
var _timer: float = 0.0


func _ready() -> void:
	# Find siblings by name; NodePath references can fail in some contexts.
	if formation == null:
		formation = get_parent().get_node_or_null("Formation") as Formation
	if entities == null:
		entities = get_parent().get_node_or_null("Entities") as Node2D
	if dive_director == null:
		dive_director = get_parent().get_node_or_null("DiveDirector") as DiveDirector
	if stage_data == null:
		push_error("StageDirector: stage_data is null.")
		_state = 4
		return
	if stage_data.waves.is_empty():
		push_error("StageDirector: stage_data has no waves.")
		_state = 4
		return
	if dive_director == null:
		push_warning("StageDirector: dive_director not set; difficulty scaling disabled.")
	# Remember the base settings from the director for difficulty scaling.
	_base_max_divers = dive_director.max_divers
	_base_interval_min = dive_director.interval_min
	_base_interval_max = dive_director.interval_max
	GameManager.game_over.connect(_on_game_over)
	_begin_stage()


func _physics_process(delta: float) -> void:
	match _state:
		0:  # INTRO
			_timer -= delta
			if _timer <= 0.0:
				_state = 1  # SPAWNING
				_timer = stage_data.waves[_wave_index].delay
		1:  # SPAWNING
			_timer -= delta
			if _timer <= 0.0:
				_spawn_current_wave()
				_wave_index += 1
				if _wave_index >= stage_data.waves.size():
					_state = 2  # PLAYING
				else:
					_timer = stage_data.waves[_wave_index].delay
		2:  # PLAYING
			if _count_live_foes() == 0:
				_state = 3  # CLEARED
				_timer = CLEAR_DELAY
		3:  # CLEARED
			_timer -= delta
			if _timer <= 0.0:
				GameManager.advance_stage()
				_begin_stage()
		4:  # STOPPED
			pass


func _begin_stage() -> void:
	_apply_difficulty()
	_wave_index = 0
	_timer = INTRO_DURATION
	_state = 0


func _spawn_current_wave() -> void:
	var wave: WaveData = stage_data.waves[_wave_index]
	if wave.foe_scene == null:
		push_warning("StageDirector: wave %d has no foe_scene; skipping." % _wave_index)
		return
	if formation == null or entities == null:
		push_error("StageDirector: formation or entities not set.")
		return
	# Spawn one foe per column in the wave's row, mirrored from the right.
	var row: int = wave.row
	var col_count: int = formation.columns
	var left_n: int = col_count / 2
	var slot_index: int = 0
	for col: int in col_count:
		var mirror: bool = col >= left_n
		var slot: Marker2D = formation.get_slot(row, col)
		if slot == null:
			push_warning("StageDirector: slot (%d, %d) is null; skipping." % [row, col])
			continue
		var foe: Entity = wave.foe_scene.instantiate() as Entity
		entities.add_child(foe)
		var brain: FoeBrain = foe.get_node("FoeBrain") as FoeBrain
		brain.setup(wave.entry_curve, mirror, slot, slot_index * wave.spacing)
		slot_index += 1


func _count_live_foes() -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		if not is_instance_valid(node):
			continue
		var brain: FoeBrain = node as FoeBrain
		if brain == null:
			continue
		var parent_foe: Entity = brain.get_parent() as Entity
		if parent_foe == null:
			continue
		if parent_foe.is_dead or parent_foe.is_queued_for_deletion():
			continue
		count += 1
	return count


func _apply_difficulty() -> void:
	if dive_director == null:
		return
	var s: int = max(0, GameManager.stage - 1)
	var extra_divers: int = floori(float(s) / float(STAGES_PER_EXTRA_DIVER))
	var new_max: int = mini(_base_max_divers + extra_divers, MAX_DIVERS_CAP)
	dive_director.max_divers = new_max
	var factor: float = maxf(1.0 - INTERVAL_SHRINK_PER_STAGE * float(s), INTERVAL_MIN_FACTOR)
	dive_director.interval_min = _base_interval_min * factor
	dive_director.interval_max = _base_interval_max * factor


func _on_game_over() -> void:
	_state = 4  # STOPPED
