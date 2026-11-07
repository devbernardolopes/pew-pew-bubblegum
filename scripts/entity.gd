@tool
class_name Entity
extends Area2D

const EffectsScript = preload("res://scripts/effects/effects.gd")
## Visuals is a north-facing Polygon2D filled with a color.
## Collision shape is a CollisionPolygon2D matching visual.

## Emitted when the Entity dies, right before it leaves the tree.
signal died(entity: Entity)
## Emitted when this entity is captured by a tractor beam.
signal capture_started(entity: Entity)
## Emitted when the carrier is back in formation and the life is committed.
signal capture_committed(entity: Entity)
## Emitted when the captured hero is released (no life cost).
signal capture_released(entity: Entity)
## Emitted when a dash starts, with its locked direction (-1 left, 1 right).
@warning_ignore("unused_signal")
signal dash_started(direction: int)
## Emitted when a dash ends, however it ends.
@warning_ignore("unused_signal")
signal dash_ended

@export var data: EntityData = null:
	set(v):
		data = v
		_refresh_shape()

## A little helper so that I can set [param scale] quickly in the Inspector
@export var scale_aux: float = 0.25:
	set(v):
		scale_aux = v
		_refresh_shape()

@export var speed_multiplier: float = 1.0

@export_tool_button("Center") var center_button: Callable = _center_entity
@export_tool_button("Refresh Visual") var refresh_visual_button: Callable = _refresh_shape

var collision: CollisionPolygon2D = null
var visual: Polygon2D = null
var controller: EntityController = null
## The first [Weapon] child: the primary, which foes, [FoeBrain] and the
## tractor beam keep using exactly as before.
var weapon: Weapon = null
## Every [Weapon] child by its [member Weapon.weapon_id]. [member weapon] is
## the primary of the same set.
var weapons: Dictionary = {}
var dash_ability: DashAbility = null
var charge_effect: ChargeEffect = null
## Momentum drift state, only when [member EntityData.drift_enabled] is on.
## [Fleet] ships never use their own: the fleet owns one for the whole block.
var lateral_motion: LateralMotion = null
var health: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var is_dead: bool = false
## Whether damage and tractor beams ignore this Entity. The dash drives it.
var invulnerable: bool = false
## Whether this entity is currently captured by a tractor beam.
var capture_active: bool = false
## Whether this ship is flying back to its fleet after being freed.
var returning: bool = false
## Whether another node (the [Fleet]) owns this entity's position and firing.
var externally_driven: bool = false
## Score multiplier (e.g. 2 while a foe is diving). Set by the brain.
var score_multiplier: int = 1

const TILT_STEPS: float = 24.0
const TILT_DEADZONE: float = 0.04
const TELEPORT_SPEED_FACTOR: float = 4.0

var _base_points: PackedVector2Array = PackedVector2Array()
var _tilt: float = 0.0
var _tilt_applied: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _motion_primed: bool = false
var _trail_distance: float = 0.0
## The visual's position as set by [_refresh_shape], restored after a charge.
var _visual_base_position: Vector2 = Vector2.ZERO
## Physics seconds of the current charge, driving the visual shake.
var _charge_elapsed: float = 0.0
## Current horizontal shake offset of the visual, in local pixels. The ghost
## trail subtracts it so ghosts never inherit the shake.
var _charge_shake_x: float = 0.0


func _ready() -> void:
	collision = CollisionPolygon2D.new()
	visual = Polygon2D.new()
	add_child(collision)
	add_child(visual)
	_refresh_shape()
	reset_health()
	if not Engine.is_editor_hint():
		if controller == null:
			controller = _find_controller()
		_collect_weapons()
		_create_dash_ability()
		_create_charge_effect()
		_create_drift()
		_join_team_group()
		area_entered.connect(_on_area_entered)


