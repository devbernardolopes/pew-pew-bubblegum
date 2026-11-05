class_name StageDirector
extends Node
## Spawns waves in order from a [StageData] resource and manages the stage
## lifecycle: intro, spawning, playing, cleared, and game-over stop.
##
## It owns the [Formation] instances of the current stage: one per distinct
## [FormationData], built when the first wave needs it and freed only when the
## next stage begins, so no foe ever loses the slot it was given.

## The stage definitions (ordered list for cycling).
@export var stages: Array[StageData] = []
## Node that holds one [Formation] child per distinct [FormationData].
@export var formations_root: Node2D = null
## Entities container where foes are spawned.
@export var entities: Node2D = null
## Dive director to adjust difficulty and disable dives on game over.
@export var dive_director: DiveDirector = null
## Fire director to adjust the formation fire difficulty.
@export var fire_director: FireDirector = null

## Emitted when the stage is cleared without any foe reaching formation.
signal flawless_victory

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
## Extra foe bullets the fire director allows per stage.
const FIRE_BULLETS_PER_STAGE: int = 1
## Maximum foe bullets the fire director allows at any stage.
const MAX_FOE_BULLETS_CAP: int = 12

var _base_max_divers: int = 2
var _base_interval_min: float = 1.5
var _base_interval_max: float = 3.0
var _base_fire_interval_min: float = 1.0
var _base_fire_interval_max: float = 2.5
var _base_max_foe_bullets: int = 6

var _state: int = 0  # 0=INTRO, 1=SPAWNING, 2=PLAYING, 3=CLEARED, 4=STOPPED
var _wave_index: int = 0
var _timer: float = 0.0
var _current_stage_index: int = 0
var _formation_entries: int = 0
var _total_foes_spawned: int = 0
## [FormationData] to the [Formation] built for it during the current stage.
var _formations: Dictionary = {}
var _formation_serial: int = 0


func _ready() -> void:
	# Find siblings by name; NodePath references can fail in some contexts.
	if formations_root == null:
		formations_root = get_parent().get_node_or_null("Formations") as Node2D
	if entities == null:
		entities = get_parent().get_node_or_null("Entities") as Node2D
	if dive_director == null:
		dive_director = get_parent().get_node_or_null("DiveDirector") as DiveDirector
	if fire_director == null:
		fire_director = get_parent().get_node_or_null("FireDirector") as FireDirector
	if stages.is_empty():
		push_error("StageDirector: stages is empty.")
		_state = 4
		return
	if stages[0] == null or stages[0].waves.is_empty():
		push_error("StageDirector: first stage has no waves.")
		_state = 4
		return
	if dive_director == null:
		push_warning("StageDirector: dive_director not set; difficulty scaling disabled.")
	else:
		# Remember the base settings from the director for difficulty scaling.
		_base_max_divers = dive_director.max_divers
		_base_interval_min = dive_director.interval_min
		_base_interval_max = dive_director.interval_max
	if fire_director == null:
		push_warning("StageDirector: fire_director not set; formation fire stays unscaled.")
	else:
		_base_fire_interval_min = fire_director.interval_min
		_base_fire_interval_max = fire_director.interval_max
		_base_max_foe_bullets = fire_director.max_foe_bullets
	if OS.is_debug_build() and _validate_stages():
		_state = 4
		return
	GameManager.game_over.connect(_on_game_over)
	_begin_stage()


func _physics_process(delta: float) -> void:
	match _state:
		0:  # INTRO
			_timer -= delta
			if _timer <= 0.0:
				_state = 1  # SPAWNING
				_timer = _current_stage().waves[_wave_index].delay
		1:  # SPAWNING
			_timer -= delta
			if _timer <= 0.0:
				_spawn_current_wave()
				_wave_index += 1
				if _wave_index >= _current_stage().waves.size():
					_state = 2  # PLAYING
				else:
					_timer = _current_stage().waves[_wave_index].delay
		2:  # PLAYING
			if _count_live_foes() == 0:
				if _total_foes_spawned > 0 and _formation_entries == 0:
					flawless_victory.emit()
				_state = 3  # CLEARED
				_timer = CLEAR_DELAY
		3:  # CLEARED
			_timer -= delta
			if _timer <= 0.0:
				_current_stage_index = (_current_stage_index + 1) % stages.size()
				GameManager.advance_stage()
				_begin_stage()
		4:  # STOPPED
			pass


