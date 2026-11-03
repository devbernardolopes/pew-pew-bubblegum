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

## The Color used to fill the Polygon2D of this Entity instance
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		if visual:
			visual.color = v

## A little helper so that I can set [param scale] quickly in the Inspector
@export var scale_aux: float = 0.25:
	set(v):
		scale_aux = v
		_refresh_shape()

@export var speed_multiplier: float = 1.0

@export_tool_button("Center") var center_button: Callable = _center_entity

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
## Whether this hero is descending back to its home y after being released.
var auto_descending: bool = false
## The y position where the hero should return after release.
var home_y: float = 0.0
## Score multiplier (e.g. 2 while a foe is diving). Set by the brain.
var score_multiplier: int = 1
var _trail_timer: float = 0.0


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
	if capture_active:
		# During capture the hero is frozen; position is controlled by the foe brain.
		return
	if auto_descending:
		# Descending after release; ignore input and stay non-monitorable.
		return
	var dir: float = 0.0
	if controller != null:
		dir = controller.get_direction_h()
		position.x += dir * data.base_speed * speed_multiplier * delta
		position.x = clampf(position.x, 
			Helpers.ENTITY_HALF_WIDTH * scale_aux, 
			get_viewport_rect().size.x - (Helpers.ENTITY_HALF_WIDTH * scale_aux))
	else:
		# Foes and other entities without a controller derive tilt direction from rotation
		dir = cos(rotation - PI / 2.0)
	# Update tilt shader uniform based on horizontal direction
	if data.tilt_enabled and visual != null and visual.material != null:
		var mat: ShaderMaterial = visual.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("tilt_amount", dir)
			mat.set_shader_parameter("glow_amount", clampf(abs(dir) * 2.0, 0.0, 1.0))
	if data.trail_enabled:
		_trail_timer -= delta
		if abs(dir) > 0.01 and _trail_timer <= 0.0:
			_trail_timer = 0.06
			_spawn_trail()
	if weapon != null and controller != null and controller.wants_fire() and not capture_active:
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
	if capture_active or auto_descending:
		return
	health -= amount
	# Non-lethal hit: white flash for ~0.08 s
	if health > 0:
		if visual != null:
			visual.color = Color.WHITE
			var flash_tween: Tween = create_tween()
			flash_tween.tween_interval(0.08)
			flash_tween.tween_property(visual, ^"color", color, 0.0)
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
	EffectsScript.explode(data.visual, scale_aux, global_position, color, explosion_scale)
	# The popup and the score are awarded here so that every way of dying pays
	# out once: bullets, ramming, or anything added later.
	if data != null and data.score_value > 0:
		EffectsScript.score_popup(global_position, data.score_value * score_multiplier, score_multiplier > 1)
		GameManager.add_score(get_score_value())
	# Screen shake only when hero dies
	if data != null and data.team == Helpers.TEAM.FRIEND:
		EffectsScript.screen_shake(1.0, 0.3)
	set_deferred(&"monitorable", false)
	set_deferred(&"monitoring", false)
	died.emit()
	#died.emit(self)
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


## Releases the hero with no life cost: shows it at the given world position
## and starts an automatic descent to [member home_y].
func release_from_capture(world_position: Vector2) -> void:
	global_position = world_position
	rotation = 0
	visible = true
	capture_active = false
	auto_descending = true
	set_deferred(&"monitorable", false)
	var target_y: float = home_y
	var dist: float = absf(world_position.y - target_y)
	if dist < 1.0:
		auto_descending = false
		set_deferred(&"monitorable", true)
		capture_released.emit(self)
		return
	var tween: Tween = create_tween()
	tween.tween_property(self, ^"global_position:y", target_y, dist / 400.0)
	tween.tween_callback(func() -> void:
		auto_descending = false
		set_deferred(&"monitorable", true)
		capture_released.emit(self)
	)


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
	collision.polygon = points
	visual.polygon = points
	collision.scale = Vector2.ONE * scale_aux
	visual.scale = Vector2.ONE * scale_aux
	# Center the collision and the polygon in the Area2D on both axes, so that
	# the Entity pivots around the center of its shape.
	collision.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.color = color
	if data.tilt_enabled:
		if visual.material == null or visual.material.get_shader() == null:
			var shader_mat: ShaderMaterial = ShaderMaterial.new()
			shader_mat.shader = preload("res://shaders/tilt_shader.gdshader")
			visual.material = shader_mat
	else:
		if visual.material != null and visual.material.get_shader() != null:
			visual.material = null
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


func _spawn_trail() -> void:
	if not is_instance_valid(self) or is_queued_for_deletion():
		return
	var ghost: Polygon2D = Polygon2D.new()
	if visual != null:
		ghost.polygon = visual.polygon
		ghost.color = color
		ghost.scale = visual.scale
		var trail_dir: float = controller.get_direction_h() if controller != null else cos(rotation - PI / 2.0)
		ghost.position = global_position + Vector2(20, 0) * -sign(trail_dir)
	get_tree().current_scene.add_child(ghost)
	var tween: Tween = ghost.create_tween()
	tween.tween_property(ghost, ^"modulate:a", 0.0, 0.3)
	tween.tween_callback(Callable(ghost.queue_free))


func _pulse_fire() -> void:
	if visual == null:
		return
	var pulse_tween: Tween = create_tween()
	pulse_tween.tween_property(visual, ^"modulate", Color(2.0, 2.0, 2.0), 0.05)
	pulse_tween.tween_property(visual, ^"modulate", color, 0.15)


## Plays the feedback of a shot: the sprite pulse, plus the camera shake when
## this Entity asks for it. [Weapon] calls it after every successful shot, so
## every shooter gets the same behaviour driven by its own [member data].
func play_fire_feedback() -> void:
	if data == null or not data.fire_pulse_enabled:
		return
	_pulse_fire()
	if data.shake_on_fire_enabled:
		EffectsScript.screen_shake(0.2, 0.05)
