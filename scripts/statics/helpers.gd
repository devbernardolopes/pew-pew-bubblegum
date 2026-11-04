class_name Helpers

enum VISUAL {
	BULLET = 10,
	TRIANGLE = 100,
	DOUBLE_SQUARE = 101,
	DECAGON = 102,
	KITE = 103,
	TRAPEZOID = 104,
	STAR = 105,
	BOW_TIE = 106,
	TURRET = 107,
	H = 108,
}

enum TEAM {
	FOE,
	FRIEND,
	NEUTRAL,
}

const TRIANGLE_POLYGON: PackedVector2Array = [
	Vector2(64, 0), 
	Vector2(0, 128), 
	Vector2(128, 128),
	]

const DOUBLE_SQUARE_POLYGON: PackedVector2Array = [
	Vector2(0, 64), 
	Vector2(32, 0), 
	Vector2(64, 64),
	Vector2(96, 0),
	Vector2(128, 64),
	Vector2(128, 128),
	Vector2(64, 128),
	Vector2(0, 128),
	]

const DECAGON_POLYGON: PackedVector2Array = [
	Vector2(8.0, 24.0),
	Vector2(40.0, 0.0),
	Vector2(88.0, 0.0),
	Vector2(120.0, 24.0),
	Vector2(128.0, 64.0),
	Vector2(120.0, 104.0),
	Vector2(88.0, 128.0),
	Vector2(40.0, 128.0),
	Vector2(8.0, 104.0),
	Vector2(0.0, 64.0),
]

const KITE_POLYGON: PackedVector2Array = [
	Vector2(0.0, 88.0),
	Vector2(32.0, 64.0),
	Vector2(64.0, 0.0),
	Vector2(96.0, 64.0),
	Vector2(128.0, 88.0),
	Vector2(64.0, 128.0),
]

const TRAPEZOID_POLYGON: PackedVector2Array = [
	Vector2(0.0, 64.0),
	Vector2(32.0, 0.0),
	Vector2(96.0, 0.0),
	Vector2(128.0, 64.0),
	Vector2(128.0, 128.0),
	Vector2(0.0, 128.0),
]

const STAR_POLYGON: PackedVector2Array = [
	Vector2(0.0, 64.0),
	Vector2(40.0, 40.0),
	Vector2(64.0, 0.0),
	Vector2(88.0, 40.0),
	Vector2(128.0, 64.0),
	Vector2(88.0, 88.0),
	Vector2(64.0, 128.0),
	Vector2(40.0, 88.0),
]

const BOW_TIE_POLYGON: PackedVector2Array = [
	Vector2(0.0, 0.0),
	Vector2(64.0, 48.0),
	Vector2(128.0, 0.0),
	Vector2(128.0, 128.0),
	Vector2(64.0, 80.0),
	Vector2(0.0, 128.0),
]

const TURRET_POLYGON: PackedVector2Array = [
	Vector2(0.0, 128.0),
	Vector2(16.0, 88.0),
	Vector2(8.0, 64.0),
	Vector2(24.0, 56.0),
	Vector2(32.0, 0.0),
	Vector2(40.0, 56.0),
	Vector2(56.0, 64.0),
	Vector2(40.0, 88.0),
	Vector2(64.0, 80.0),
	Vector2(88.0, 88.0),
	Vector2(72.0, 64.0),
	Vector2(88.0, 56.0),
	Vector2(96.0, 0.0),
	Vector2(104.0, 56.0),
	Vector2(120.0, 64.0),
	Vector2(112.0, 88.0),
	Vector2(128.0, 128.0),
	Vector2(112.0, 128.0),
	Vector2(112.0, 120.0),
	Vector2(96.0, 120.0),
	Vector2(96.0, 128.0),
	Vector2(32.0, 128.0),
	Vector2(32.0, 120.0),
	Vector2(16.0, 120.0),
	Vector2(16.0, 128.0),
]

const H_POLYGON: PackedVector2Array = [
	Vector2(24.0, 8.0),
	Vector2(0.0, 128.0),
	Vector2(40.0, 128.0),
	Vector2(40.0, 88.0),
	Vector2(88.0, 88.0),
	Vector2(88.0, 128.0),
	Vector2(128.0, 128.0),
	Vector2(104.0, 8.0),
	Vector2(88.0, 0.0),
	Vector2(88.0, 48.0),
	Vector2(40.0, 48.0),
	Vector2(40.0, 0.0),
]

const ENTITY_WIDTH: float = 128.0
const ENTITY_HALF_WIDTH: float = ENTITY_WIDTH / 2.0

const BULLET_POLYGON: PackedVector2Array = [
	Vector2(52, 0),
	Vector2(76, 0),
	Vector2(76, 128),
	Vector2(52, 128),
	]


static func get_polygon(_visual: VISUAL = VISUAL.TRIANGLE) -> PackedVector2Array:
	var result: PackedVector2Array = [Vector2.ZERO]
	match _visual:
		VISUAL.BULLET:
			return BULLET_POLYGON.duplicate()
		VISUAL.TRIANGLE:
			return TRIANGLE_POLYGON.duplicate()
		VISUAL.DOUBLE_SQUARE:
			return DOUBLE_SQUARE_POLYGON.duplicate()
		VISUAL.DECAGON:
			return DECAGON_POLYGON.duplicate()
		VISUAL.KITE:
			return KITE_POLYGON.duplicate()
		VISUAL.TRAPEZOID:
			return TRAPEZOID_POLYGON.duplicate()
		VISUAL.STAR:
			return STAR_POLYGON.duplicate()
		VISUAL.BOW_TIE:
			return BOW_TIE_POLYGON.duplicate()
		VISUAL.TURRET:
			return TURRET_POLYGON.duplicate()
		VISUAL.H:
			return H_POLYGON.duplicate()
	return result


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
