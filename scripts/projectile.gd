class_name Projectile
extends Area2D

const EffectsScript = preload("res://scripts/effects/effects.gd")

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
## Damage of the next hit; falls off per [member ProjectileData.pierce_count].
var _damage: int = 0
var _pierce_left: int = 0
var _hit_counted: bool = false
## The shooter's team, set when [method launch] is called.
var team: Helpers.TEAM = Helpers.TEAM.NEUTRAL


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
func launch(data: ProjectileData, _team: Helpers.TEAM, shooter: Entity, spawn_position: Vector2, direction: Vector2) -> void:
	_data = data
	_shooter = shooter
	self.team = _team
	_direction = direction.normalized()
	_damage = data.base_damage
	_pierce_left = 0 if data.explode_on_contact else data.pierce_count
	_build_shapes()
	global_position = spawn_position
	rotation = _direction.angle() + PI / 2.0
	_apply_layers(_team)
	monitorable = false
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	if _spent:
		return
	var target: Entity = area as Entity
	if target == null or target.is_dead:
		return
	# A dashing (invulnerable) Entity is ignored like in ramming, and the
	# bullet keeps flying. Area2D only reports an overlap on entry, so a
	# bullet already overlapping the hero when the dash ends does not hit
	# it; that small grace is accepted.
	if target.invulnerable:
		return
	# Spark streak at impact point
	EffectsScript.hit_spark(global_position, _direction, 0.2)
	if _data.explode_on_contact:
		_spent = true
		var center: Vector2 = global_position
		var direct: Entity = target
		var data: ProjectileData = _data
		var shooter: Entity = _shooter
		var projectile_team: Helpers.TEAM = team
		call_deferred("_explode", center, direct, data, shooter, projectile_team)
		return
	target.take_damage(_damage)
	if not _hit_counted and is_instance_valid(_shooter):
		_shooter.shots_hit += 1
		_hit_counted = true
	if target.is_dead and _pierce_left > 0:
		_pierce_left -= 1
		_damage = maxi(_damage - _data.pierce_damage_falloff, _data.pierce_min_damage)
		return
	_spent = true
	queue_free()


## Applies the direct damage and blast of an exploding projectile. Runs deferred
## so the physics space can be queried outside the area_entered callback, and
## frees this projectile at the end.
func _explode(center: Vector2, direct: Entity, data: ProjectileData, shooter: Entity, projectile_team: Helpers.TEAM) -> void:
	if is_instance_valid(direct) and not direct.is_dead:
		direct.take_damage(data.base_damage)
	if not _hit_counted and is_instance_valid(shooter):
		shooter.shots_hit += 1
		_hit_counted = true
	# Blast query against the opposing team's Entity layer only.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var shape: CircleShape2D = CircleShape2D.new()
	shape.radius = data.explosion_radius
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	match projectile_team:
		Helpers.TEAM.FRIEND:
			params.collision_mask = PhysicsLayers.FOE
		Helpers.TEAM.FOE:
			params.collision_mask = PhysicsLayers.FRIEND
		_:
			params.collision_mask = 0
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var seen: Array[Entity] = []
	for hit: Dictionary in space.intersect_shape(params, 64):
		var collider: Object = hit.get("collider")
		var target: Entity = collider as Entity
		if target == null or seen.has(target):
			continue
		seen.append(target)
		if target.is_dead or target.invulnerable:
			continue
		if target == direct and not data.explosion_hits_direct_target:
			continue
		var distance: float = _distance_to_entity_shape(center, target)
		var t: float = clampf(distance / data.explosion_radius, 0.0, 1.0) if data.explosion_radius > 0.0 else 1.0
		var damage: int = roundi(lerpf(float(data.explosion_damage), float(data.explosion_edge_damage), t))
		if damage < 1:
			continue
		target.take_damage(damage)
	EffectsScript.blast_ring(center, data.explosion_radius, data.color)
	EffectsScript.screen_shake(0.4, 0.2)
	EffectsScript.camera_punch(0.03, 0.15)
	queue_free()


## Distance from [param center] to the nearest point of [param entity]'s
## collision polygon; 0 when the center is inside it. Falls back to the
## entity's origin when it has no usable polygon.
static func _distance_to_entity_shape(center: Vector2, entity: Entity) -> float:
	var collision: CollisionPolygon2D = entity.collision
	if collision == null or collision.polygon.is_empty():
		return center.distance_to(entity.global_position)
	var global_points: PackedVector2Array = []
	for point: Vector2 in collision.polygon:
		global_points.append(collision.global_transform * point)
	if Geometry2D.is_point_in_polygon(center, global_points):
		return 0.0
	var best: float = INF
	for i: int in global_points.size():
		var a: Vector2 = global_points[i]
		var b: Vector2 = global_points[(i + 1) % global_points.size()]
		best = minf(best, center.distance_to(Geometry2D.get_closest_point_to_segment(center, a, b)))
	return best


## Assigns the physics layers of this Projectile according to the shooter's team.
## Only one side of an interaction lists the other in its mask, otherwise
## every hit fires twice.
func _apply_layers(_team: Helpers.TEAM) -> void:
	match _team:
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
	var points: PackedVector2Array = _data.get_polygon()
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


func _find_visual() -> Polygon2D:
	for child: Node in get_children():
		if child is Polygon2D:
			return child as Polygon2D
	return null

func set_color(_color: Color = Color.FUCHSIA) -> void:
	var _visual: Polygon2D = _find_visual()
	if _visual:
		_visual.color = _color
