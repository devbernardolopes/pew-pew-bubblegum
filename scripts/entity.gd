@tool
class_name Entity
extends Area2D

const EffectsScript = preload("res://scripts/effects/effects.gd")
## Visuals is a north-facing Polygon2D filled with a color.
## Collision shape is a CollisionPolygon2D matching visual.

## Emitted when the Entity dies, right before it leaves the tree.
signal died(entity: Entity)

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
## Score multiplier (e.g. 2 while a foe is diving). Set by the brain.
var score_multiplier: int = 1


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
	if controller == null:
		return
	if is_dead:
		return
	var dir: float = controller.get_direction_h()
	position.x += dir * data.base_speed * speed_multiplier * delta
	position.x = clampf(position.x, 
			Helpers.ENTITY_HALF_WIDTH * scale_aux, 
			get_viewport_rect().size.x - (Helpers.ENTITY_HALF_WIDTH * scale_aux))
	if weapon != null and controller.wants_fire():
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
	if is_dead:
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
	# Score popup handled by projectile on kill; add here for non-projectile kills (e.g. ramming)
	if data != null and data.score_value > 0:
		EffectsScript.score_popup(global_position, data.score_value * score_multiplier, score_multiplier > 1)
	# Screen shake only when hero dies
	if data != null and data.team == Helpers.TEAM.FRIEND:
		EffectsScript.screen_shake(1.0, 0.3)
	set_deferred(&"monitorable", false)
	set_deferred(&"monitoring", false)
	died.emit(self)
	queue_free()


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
	if stream == null:
		return
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.autoplay = false
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(func() -> void: player.queue_free())
