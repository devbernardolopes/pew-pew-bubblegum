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
var weapon: Weapon = null
var health: int = 0
var shots_fired: int = 0
var shots_hit: int = 0
var is_dead: bool = false
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
		if weapon == null:
			weapon = _find_weapon()
		_join_team_group()
		area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not data:
		return
	if is_dead:
		return
	_update_motion_feedback(delta)
	if capture_active or returning or externally_driven:
		# Another node owns this entity's position (a capture, the fleet, a brain).
		return
	var wants_fire: bool = false
	if controller != null:
		var dir: float = controller.get_direction_h()
		position.x += dir * data.base_speed * speed_multiplier * delta
		position.x = clampf(position.x,
			Helpers.ENTITY_HALF_WIDTH * scale_aux,
			get_viewport_rect().size.x - (Helpers.ENTITY_HALF_WIDTH * scale_aux))
		wants_fire = controller.wants_fire()
	drive(wants_fire)


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
	if is_dead:
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
	# Sound effect before visuals/freeing
	_play_profile_stream("explosion")
	# Explosion and score popup before freeing
	var explosion_scale: float = 1.0
	if data != null:
		explosion_scale = data.explosion_scale
	EffectsScript.explode(data.visual, scale_aux, global_position, data.color, explosion_scale)
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
	set_deferred(&"monitorable", false)
	capture_started.emit(self)


## Hides the hero while being pulled/parked.
func park_captured() -> void:
	visible = false


## Commits the capture: the life is lost, the hero is freed by the caller.
func commit_capture() -> void:
	capture_active = false
	capture_committed.emit(self)


## Releases the hero with no life cost: shows it again and flags it as flying
## back to its fleet. The [Fleet] owns its position until it docks.
func begin_return() -> void:
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
	if is_dead or is_queued_for_deletion():
		return false
	return not capture_active and not returning


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
	# the Entity pivots around the center of its shape.
	collision.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.color = data.color
	if data.tilt_enabled:
		_apply_tilt(true)
	else:
		_tilt = 0.0
		_tilt_applied = 0.0
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
	other.take_damage(data.contact_damage)
	die()


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
	ghost.modulate.a = data.trail_alpha
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, ^"modulate:a", 0.0, data.trail_lifetime).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ghost.queue_free)


func _pulse_fire() -> void:
	if visual == null:
		return
	var pulse_tween: Tween = create_tween()
	pulse_tween.tween_property(visual, ^"modulate", Color(2.0, 2.0, 2.0), 0.05)
	pulse_tween.tween_property(visual, ^"modulate", Color.WHITE, 0.15)


## Plays the feedback of a shot: the sprite pulse, plus the camera shake when
## this Entity asks for it. [Weapon] calls it after every successful shot, so
## every shooter gets the same behaviour driven by its own [member data].
func play_fire_feedback() -> void:
	if data == null or not data.fire_pulse_enabled:
		return
	_pulse_fire()
	if data.shake_on_fire_enabled:
		EffectsScript.screen_shake(0.2, 0.05)
