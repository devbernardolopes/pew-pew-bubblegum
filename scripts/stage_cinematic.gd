class_name StageCinematic
extends Node
## The boss entrance cinematic. Runs in parallel with the StageDirector's
## INTRO/SPAWNING states (it is not a director state): zoom out, hold a
## [CombatGate] ceasefire until the release condition is met, then lift the
## ceasefire and ease back to 1.0. Frees itself when done or aborted, never
## leaving a lock or a non-1.0 zoom behind.

enum Phase { OUT, WAITING, HOLD, BACK, DONE }

## The [CombatGate] lock reason it owns.
const LOCK_REASON: StringName = &"boss_cinematic"

var _data: CinematicData = null
var _director: StageDirector = null
var _phase: Phase = Phase.OUT
var _clock: float = 0.0
var _hold_elapsed: float = 0.0
var _boss_entered: bool = false
var _finished: bool = false


## Stores the cinematic [param data] and the owning [param director], whose
## state drives the ALL_WAVES_FORMED condition and the abort paths.
func setup(data: CinematicData, director: StageDirector) -> void:
	_data = data
	_director = director


## Starts the cinematic: ceasefire on, zoom-out begins now so it coincides
## with the STAGE banner. Call right after [method setup], from
## [method StageDirector._begin_stage].
func start() -> void:
	if _data == null:
		return
	CombatGate.lock(LOCK_REASON, _data.lock_hero_fire, _data.lock_foe_fire)
	var director: CameraDirector = _camera()
	if director != null:
		director.set_base_zoom(_data.zoom, _data.zoom_out_time, _data.trans, _data.ease_type)
	_phase = Phase.WAITING


## The one-shot Awaited callback: the cinematic's boss reached formation.
func on_boss_entered() -> void:
	_boss_entered = true


## Ends the cinematic early (stage cleared/stopped, game over, or a new stage
## began): lifts the ceasefire, restores the resting camera and frees this
## node. Safe to call after the cinematic already finished.
func abort() -> void:
	if _finished:
		return
	_finished = true
	CombatGate.unlock(LOCK_REASON)
	var director: CameraDirector = _camera()
	if director != null:
		director.reset()
	queue_free()


func _physics_process(delta: float) -> void:
	if _data == null:
		return
	# Abort paths: the stage is over (cleared or stopped, game over included)
	# or the owning director is gone.
	if _director == null or not is_instance_valid(_director) or _director._state >= 3:
		abort()
		return
	_clock += delta
	match _phase:
		Phase.WAITING:
			if _condition_met():
				_phase = Phase.HOLD
				_hold_elapsed = 0.0
		Phase.HOLD:
			_hold_elapsed += delta
			if _hold_elapsed >= _data.hold_time:
				_finish()


## The release condition for the current ceasefire mode, with [member
## CinematicData.max_duration] forcing it in every mode.
func _condition_met() -> bool:
	if _clock >= _data.max_duration:
		return true
	match _data.ceasefire_until:
		CinematicData.CeasefireUntil.BOSS_IN_FORMATION:
			return _boss_entered
		CinematicData.CeasefireUntil.ALL_WAVES_FORMED:
			return _director._state >= 2 and _director._all_foes_in_formation()
		CinematicData.CeasefireUntil.FIXED_DURATION:
			return _clock >= _data.ceasefire_duration
	return true


## BACK: the ceasefire lifts now and the zoom back starts, so the player can
## already shoot while the camera returns; then DONE and this node frees
## itself (the zoom tween lives on the camera, not here).
func _finish() -> void:
	_finished = true
	_phase = Phase.BACK
	CombatGate.unlock(LOCK_REASON)
	var director: CameraDirector = _camera()
	if director != null:
		director.set_base_zoom(1.0, _data.zoom_in_time, _data.trans, Tween.EASE_IN_OUT)
	_phase = Phase.DONE
	queue_free()


func _camera() -> CameraDirector:
	return get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
