class_name BossPattern
extends Node
## Runs a boss's health phases. It never moves the boss itself: it moves the
## formation anchor the [FoeBrain] follows, and fires through the boss's
## [Weapon] from the muzzle markers under its [code]Muzzles[/code] child.

## Emitted when the boss enters a new phase; nothing listens yet.
signal phase_changed(index: int)

var _entity: Entity = null
var _brain: FoeBrain = null
var _anchor: Marker2D = null
var _home: Vector2 = Vector2.ZERO
var _formation: Formation = null
var _footprint: Rect2i = Rect2i()
var _entered: Callable = Callable()
var _muzzles: Array[Marker2D] = []
var _phase_index: int = -1
var _fire_timer: float = 0.0
var _muzzle_cursor: int = 0
var _move_tween: Tween = null


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("BossPattern must be a child of an Entity; firing disabled.")
		set_physics_process(false)
		return
	_brain = _entity.get_node_or_null(^"FoeBrain") as FoeBrain
	if _brain == null:
		push_error("BossPattern needs a sibling FoeBrain; firing disabled.")
		set_physics_process(false)
		return
	var muzzles: Node = _entity.get_node_or_null(^"Muzzles")
	if muzzles != null:
		for child: Node in muzzles.get_children():
			var muzzle: Marker2D = child as Marker2D
			if muzzle != null:
				_muzzles.append(muzzle)
	if _muzzles.is_empty():
		push_error("BossPattern found no Marker2D under Muzzles; it will never fire.")
	_entity.died.connect(_on_entity_died)


## Stores the anchor the boss follows and the position it sways around, plus
## the split context: the [param formation] and [param footprint] a piece of
## this boss settles into, and the [param entered] callback of
## [signal FoeBrain.entered_formation] passed down to every piece so the
## flawless-victory bookkeeping keeps counting. [StageDirector] (through
## [BossSpawner]) calls it once, right after [method FoeBrain.setup].
func setup(anchor: Marker2D, formation: Formation, footprint: Rect2i, entered: Callable) -> void:
	_anchor = anchor
	_home = anchor.position if anchor != null else Vector2.ZERO
	_formation = formation
	_footprint = footprint
	_entered = entered


## Requests the split of this boss, if it has pieces. Runs synchronously inside
## [signal Entity.died], before [method BossSpawner.request_split] defers the
## spawn, so the pending-piece counter covers the gap (hazard 1); it never
## adds nodes itself.
func _on_entity_died(entity: Entity) -> void:
	var data: BossData = entity.data as BossData
	if data == null or data.pieces.is_empty():
		return
	if _formation == null or not is_instance_valid(_formation):
		return
	BossSpawner.request_split(entity, data, entity.get_parent(), _formation, _footprint, _entered)


func _physics_process(delta: float) -> void:
	if _brain == null or _brain.state != FoeBrain.State.FORMATION:
		return
	if _entity == null or _entity.is_dead or _entity.is_queued_for_deletion():
		return
	var data: BossData = _entity.data as BossData
	if data == null or data.phases.is_empty():
		return
	if _anchor == null or not is_instance_valid(_anchor):
		return
	_update_phase(data)
	_update_fire(delta, data)


## Enters the deepest phase whose threshold the current health fraction meets.
## Phases only advance, never go back.
func _update_phase(data: BossData) -> void:
	var fraction: float = float(_entity.health) / float(maxi(data.max_health, 1))
	var wanted: int = 0
	for i: int in data.phases.size():
		var phase: BossPhaseData = data.phases[i]
		if phase != null and fraction <= phase.health_below:
			wanted = i
	if wanted <= _phase_index:
		return
	_phase_index = wanted
	_enter_phase(data.phases[wanted])


func _enter_phase(phase: BossPhaseData) -> void:
	var target: Vector2 = _home + phase.offset
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	if phase.move_duration <= 0.0:
		_anchor.position = target
	else:
		_move_tween = create_tween()
		_move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_move_tween.tween_property(_anchor, ^"position", target, phase.move_duration)
	_fire_timer = phase.fire_interval
	_muzzle_cursor = 0
	phase_changed.emit(_phase_index)


func _update_fire(delta: float, data: BossData) -> void:
	# The ceasefire gate freezes the timer instead of spending it, so the
	# volley (and the muzzle cursor it advances) is not consumed by a lock.
	if not CombatGate.is_open_for(Helpers.TEAM.FOE):
		return
	var phase: BossPhaseData = data.phases[_phase_index]
	if phase == null:
		return
	_fire_timer -= delta
	if _fire_timer > 0.0:
		return
	_fire_timer = phase.fire_interval
	if phase.fire_pattern == BossPhaseData.FirePattern.NONE:
		return
	# Never fire without a capturable hero, or while a capture is under way:
	# the respawn rule needs a moment without foe-team bullets.
	if FoeBrain.is_capture_in_progress():
		return
	var weapon: Weapon = _entity.weapon
	if weapon == null:
		return
	var target: Entity = _find_target()
	if target == null:
		return
	_fire_volley(phase, weapon, target)


func _fire_volley(phase: BossPhaseData, weapon: Weapon, target: Entity) -> void:
	for muzzle: Marker2D in _get_active_muzzles(phase):
		var base: Vector2 = Vector2.UP.rotated(muzzle.global_rotation)
		match phase.fire_pattern:
			BossPhaseData.FirePattern.AIMED:
				var to_target: Vector2 = target.global_position - muzzle.global_position
				var cone: float = deg_to_rad(phase.aim_cone_deg)
				var aim: float = clampf(base.angle_to(to_target), -cone, cone)
				weapon.fire_from(muzzle.global_position, base.rotated(aim))
			BossPhaseData.FirePattern.SPREAD:
				var count: int = maxi(phase.spread_count, 1)
				var spread: float = deg_to_rad(phase.spread_angle_deg)
				var step: float = 0.0
				if count > 1:
					step = spread / float(count - 1)
				for i: int in count:
					weapon.fire_from(muzzle.global_position, base.rotated(-spread / 2.0 + step * float(i)))
			_:
				weapon.fire_from(muzzle.global_position, base)


## The muzzles this phase uses, or a single one when it alternates.
func _get_active_muzzles(phase: BossPhaseData) -> Array[Marker2D]:
	var active: Array[Marker2D] = []
	if phase.muzzle_indices.is_empty():
		active.assign(_muzzles)
	else:
		for index: int in phase.muzzle_indices:
			if index >= 0 and index < _muzzles.size():
				active.append(_muzzles[index])
	if phase.alternate_muzzles and active.size() > 1:
		var single: Array[Marker2D] = [active[_muzzle_cursor % active.size()]]
		_muzzle_cursor = (_muzzle_cursor + 1) % active.size()
		return single
	return active


## The closest friend that is in play: a returning or captured ship is not a
## target, because it is not where the player is.
func _find_target() -> Entity:
	var target: Entity = null
	var best_distance: float = INF
	var origin: Vector2 = _entity.global_position
	for node: Node in get_tree().get_nodes_in_group(&"friend"):
		var hero: Entity = node as Entity
		if hero == null or not hero.is_capturable():
			continue
		var distance: float = origin.distance_squared_to(hero.global_position)
		if distance < best_distance:
			best_distance = distance
			target = hero
	return target
