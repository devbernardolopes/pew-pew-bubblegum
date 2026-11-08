class_name StageDirector
extends Node
## Spawns waves in order from a [StageData] resource and manages the stage
## lifecycle: intro, spawning, playing, cleared, and game-over stop.
##
## It owns the [Formation] instances of the current stage: one per distinct
## ([FormationData], sway start phase) pair, built when the first wave needs
## it and freed only when the next stage begins, so no foe ever loses the
## slot it was given. Waves sharing both sway in unison; a wave with a
## different [member WaveData.sway_start_phase_deg] gets its own instance.

## An array of [StageData]. 
@export var journey: JourneyData = null
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

## The stage definitions (ordered list for cycling).
var stages: Array[StageData] = []

var _base_max_divers: int = 2
var _base_interval_min: float = 1.5
var _base_interval_max: float = 3.0
var _base_fire_interval_min: float = 1.0
var _base_fire_interval_max: float = 2.5
var _base_max_foe_bullets: int = 6

var _state: int = 0  # 0=INTRO, 1=SPAWNING, 2=PLAYING, 3=CLEARED, 4=STOPPED
var _wave_index: int = 0
## Debug start: index of the first wave of the first stage (set by
## [StagePreview] before the scene enters the tree). 0 in a normal run, so
## every stage starts at its first wave. [_begin_stage] consumes and resets it.
var debug_start_wave: int = 0
var _timer: float = 0.0
var _current_stage_index: int = 0
var _formation_entries: int = 0
var _total_foes_spawned: int = 0
## Key (formation data instance plus sway phase) to the [Formation] built for
## it during the current stage.
var _formations: Dictionary = {}
var _formation_serial: int = 0
## The running boss entrance cinematic of the current stage, if any, and the
## wave whose boss it waits for. Aborted by the next [_begin_stage] or by the
## stage reaching CLEARED/STOPPED (see StageCinematic).
var _cinematic: StageCinematic = null
var _cinematic_wave: BossWaveData = null


func _ready() -> void:
	# CombatGate statics survive a scene reload, so every run starts open.
	CombatGate.clear()
	# Find siblings by name; NodePath references can fail in some contexts.
	if formations_root == null:
		formations_root = get_parent().get_node_or_null("Formations") as Node2D
	if entities == null:
		entities = get_parent().get_node_or_null("Entities") as Node2D
	if dive_director == null:
		dive_director = get_parent().get_node_or_null("DiveDirector") as DiveDirector
	if fire_director == null:
		fire_director = get_parent().get_node_or_null("FireDirector") as FireDirector
	if not journey:
		push_error("StageDirector: journey is empty.")
		_state = 4
		return
	stages = journey.stages
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
	# A still-running cinematic of the previous stage ends here, never
	# leaking its lock or zoom into the new stage.
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.abort()
	_cinematic = null
	_cinematic_wave = null
	_free_formations()
	BossSpawner.pending_pieces = 0
	_formation_entries = 0
	_total_foes_spawned = 0
	_apply_difficulty()
	var current: StageData = _current_stage()
	# First wave index of the first stage (see [member debug_start_wave]): the
	# reset makes every later stage start at wave 0 again.
	var start_wave: int = clampi(debug_start_wave, 0, current.waves.size() - 1) \
			if current != null and not current.waves.is_empty() else 0
	_wave_index = start_wave
	debug_start_wave = 0
	_timer = INTRO_DURATION
	_state = 0
	# Play stage music
	if current != null and current.music_stream != null:
		MusicPlayer.play_music(current.music_stream, MusicPlayer.crossfade_duration, true)
	_start_cinematic(current, start_wave)


