class_name HitSpark
extends Node2D

func setup(position: Vector2, direction: Vector2 = Vector2.UP, scale: float = 0.2) -> void:
	global_position = position
	var points: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.BULLET)
	var offset: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale
	var scaled_points: PackedVector2Array = []
	for p in points:
		scaled_points.append((p - Vector2(Helpers.ENTITY_WIDTH / 2.0, Helpers.ENTITY_WIDTH / 2.0)) * scale)

	for i in 3:
		var streak: Polygon2D = Polygon2D.new()
		streak.polygon = scaled_points
		streak.color = Color.YELLOW
		streak.scale = Vector2.ONE * scale
		streak.rotation = direction.angle() + randf_range(-0.3, 0.3)
		add_child(streak)

		var streak_tween: Tween = create_tween()
		streak_tween.tween_property(streak, ^"position", streak.position + direction.rotated(randf_range(-0.5, 0.5)) * randf_range(10.0, 30.0) * scale, 0.15)
		streak_tween.tween_property(streak, ^"scale", Vector2.ONE * scale * randf_range(0.1, 0.5), 0.2)
		streak_tween.tween_property(streak, ^"modulate:a", 0.0, 0.2)
		streak_tween.tween_callback(func(): streak.queue_free())

	var cleanup: Tween = create_tween()
	cleanup.tween_interval(0.3)
	cleanup.tween_callback(func(): queue_free())