#func _process(delta: float) -> void:
	#if not Engine.is_editor_hint():
		#if not data:
			#return
		#if not data.god_mode and data.god_mode_effect:
			#return
		#if not visual:
			#return
		#if not visual.texture:
			#return
		#if not visual.material:
			#return
		#if not visual.material is ShaderMaterial:
			#return
		#var _shader_material: ShaderMaterial = (visual.material as ShaderMaterial)
		#var _horizontal_influence_speed: float = 0.2
		#var _horizontal_influence: float = _shader_material.get_shader_parameter("horizontal_influence")
		#var _new_horiontal_influence: float = clampf(lerpf(_horizontal_influence, 1.0, _horizontal_influence_speed * delta), 0.5, 1.0)
		#_shader_material.set_shader_parameter("horizontal_influence", _new_horiontal_influence)
		#print(_horizontal_influence, " -> ", _new_horiontal_influence)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not data:
		reset_drift()
		return
	if is_dead:
		reset_drift()
		return
	_update_motion_feedback(delta)
	if capture_active or returning or externally_driven:
		reset_drift()
		# Another node owns this entity's position (a capture, the fleet, a brain).
		# Fleet ships get their charge visual from the Fleet, not from here.
		return
	var request: StringName = controller.get_fire_request() if controller != null else &""
	var progress: float = controller.get_charge_progress() if controller != null else 0.0
	var is_ready: bool = controller.is_charge_ready() if controller != null else false
	set_charge_visual(progress, is_ready, delta)
	if is_dashing():
		# The DashAbility owns the position while dashing; firing is still allowed.
		reset_drift()
		drive_weapon(request, get_fire_fallback(request))
		return
	if controller != null:
		var dir: float = controller.get_direction_h()
		if lateral_motion != null:
			var top_speed: float = data.base_speed * speed_multiplier
			var requested: float = lateral_motion.step(dir, delta, top_speed,
					data.drift_distance_ships * get_width())
			var moved: float = move_horizontal(requested)
			lateral_motion.report(requested, moved)
		else:
			move_horizontal(dir * data.base_speed * speed_multiplier * delta)
	drive_weapon(request, get_fire_fallback(request))


func _update_motion_feedback(delta: float) -> void:
	if delta <= 0.0 or visual == null:
		return
	var step: Vector2 = global_position - _last_position
	_last_position = global_position
	var top_speed: float = maxf(data.base_speed * speed_multiplier, 1.0)
	var is_motion: bool = _motion_primed and absf(step.x) <= top_speed * TELEPORT_SPEED_FACTOR * delta
	_motion_primed = true
	if data.tilt_enabled:
		var target: float = _tilt
		if is_motion:
			target = clampf(step.x / delta * cos(global_rotation) / top_speed, -1.0, 1.0)
			if absf(target) < TILT_DEADZONE:
				target = 0.0
		_tilt += (target - _tilt) * (1.0 - exp(-data.tilt_response * delta))
		_apply_tilt(false)
	if data.trail_enabled and is_motion:
		_trail_distance += step.length()
		if _trail_distance >= data.trail_spacing:
			_trail_distance = fmod(_trail_distance, data.trail_spacing)
			_spawn_trail()


## Rebuilds the polygons for the current roll, only when the quantized value
## changed (or when [param force] is set).
func _apply_tilt(force: bool) -> void:
	if visual == null or _base_points.is_empty():
		return
	var quantized: float = roundf(_tilt * TILT_STEPS) / TILT_STEPS
	if not force and is_equal_approx(quantized, _tilt_applied):
		return
	_tilt_applied = quantized
	var points: PackedVector2Array = _base_points
	if quantized != 0.0:
		points = Helpers.roll_polygon(
			_base_points, deg_to_rad(data.tilt_max_angle) * quantized, data.tilt_perspective)
	visual.polygon = points
	if data.tilt_affects_collision and collision != null:
		collision.set_deferred(&"polygon", points)


## Applies this frame's facing feedback and firing. [Fleet] calls it for the
## ships it owns, which have no controller of their own.
func drive(wants_fire: bool) -> void:
	if wants_fire and weapon != null:
		weapon.fire()


## The weapon with [param id], or null when this Entity has none.
func get_weapon(id: StringName) -> Weapon:
	return weapons.get(id) as Weapon


## Whether the weapon with [param id] would fire right now.
func can_fire_weapon(id: StringName) -> bool:
	var found: Weapon = get_weapon(id)
	return found != null and found.can_fire()


