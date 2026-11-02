class_name Helpers

enum VISUAL {
	TRIANGLE,
	DOUBLE_SQUARE,
	BULLET,
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
		VISUAL.TRIANGLE:
			return TRIANGLE_POLYGON
		VISUAL.DOUBLE_SQUARE:
			return DOUBLE_SQUARE_POLYGON
		VISUAL.BULLET:
			return BULLET_POLYGON
	return result
