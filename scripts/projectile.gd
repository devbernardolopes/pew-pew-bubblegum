class_name Projectile
extends Area2D
## A bullet that damages the opposing team's Entities on contact.
## Built entirely in code: [Weapon] creates it, adds it to the projectiles
## container and then calls [method launch].
## The projectile is the monitoring side: it lists the target team's Entity
## layer in its mask, and Entities do not list projectile layers in theirs,
## otherwise every hit would fire twice.

var _data: ProjectileData = null
var _direction: Vector2 = Vector2.UP
var _shooter: Entity = null
var _spent: bool = false


func _physics_process(delta: float) -> void:
	if _data == null:
		return
	global_position += _direction * _data.base_speed * delta
	# The margin covers the whole bullet, so it vanishes only once fully
	# off-screen. It stays small on purpose: waiting foes are parked at y = -64.
	var margin: float = Helpers.ENTITY_HALF_WIDTH * _data.visual_scale
	if not get_viewport_rect().grow(margin).has_point(global_position):
		queue_free()


## Starts the projectile moving. Call it after adding the projectile to the tree.
## [param team] is the shooter's team; it decides the collision layers.
func launch(data: ProjectileData, team: Helpers.TEAM, shooter: Entity, spawn_position: Vector2, direction: Vector2) -> void:
	_data = data
	_shooter = shooter
	_direction = direction.normalized()
	_build_shapes()
	global_position = spawn_position
	rotation = _direction.angle() + PI / 2.0
	_apply_layers(team)
	monitorable = false
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	var target: Entity = area as Entity
	if target == null or target.is_dead:
		return
	_spent = true
	target.take_damage(_data.base_damage)
	if is_instance_valid(_shooter):
		_shooter.shots_hit += 1
	queue_free()


## Assigns the physics layers of this Projectile according to the shooter's team.
## Only one side of an interaction lists the other in its mask, otherwise
## every hit fires twice.
func _apply_layers(team: Helpers.TEAM) -> void:
	match team:
		Helpers.TEAM.FRIEND:
			collision_layer = PhysicsLayers.FRIEND_PROJECTILE
			collision_mask = PhysicsLayers.FOE
		Helpers.TEAM.FOE:
			collision_layer = PhysicsLayers.FOE_PROJECTILE
			collision_mask = PhysicsLayers.FRIEND
		Helpers.TEAM.NEUTRAL:
			collision_layer = 0
			collision_mask = 0


func _build_shapes() -> void:
	var points: PackedVector2Array = Helpers.get_polygon(_data.visual)
	var offset: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * _data.visual_scale * -1.0
	var collision: CollisionPolygon2D = CollisionPolygon2D.new()
	collision.polygon = points
	collision.scale = Vector2.ONE * _data.visual_scale
	collision.position = offset
	add_child(collision)
	var visual: Polygon2D = Polygon2D.new()
	visual.polygon = points
	visual.scale = Vector2.ONE * _data.visual_scale
	visual.position = offset
	visual.color = _data.color
	add_child(visual)