## Fires the weapon with [param id] when it can, otherwise the weapon with
## [param fallback_id] when one is given (a charged shot falls back to the
## primary, so a shot is never lost). Returns whether a shot was fired.
func drive_weapon(id: StringName, fallback_id: StringName = &"") -> bool:
	if id == &"":
		return false
	var found: Weapon = get_weapon(id)
	if found != null and found.can_fire():
		found.fire()
		return true
	if fallback_id != &"":
		var fallback: Weapon = get_weapon(fallback_id)
		if fallback != null and fallback.can_fire():
			fallback.fire()
			return true
	return false


## The fallback for a fire request: the primary for a charged shot, nothing
## for any other weapon (a missile whose pool is full fires nothing).
func get_fire_fallback(request: StringName) -> StringName:
	if data != null and data.charge_enabled and request == data.charge_weapon_id:
		return &"primary"
	return &""


## Shows the charge at [param progress] (0..1) on this ship: the particles of
## [member charge_effect] plus a horizontal shake of the visual only, so
## clamping, collision and the dash are untouched. Progress 0 restores the
## visual's base position exactly. [Fleet] calls it for the ships it owns;
## [method _physics_process] calls it for a ship with its own controller.
func set_charge_visual(progress: float, is_ready: bool, delta: float) -> void:
	if charge_effect != null:
		charge_effect.set_progress(progress, is_ready)
	if visual == null or data == null:
		return
	if progress <= 0.0:
		_charge_elapsed = 0.0
		_charge_shake_x = 0.0
		visual.position = _visual_base_position
		return
	_charge_elapsed += delta
	_charge_shake_x = sin(_charge_elapsed * TAU * data.charge_shake_hz) * data.charge_shake_px * progress
	visual.position = _visual_base_position + Vector2(_charge_shake_x, 0.0)

## Sets [member health] back to the maximum of [member data]. Use it when
## [member data] is assigned after the Entity entered the tree.
func reset_health() -> void:
	if data == null:
		return
	health = data.max_health


## Points awarded for destroying this Entity right now.
func get_score_value() -> int:
	if data == null:
		return 0
	return data.score_value * score_multiplier


## Subtracts [param amount] from [member health], killing the Entity when it
## runs out.
func take_damage(amount: int) -> void:
	if data.god_mode:
		return
	if is_dead or invulnerable:
		return
	if capture_active or returning:
		return
	health -= amount
	# Non-lethal hit: white flash for ~0.08 s
	if health > 0:
		if visual != null:
			visual.color = Color.WHITE
			var flash_tween: Tween = create_tween()
			flash_tween.tween_interval(0.08)
			flash_tween.tween_property(visual, ^"color", data.color, 0.0)
	if health <= 0:
		die()
	else:
		_play_profile_stream("hit")


## Marks the Entity dead and removes it from the tree, so nothing else can hit
## it on the way out.
func die() -> void:
	if is_dead:
		return
	is_dead = true
	cancel_dash()
	reset_drift()
	set_charge_visual(0.0, false, 0.0)
	# Sound effect before visuals/freeing
	_play_profile_stream("explosion")
	# Explosion and score popup before freeing
	var explosion_scale: float = 1.0
	if data != null:
		explosion_scale = data.explosion_scale
	EffectsScript.explode(data.visual, scale_aux, global_position, data.color, explosion_scale,
			data.center_on_bounds)
	if data is BossData:
		EffectsScript.camera_punch(0.04, 0.20)
	# The popup and the score are awarded here so that every way of dying pays
	# out once: bullets, ramming, or anything added later.
	if data != null and data.score_value > 0:
		EffectsScript.score_popup(global_position, data.score_value * score_multiplier, score_multiplier > 1)
		GameManager.add_score(get_score_value())
	set_deferred(&"monitorable", false)
	set_deferred(&"monitoring", false)
	died.emit(self)
	queue_free()


## Starts capture: freeze the hero, disable monitoring, emit signal.
func begin_capture() -> void:
	capture_active = true
	cancel_dash()
	reset_drift()
	set_charge_visual(0.0, false, 0.0)
	set_deferred(&"monitorable", false)
	capture_started.emit(self)


## Hides the hero while being pulled/parked.
func park_captured() -> void:
	cancel_dash()
	reset_drift()
	set_charge_visual(0.0, false, 0.0)
	visible = false