## Starts the boss entrance cinematic of [param stage], if it has one: the
## first [BossWaveData] at wave [param start_wave] or later with a non-null
## cinematic. A cinematic whose boss wave is skipped by a debug start wave
## never starts. The ceasefire and the zoom-out begin now, in parallel with
## INTRO, so they coincide with the STAGE banner. Stages without one are
## completely unaffected.
func _start_cinematic(stage: StageData, start_wave: int = 0) -> void:
	if stage == null:
		return
	for i: int in stage.waves.size():
		if i < start_wave:
			continue
		var wave: WaveData = stage.waves[i]
		var boss_wave: BossWaveData = wave as BossWaveData
		if boss_wave == null or boss_wave.cinematic == null:
			continue
		_cinematic_wave = boss_wave
		_cinematic = StageCinematic.new()
		add_child(_cinematic)
		_cinematic.setup(boss_wave.cinematic, self)
		_cinematic.start()
		return


## Whether every live foe is sitting in formation (ignores dead or queued
## foes). Used by the ALL_WAVES_FORMED cinematic condition.
func _all_foes_in_formation() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"foe_brains"):
		if not is_instance_valid(node):
			continue
		var brain: FoeBrain = node as FoeBrain
		if brain == null:
			continue
		var parent_foe: Entity = brain.get_parent() as Entity
		if parent_foe == null or parent_foe.is_dead or parent_foe.is_queued_for_deletion():
			continue
		if brain.state != FoeBrain.State.FORMATION:
			return false
	return true


func _spawn_current_wave() -> void:
	var wave: WaveData = _current_stage().waves[_wave_index]
	if wave.foe_scene == null:
		push_warning("StageDirector: wave %d has no foe_scene; skipping." % _wave_index)
		return
	if formations_root == null or entities == null:
		push_error("StageDirector: formations_root or entities not set.")
		return
	var formation: Formation = _get_formation(wave.formation, wave.sway_start_phase_deg)
	if formation == null:
		push_warning("StageDirector: wave %d has no formation; skipping." % _wave_index)
		return
	# Bosses claim a rectangle of cells instead of filling a row.
	if wave is BossWaveData:
		_spawn_boss(wave as BossWaveData, formation)
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
			# Holes are expected; an all-hole row is caught by validation at startup.
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


## Spawns a boss on its own anchor: the [FoeBrain] settles it like any foe and
## the [BossPattern] moves the anchor (and fires) once it is in formation.
func _spawn_boss(wave: BossWaveData, formation: Formation) -> void:
	var boss: Entity = BossSpawner.spawn(
			wave.foe_scene, entities, formation,
			Rect2i(wave.col, wave.row, wave.col_span, wave.row_span),
			_on_formation_entered, wave.entry_curve, wave.mirror_entry)
	if boss != null:
		_total_foes_spawned += 1
		# The cinematic's wave: its first arrival in formation releases the
		# ceasefire (one shot, in addition to the existing callback).
		if _cinematic != null and is_instance_valid(_cinematic) and wave == _cinematic_wave:
			var brain: FoeBrain = boss.get_node_or_null(^"FoeBrain") as FoeBrain
			if brain != null:
				brain.entered_formation.connect(_cinematic.on_boss_entered, CONNECT_ONE_SHOT)


## Returns the [Formation] of [param data] and [param phase_deg] for the
## current stage, building it on first use. The instance is never rebuilt,
## so its slots outlive every foe; waves sharing the pair share the instance
## and sway in unison.
func _get_formation(data: FormationData, phase_deg: float) -> Formation:
	if data == null or formations_root == null:
		return null
	var phase: float = fposmod(phase_deg, 360.0)
	var key: String = "%d_%.3f" % [data.get_instance_id(), phase]
	if _formations.has(key):
		return _formations[key] as Formation
	var formation: Formation = Formation.new()
	formation.name = "Formation_%d" % _formation_serial
	_formation_serial += 1
	# The layout and phase must be in place before the node enters the tree:
	# _ready() builds the slots from it and never rebuilds them afterwards.
	formation.data = data
	formation.sway_phase = deg_to_rad(phase)
	formations_root.add_child(formation)
	_formations[key] = formation
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
	# A dying boss with pieces counts until its deferred pieces are spawned,
	# so the stage cannot clear in the gap (hazard 1 of the Lego-boss plan).
	return count + BossSpawner.pending_pieces


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
	CombatGate.clear()
	var director: CameraDirector = get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	if director != null:
		director.reset()