func _current_stage() -> StageData:
	return stages[_current_stage_index]

func _begin_stage() -> void:
	_free_formations()
	_formation_entries = 0
	_total_foes_spawned = 0
	_apply_difficulty()
	_wave_index = 0
	_timer = INTRO_DURATION
	_state = 0
	# Play stage music
	var current: StageData = _current_stage()
	if current != null and current.music_stream != null:
		MusicPlayer.play_music(current.music_stream, MusicPlayer.crossfade_duration, true)


func _spawn_current_wave() -> void:
	var wave: WaveData = _current_stage().waves[_wave_index]
	if wave.foe_scene == null:
		push_warning("StageDirector: wave %d has no foe_scene; skipping." % _wave_index)
		return
	if formations_root == null or entities == null:
		push_error("StageDirector: formations_root or entities not set.")
		return
	var formation: Formation = _get_formation(wave.formation)
	if formation == null:
		push_warning("StageDirector: wave %d has no formation; skipping." % _wave_index)
		return

	# Spawn one foe per column in the wave's row, mirrored from the right.
	var row: int = wave.row
	var col_count: int = formation.columns
	var left_n: int = int(float(col_count) / 2.0)
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
		brain.setup(wave.entry_curve, mirror, slot, slot_index * wave.spacing, wave.dive_curves)
		var shooter: FoeShooter = foe.get_node_or_null(^"FoeShooter") as FoeShooter
		if shooter != null:
			shooter.configure(wave)
		brain.entered_formation.connect(_on_formation_entered)
		_total_foes_spawned += 1
		slot_index += 1


## Returns the [Formation] of [param data] for the current stage, building it on
## first use. The instance is never rebuilt, so its slots outlive every foe.
func _get_formation(data: FormationData) -> Formation:
	if data == null or formations_root == null:
		return null
	if _formations.has(data):
		return _formations[data] as Formation
	var formation: Formation = Formation.new()
	formation.name = "Formation_%d" % _formation_serial
	_formation_serial += 1
	# The layout must be in place before the node enters the tree: _ready()
	# builds the slots from it and never rebuilds them afterwards.
	formation.data = data
	formations_root.add_child(formation)
	_formations[data] = formation
	return formation


## Frees every formation of the stage that just ended. Only called when no foe
## is alive, so no brain is left holding a slot that is about to disappear.
func _free_formations() -> void:
	for formation: Formation in _formations.values():
		if is_instance_valid(formation):
			formation.queue_free()
	_formations.clear()


## Prints the problems of every stage and returns whether any of them is an
## error, which stops the director before the first stage starts.
func _validate_stages() -> bool:
	var has_errors: bool = false
	for stage: StageData in stages:
		if stage == null:
			push_error("StageDirector: a stage in the list is null.")
			has_errors = true
			continue
		for issue: String in stage.validate():
			if issue.begins_with("[error]"):
				push_error(issue)
				has_errors = true
			else:
				push_warning(issue)
	return has_errors


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
	var s: int = max(0, GameManager.stage - 1)
	var factor: float = maxf(1.0 - INTERVAL_SHRINK_PER_STAGE * float(s), INTERVAL_MIN_FACTOR)
	if dive_director != null:
		var extra_divers: int = floori(float(s) / float(STAGES_PER_EXTRA_DIVER))
		var new_max: int = mini(_base_max_divers + extra_divers, MAX_DIVERS_CAP)
		dive_director.max_divers = new_max
		dive_director.interval_min = _base_interval_min * factor
		dive_director.interval_max = _base_interval_max * factor
	if fire_director != null:
		fire_director.interval_min = _base_fire_interval_min * factor
		fire_director.interval_max = _base_fire_interval_max * factor
		fire_director.max_foe_bullets = mini(
				_base_max_foe_bullets + s * FIRE_BULLETS_PER_STAGE, MAX_FOE_BULLETS_CAP)


func _on_formation_entered() -> void:
	_formation_entries += 1


func _on_game_over() -> void:
	_state = 4  # STOPPED