## Commits the capture: the life is lost, the hero is freed by the caller.
func commit_capture() -> void:
	capture_active = false
	capture_committed.emit(self)


## Releases the hero with no life cost: shows it again and flags it as flying
## back to its fleet. The [Fleet] owns its position until it docks.
func begin_return() -> void:
	cancel_dash()
	reset_drift()
	set_charge_visual(0.0, false, 0.0)
	rotation = 0.0
	visible = true
	capture_active = false
	returning = true
	set_deferred(&"monitorable", false)
	capture_released.emit(self)


## Whether a tractor beam may grab this entity: a live friend that is in play.
func is_capturable() -> bool:
	if data == null or data.team != Helpers.TEAM.FRIEND:
		return false
	if is_dead or is_queued_for_deletion() or invulnerable:
		return false
	return not capture_active and not returning


## Starts a dash towards [param direction] (-1 left, 1 right).
func try_dash(direction: int) -> bool:
	return dash_ability != null and dash_ability.try_dash(direction)


## Whether a dash is currently running, which also means [member invulnerable].
func is_dashing() -> bool:
	return dash_ability != null and dash_ability.is_dashing()


## Whether [method try_dash] would start a dash now.
func can_dash() -> bool:
	return dash_ability != null and dash_ability.can_dash()


## Seconds a dash press is remembered while no direction is held.
func get_dash_input_buffer() -> float:
	return data.dash_input_buffer if data != null else 0.0


## Ends a running dash, restoring the alpha cue and invulnerability.
func cancel_dash() -> void:
	if dash_ability != null:
		dash_ability.cancel()


## Forgets any momentum slide in progress. Called on every early return of
## [method _physics_process] and when the entity dies, is captured or starts
## its return flight.
func reset_drift() -> void:
	if lateral_motion != null:
		lateral_motion.reset()


## Full visual width of this Entity, in pixels. The same value drives the
## fleet's docking offset, clamping and the dash distance.
func get_width() -> float:
	return Helpers.ENTITY_WIDTH * scale_aux


## Half of [method get_width], the distance from the centre to a side.
func get_half_width() -> float:
	return get_width() / 2.0


## How many pixels this Entity can still move towards [param direction]
## (-1 left, 1 right) before the screen-edge clamp of [method move_horizontal]
## stops it. Zero or less when already against that edge.
func get_room_horizontal(direction: int) -> float:
	if direction == 0:
		return 0.0
	if direction > 0:
		return _clamped_x(position.x + get_viewport_rect().size.x) - position.x
	return position.x - _clamped_x(position.x - get_viewport_rect().size.x)


## Moves [param delta_x] pixels horizontally, clamped by the same screen edges
## as normal movement. Returns the progress the clamp actually allowed.
func move_horizontal(delta_x: float) -> float:
	var before: float = position.x
	position.x = _clamped_x(before + delta_x)
	return position.x - before


## The screen-edge clamp shared by [method move_horizontal] and
## [method get_room_horizontal].
func _clamped_x(x: float) -> float:
	return clampf(x, get_half_width(), get_viewport_rect().size.x - get_half_width())


## Plays a sound profile stream by key.
func play_sound(key: String) -> void:
	if data == null or data.sound_profile == null:
		return
	_play_profile_stream(key)


func _center_entity() -> void:
	# The editor viewport is not the game viewport, so read the project setting.
	var viewport_width: float = Helpers.get_game_width()
	position.x = viewport_width / 2.0


