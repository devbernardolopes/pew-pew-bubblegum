class_name ComboDetector
extends RefCounted
## Watches Input Map actions for the [ComboData] sequences of one Entity.
## [method update] is called once per physics frame by the owning
## [PlayerController] and returns the combo completed on this frame's press
## (whose press is then consumed by the caller), or null. All timing uses
## physics [param delta], so it freezes with the tree; at most one step per
## combo advances per frame, taking the press that matches the next expected
## step first. [code]left[/code], [code]right[/code] and [code]dash[/code]
## are never monitored, so they never break a combo.

var _combos: Array[ComboData] = []
## Next step index expected for each combo.
var _next_step: PackedInt32Array = PackedInt32Array()
## Physics seconds since the last matched step of each combo.
var _time_since_step: PackedFloat32Array = PackedFloat32Array()
## Physics seconds until each combo may fire again.
var _cooldown_left: PackedFloat32Array = PackedFloat32Array()


## Advances every combo by [param delta] and the presses of this frame.
## Returns the combo completed by this frame's press, or null.
func update(delta: float, combos: Array[ComboData], debug: bool = false) -> ComboData:
	_sync(combos)
	if combos.is_empty():
		return null
	for i: int in _combos.size():
		_time_since_step[i] += delta
		_cooldown_left[i] = maxf(_cooldown_left[i] - delta, 0.0)
	var pressed: Array[StringName] = _pressed_actions()
	if pressed.is_empty():
		return null
	for i: int in _combos.size():
		var combo: ComboData = _combos[i]
		if combo == null or combo.steps.is_empty():
			continue
		var expected: StringName = combo.steps[_next_step[i]]
		if pressed.has(expected):
			if _advance(i, combo, expected, debug):
				return combo
		elif combo.strict:
			_reset(i, combo, pressed, debug)
	return null


## Forgets all progress and cooldowns, so a cancelled control state (death,
## capture, rescue flight, ...) never carries a half-typed combo.
func reset() -> void:
	for i: int in _next_step.size():
		_next_step[i] = 0
		_time_since_step[i] = 0.0


## Returns true when combo [param index] completed on [param action].
func _advance(index: int, combo: ComboData, action: StringName, debug: bool) -> bool:
	var next: int = _next_step[index]
	if next > 0:
		if combo.min_step_delay > 0.0 and _time_since_step[index] < combo.min_step_delay:
			# Mashing the expected step too soon is ignored, not a reset.
			if debug:
				print("combo %s: step %d ignored, %.2fs < min %.2fs" % [
						combo.id, next + 1, _time_since_step[index], combo.min_step_delay])
			return false
		var gap: float = combo.get_gap_before(next)
		if _time_since_step[index] > gap:
			if debug:
				print("combo %s: step %d late, %.2fs > %.2fs, reset" % [
						combo.id, next + 1, _time_since_step[index], gap])
			_reset(index, combo, [action], debug)
			return false
	var elapsed: float = _time_since_step[index]
	_next_step[index] = next + 1
	_time_since_step[index] = 0.0
	if debug:
		print("combo %s: step %d/%d (%s) +%.2fs" % [
				combo.id, next + 1, combo.steps.size(), action, elapsed])
	if _next_step[index] < combo.steps.size():
		return false
	# The last step was pressed: the combo completes on this press.
	var was_cooling: bool = _cooldown_left[index] > 0.0
	_next_step[index] = 0
	_time_since_step[index] = 0.0
	_cooldown_left[index] = maxf(combo.cooldown, 0.0)
	if was_cooling:
		if debug:
			print("combo %s: completed on cooldown, suppressed" % combo.id)
		return false
	return true


## Resets combo [param index] after an out-of-order press, restarting it when
## one of the presses is its first step.
func _reset(index: int, combo: ComboData, pressed: Array[StringName], debug: bool) -> void:
	if _next_step[index] == 0:
		return
	_next_step[index] = 0
	_time_since_step[index] = 0.0
	if debug:
		print("combo %s: reset" % combo.id)
	if combo.steps[0] in pressed:
		_next_step[index] = 1
		_time_since_step[index] = 0.0
		if debug:
			print("combo %s: step 1/%d (%s) +0.00s" % [combo.id, combo.steps.size(), combo.steps[0]])


## Every step action of every combo that was pressed this frame, in order.
func _pressed_actions() -> Array[StringName]:
	var monitored: Array[StringName] = []
	for combo: ComboData in _combos:
		if combo == null:
			continue
		for step: StringName in combo.steps:
			if not monitored.has(step):
				monitored.append(step)
	var pressed: Array[StringName] = []
	for action: StringName in monitored:
		if Input.is_action_just_pressed(action):
			pressed.append(action)
	return pressed


## Rebuilds the per-combo state when the combo list changed identity.
func _sync(combos: Array[ComboData]) -> void:
	if _combos.size() == combos.size():
		var same: bool = true
		for i: int in combos.size():
			if _combos[i] != combos[i]:
				same = false
				break
		if same:
			return
	_combos = combos.duplicate()
	_next_step.clear()
	_time_since_step.clear()
	_cooldown_left.clear()
	for i: int in _combos.size():
		_next_step.append(0)
		_time_since_step.append(0.0)
		_cooldown_left.append(0.0)
