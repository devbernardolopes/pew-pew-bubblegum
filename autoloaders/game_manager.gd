extends Node
## Manages the run state: reserve ships, statistics, stage, high score, game
## over and restart.

## Emitted whenever the number of reserve ships changes.
signal reserve_ships_changed(reserve_ships: int)
## Emitted once, when the last ship is lost.
signal game_over
## Emitted whenever the score changes.
signal score_changed(score: int)
## Emitted whenever the high score changes.
signal high_score_changed(high_score: int)
## Emitted whenever the stage advances.
signal stage_changed(stage: int)

## Ships per run: one in play plus the rest in reserve.
const STARTING_SHIPS: int = 4
## Time after game over before the fire button restarts the run, in seconds.
const RESTART_DELAY: float = 1.0
## Default file path for the persistent high score.
const DEFAULT_HIGH_SCORE_PATH: String = "user://high_score.cfg"

var reserve_ships: int = STARTING_SHIPS - 1
var shots_fired: int = 0
var shots_hit: int = 0
var score: int = 0
var high_score: int = 0
var is_new_high_score: bool = false
var stage: int = 1
var is_game_over: bool = false
var _game_over_msec: int = 0
## The file path used for saving / loading the high score. Overridable so
## tests can use a temporary file.
var high_score_path: String = DEFAULT_HIGH_SCORE_PATH


func _ready() -> void:
	_load_high_score()
	reset_run()


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		if event.is_action_pressed("escape") and not event.is_echo():
			_save_high_score()
			get_tree().quit()
		if is_game_over and event.is_action_pressed("fire") and not event.is_echo():
			if time_since_end() >= int(RESTART_DELAY * 1000.0):
				reset_run()
				get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_high_score()


## Restores all run statistics and reserve ships to their start values.
func reset_run() -> void:
	reserve_ships = STARTING_SHIPS - 1
	shots_fired = 0
	shots_hit = 0
	score = 0
	is_new_high_score = false
	stage = 1
	is_game_over = false
	_game_over_msec = 0
	reserve_ships_changed.emit(reserve_ships)
	score_changed.emit(score)
	stage_changed.emit(stage)


## Returns true if there is at least one reserve ship left.
func has_reserve_ship() -> bool:
	return reserve_ships > 0


## Consumes one reserve ship.
func use_reserve_ship() -> void:
	reserve_ships = maxi(reserve_ships - 1, 0)
	reserve_ships_changed.emit(reserve_ships)


## Adds to the run's accumulated statistics.
func record_shots(fired: int, hit: int) -> void:
	shots_fired += fired
	shots_hit += hit


## Returns the run's hit ratio, or 0.0 when nothing was fired.
func get_hit_ratio() -> float:
	if shots_fired == 0:
		return 0.0
	return float(shots_hit) / float(shots_fired)


## Adds to the score and updates the high score if exceeded.
func add_score(points: int) -> void:
	if points <= 0:
		return
	score += points
	score_changed.emit(score)
	if score > high_score:
		high_score = score
		is_new_high_score = true
		high_score_changed.emit(high_score)


## Advances the stage number and emits the change signal.
func advance_stage() -> void:
	stage += 1
	stage_changed.emit(stage)


## Marks the run as over. Only emits [signal game_over] once.
func end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	_game_over_msec = Time.get_ticks_msec()
	game_over.emit()
	if MusicPlayer != null and MusicPlayer.game_over_music != null:
		MusicPlayer.play_music(MusicPlayer.game_over_music)
	_save_high_score()


## Returns the number of milliseconds since [method end_game] was called.
func time_since_end() -> int:
	if not is_game_over:
		return 0
	return Time.get_ticks_msec() - _game_over_msec


func _load_high_score() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(high_score_path)
	if err == OK:
		high_score = int(config.get_value("scores", "high_score", 0))
	else:
		high_score = 0


func _save_high_score() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("scores", "high_score", high_score)
	var err: int = config.save(high_score_path)
	if err != OK:
		push_warning("GameManager: failed to save high score to %s (error %d)" % [high_score_path, err])