func _refresh_shape() -> void:
	if not data or not collision:
		return
	var points: PackedVector2Array = Helpers.get_polygon(data.visual)
	_base_points = points
	collision.set_deferred("polygon", points)
	visual.polygon = points
	collision.scale = Vector2.ONE * scale_aux
	visual.scale = Vector2.ONE * scale_aux
	# Center the collision and the polygon in the Area2D on both axes, so that
	# the Entity pivots around the center of its shape. Shapes larger than the
	# 128 x 128 box (bosses) are centered on their own bounding box instead.
	var pivot: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH
	if data.center_on_bounds:
		pivot = Helpers.get_points_center(points)
	collision.position = -pivot * scale_aux
	visual.position = -pivot * scale_aux
	_visual_base_position = visual.position
	visual.color = data.color
	if data.tilt_enabled:
		_apply_tilt(true)
	else:
		_tilt = 0.0
		_tilt_applied = 0.0
	if data.god_mode and data.god_mode_effect:
		var _shader_material: ShaderMaterial = ShaderMaterial.new()
		var _shader: Shader = preload("res://shaders/moving_rainbow_gradient.gdshader")
		visual.texture = preload("res://resources/textures/gradient_texture_2d_01.tres")
		#if not visual.material:
		_shader_material.shader = _shader
		_shader_material.set_shader_parameter("strength", 0.5)
		_shader_material.set_shader_parameter("speed", 0.5)
		_shader_material.set_shader_parameter("angle", 0.025)
		visual.material = _shader_material
		#visual.texture = preload("res://resources/textures/curve_texture_01.tres")
	_apply_layers()


## Assigns the physics layers of this Entity according to its team.
## Only one side of an interaction lists the other in its mask, otherwise
## every hit fires twice.
func _apply_layers() -> void:
	match data.team:
		Helpers.TEAM.FRIEND:
			collision_layer = PhysicsLayers.FRIEND
			collision_mask = 0
		Helpers.TEAM.FOE:
			collision_layer = PhysicsLayers.FOE
			collision_mask = PhysicsLayers.FRIEND
		Helpers.TEAM.NEUTRAL:
			collision_layer = 0
			collision_mask = 0


## Adds the Entity to its team group so that other nodes can look it up at
## runtime. Groups are runtime-only, so the editor scene tree stays clean.
func _join_team_group() -> void:
	if data == null:
		return
	match data.team:
		Helpers.TEAM.FRIEND:
			add_to_group(&"friend")
		Helpers.TEAM.FOE:
			add_to_group(&"foe")
		Helpers.TEAM.NEUTRAL:
			pass


## Handles ramming. Only the monitoring side of an interaction ever receives
## this (the foe, whose mask lists FRIEND), so each contact is handled once.
func _on_area_entered(area: Area2D) -> void:
	var other: Entity = area as Entity
	if other == null or is_dead or other.is_dead:
		return
	# A dashing Entity passes through ramming untouched, and the contact does
	# not destroy either side.
	if invulnerable or other.invulnerable:
		return
	other.take_damage(data.contact_damage)
	if data.dies_on_contact:
		die()


## Adds the reusable dash component when this Entity's data enables it, and
## reports dash configuration problems in debug builds.
func _create_dash_ability() -> void:
	if data == null or not data.dash_enabled:
		return
	dash_ability = DashAbility.new()
	dash_ability.name = "DashAbility"
	add_child(dash_ability)
	if OS.is_debug_build():
		for issue: String in data.validate_dash("Entity %s" % name, speed_multiplier, scale_aux):
			push_warning(issue)


## Adds the charge particles when this Entity's data enables charging, at the
## charge weapon's muzzle, and reports charge and combo configuration
## problems in debug builds.
func _create_charge_effect() -> void:
	if data == null:
		return
	if OS.is_debug_build():
		var weapon_ids: Array[StringName] = []
		for id: StringName in weapons:
			weapon_ids.append(id)
		for issue: String in data.validate_charge("Entity %s" % name, weapon_ids):
			push_warning(issue)
	if not data.charge_enabled:
		return
	charge_effect = ChargeEffect.new()
	charge_effect.name = "ChargeEffect"
	add_child(charge_effect)
	charge_effect.configure(data.color, data.charge_ring_radius,
			data.charge_particles_min, data.charge_particles_max)
	var charge_weapon: Weapon = get_weapon(data.charge_weapon_id)
	if charge_weapon != null:
		charge_effect.position = charge_weapon.get_muzzle_local()
	else:
		charge_effect.position = Vector2.UP * Helpers.ENTITY_HALF_WIDTH * scale_aux


