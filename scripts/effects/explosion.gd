class_name Explosion
extends Node2D

func setup(visual: Helpers.VISUAL, entity_scale: float, _position: Vector2, color: Color, _scale: float = 1.0) -> void:
	global_position = _position
	var polygon_points: PackedVector2Array = Helpers.get_polygon(visual)
	# Scale points to match the entity's shape size and center at origin
	var offset: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * entity_scale
	var scaled_points: PackedVector2Array = []
	for p in polygon_points:
		scaled_points.append((p - offset) * entity_scale)

	# Triangulate
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(scaled_points)
	if triangles.is_empty():
		queue_free()
		return

	# Build shard polygons from triangles
	var shard_points_list: Array[PackedVector2Array] = []
	for i in range(0, triangles.size(), 3):
		var a: int = triangles[i]
		var b: int = triangles[i + 1]
		var c: int = triangles[i + 2]
		var shard: PackedVector2Array = [scaled_points[a], scaled_points[b], scaled_points[c]]
		shard_points_list.append(shard)

	# Subdivide triangles around centroids until at least 6 shards
	while shard_points_list.size() < 6:
		var new_list: Array[PackedVector2Array] = []
		for shard in shard_points_list:
			var centroid: Vector2 = (shard[0] + shard[1] + shard[2]) / 3.0
			# Subdivide triangle into 3 smaller triangles around centroid
			new_list.append([shard[0], shard[1], centroid])
			new_list.append([shard[1], shard[2], centroid])
			new_list.append([shard[2], shard[0], centroid])
		shard_points_list = new_list

	# Spawn shards
	var base_duration: float = 0.6 * _scale
	for shard in shard_points_list:
		var shard_node: Polygon2D = Polygon2D.new()
		shard_node.polygon = shard
		shard_node.color = color
		shard_node.scale = Vector2.ONE * _scale
		add_child(shard_node)

		# Random outward direction and rotation
		var dir: Vector2 = Vector2.from_angle(randf_range(0.0, TAU))
		var distance: float = randf_range(40.0, 120.0) * _scale
		var rot: float = randf_range(-TAU, TAU)

		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard_node, ^"position", shard_node.position + dir * distance, base_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard_node, ^"rotation", rot, base_duration)
		tween.tween_property(shard_node, ^"scale", Vector2.ZERO, base_duration)
		tween.tween_property(shard_node, ^"modulate:a", 0.0, base_duration)
		tween.tween_callback(func(): shard_node.queue_free())

	# Flash polygon (20-gon)
	var flash_points: PackedVector2Array = []
	for i in 20:
		var ang: float = (i / 20.0) * TAU
		var r: float = randf_range(20.0, 60.0) * _scale
		flash_points.append(Vector2(cos(ang) * r, sin(ang) * r))
	var flash: Polygon2D = Polygon2D.new()
	flash.polygon = flash_points
	flash.color = Color.WHITE
	flash.modulate.a = 0.8
	flash.scale = Vector2.ONE * _scale
	add_child(flash)

	var flash_tween: Tween = create_tween()
	flash_tween.tween_property(flash, ^"scale", Vector2.ONE * 2.5 * _scale, 0.15)
	flash_tween.tween_property(flash, ^"modulate:a", 0.0, 0.3)
	flash_tween.tween_callback(func(): flash.queue_free())

	# Clean up container after all tweens
	var duration: float = base_duration + 0.5
	var cleanup_tween: Tween = create_tween()
	cleanup_tween.tween_interval(duration)
	cleanup_tween.tween_callback(func(): queue_free())
