class_name Helpers

enum TEAM {
	FOE,
	FRIEND,
	NEUTRAL,
}

const ENTITY_WIDTH: float = 128.0
const ENTITY_HALF_WIDTH: float = ENTITY_WIDTH / 2.0

## Center of the bounding box of [param points], in the same space as them.
## Used to pivot shapes that do not live in the 128 x 128 box, like bosses.
static func get_points_center(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point: Vector2 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return (min_point + max_point) / 2.0


static func get_game_size() -> Vector2:
	# The editor viewport is not the game viewport, so read the project setting.
	var x: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_width"))
	var y: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_height"))
	return Vector2(x, y)


static func get_game_width() -> float:
	# The editor viewport is not the game viewport, so read the project setting.
	return get_game_size().x


## Returns [param points] (in the 0..ENTITY_WIDTH box) deformed as if the shape
## rolled by [param angle] radians around its vertical centre line, seen from
## above with a weak perspective of strength [param perspective].
static func roll_polygon(points: PackedVector2Array, angle: float, perspective: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	result.resize(points.size())
	var center: Vector2 = Vector2.ONE * ENTITY_HALF_WIDTH
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	for i: int in points.size():
		var p: Vector2 = points[i] - center
		# Positive depth is away from the camera: the lowered wing.
		var depth: float = p.x * sin_a
		var factor: float = 1.0 / maxf(1.0 + depth * perspective, 0.2)
		result[i] = center + Vector2(p.x * cos_a, p.y) * factor
	return result


static func get_game_height() -> float:
	# The editor viewport is not the game viewport, so read the project setting.
	return get_game_size().y