## Creates the momentum drift state when this Entity's data enables it, and
## reports drift configuration problems in debug builds. A stage change or
## game over also resets the slide, like the dash does.
func _create_drift() -> void:
	if data == null:
		return
	if OS.is_debug_build():
		for issue: String in data.validate_drift("Entity %s" % name, speed_multiplier, scale_aux):
			push_warning(issue)
	if not data.drift_enabled:
		return
	lateral_motion = LateralMotion.new()
	if not GameManager.stage_changed.is_connected(_on_drift_stage_changed):
		GameManager.stage_changed.connect(_on_drift_stage_changed)
	if not GameManager.game_over.is_connected(_on_drift_game_over):
		GameManager.game_over.connect(_on_drift_game_over)


func _on_drift_stage_changed(_stage: int) -> void:
	reset_drift()


func _on_drift_game_over() -> void:
	reset_drift()


## Collects every [Weapon] child by its id; the first one is [member weapon],
## the primary. A duplicate id warns once and keeps the first weapon.
func _collect_weapons() -> void:
	weapons.clear()
	weapon = null
	for child: Node in get_children():
		if not child is Weapon:
			continue
		var found: Weapon = child as Weapon
		if weapon == null:
			weapon = found
		if weapons.has(found.weapon_id):
			push_warning("Entity %s: duplicate weapon id %s; the first weapon wins." % [
					name, found.weapon_id])
			continue
		weapons[found.weapon_id] = found


func _find_controller() -> EntityController:
	for child: Node in get_children():
		if child is EntityController:
			return child as EntityController
	return null


func _find_weapon() -> Weapon:
	for child: Node in get_children():
		if child is Weapon:
			return child as Weapon
	return null


func _play_profile_stream(key: String) -> void:
	if data == null or data.sound_profile == null:
		return
	var stream: AudioStream = null
	if key == "explosion":
		stream = data.sound_profile.explosion
	elif key == "fire":
		stream = data.sound_profile.fire
	elif key == "hit":
		stream = data.sound_profile.hit
	elif key == "tractor_beam_grow":
		stream = data.sound_profile.tractor_beam_grow
	elif key == "tractor_beam_capture":
		stream = data.sound_profile.tractor_beam_capture
	if stream == null:
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.autoplay = false
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(func() -> void: player.queue_free())


## Leaves a fading copy of the current shape right behind this entity.
func _spawn_trail() -> void:
	var parent: Node = get_parent()
	if parent == null or visual == null:
		return
	var ghost: Polygon2D = Polygon2D.new()
	ghost.polygon = visual.polygon
	ghost.color = visual.color
	# Not frozen with the rest of $Entities while a rescued ship flies home.
	ghost.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(ghost)
	# Draw it just behind this entity, not on top of everything.
	parent.move_child(ghost, get_index())
	# Same transform as the visual, so it lines up exactly (offset, scale, rotation).
	ghost.global_transform = visual.global_transform
	# The charge shake is visual-only: ghosts must not inherit it.
	ghost.global_position -= Vector2(_charge_shake_x, 0.0).rotated(global_rotation)
	ghost.modulate.a = data.trail_alpha
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, ^"modulate:a", 0.0, data.trail_lifetime).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ghost.queue_free)


func _pulse_fire() -> void:
	if visual == null:
		return
	# Tween the channels only, never the alpha: the dash owns the alpha cue and
	# the ghost trail has its own modulate. This keeps the two effects apart.
	var pulse_tween: Tween = create_tween()
	pulse_tween.tween_property(visual, ^"modulate:r", 2.0, 0.05)
	pulse_tween.parallel().tween_property(visual, ^"modulate:g", 2.0, 0.05)
	pulse_tween.parallel().tween_property(visual, ^"modulate:b", 2.0, 0.05)
	pulse_tween.tween_property(visual, ^"modulate:r", 1.0, 0.15)
	pulse_tween.parallel().tween_property(visual, ^"modulate:g", 1.0, 0.15)
	pulse_tween.parallel().tween_property(visual, ^"modulate:b", 1.0, 0.15)


## Plays the feedback of a shot: the sprite pulse, plus the camera shake when
## this Entity asks for it. [Weapon] calls it after every successful shot, so
## every shooter gets the same behaviour driven by its own [member data].
func play_fire_feedback() -> void:
	if data == null or not data.fire_pulse_enabled:
		return
	_pulse_fire()
	if data.shake_on_fire_enabled:
		EffectsScript.screen_shake(0.2, 0.05)
