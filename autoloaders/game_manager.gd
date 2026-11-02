extends Node
## Manages the run state: reserve ships, statistics, game over and restart.

## Emitted whenever the number of reserve ships changes.
signal reserve_ships_changed(reserve_ships: int)
## Emitted once, when the last ship is lost.
signal game_over

## Ships per run: one in play plus the rest in reserve.
const STARTING_SHIPS: int = 3
## Time after game over before the fire button restarts the run, in seconds.
const RESTART_DELAY: float = 1.0

var reserve_ships: int = STARTING_SHIPS - 1
var shots_fired: int = 0
var shots_hit: int = 0
var is_game_over: bool = false
var _game_over_msec: int = 0


func _ready() -> void:
	reset_run()


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		if event.is_action_pressed("escape") and not event.is_echo():
			get_tree().quit()
		if is_game_over and event.is_action_pressed("fire") and not event.is_echo():
			if Time.get_ticks_msec() - _game_over_msec >= int(RESTART_DELAY * 1000.0):
				reset_run()
				get_tree().reload_current_scene()


## Restores all run statistics and reserve ships to their start values.
func reset_run() -> void:
	reserve_ships = STARTING_SHIPS - 1
	shots_fired = 0
	shots_hit = 0
	is_game_over = false
	_game_over_msec = 0
	reserve_ships_changed.emit(reserve_ships)


## Returns true if there is at least one reserve ship left.
func has_reserve_ship() -> bool:
	return reserve_ships > 0


## Consumes one reserve ship. It is called when a new hero spawns, not when
## the old one dies, so the icon disappears the moment the replacement appears.
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


## Marks the run as over. Only emits [signal game_over] once.
func end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	_game_over_msec = Time.get_ticks_msec()
	game_over.emit()


## Returns the number of milliseconds since [method end_game] was called.
func time_since_end() -> int:
	if not is_game_over:
		return 0
	return Time.get_ticks_msec() - _game_over_msec
