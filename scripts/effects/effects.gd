class_name Effects
extends RefCounted

const BlastRingScript = preload("res://scripts/effects/blast_ring.gd")
const ExplosionScript = preload("res://scripts/effects/explosion.gd")
const HitSparkScript = preload("res://scripts/effects/hit_spark.gd")
const ScorePopupScript = preload("res://scripts/effects/score_popup.gd")
const ScreenShakeScript = preload("res://scripts/effects/screen_shake.gd")

static func _find_container() -> Node:
	var nodes: Array = Engine.get_main_loop().get_nodes_in_group(&"effects")
	if nodes.is_empty():
		return null
	return nodes[0] as Node

static func explode(polygon_points: PackedVector2Array, entity_scale: float, position: Vector2, color: Color, scale: float = 1.0, center_on_bounds: bool = false) -> void:
	var container: Node = _find_container()
	if container == null:
		return
	var explosion: Node2D = ExplosionScript.new() as Node2D
	container.add_child(explosion)
	explosion.setup(polygon_points, entity_scale, position, color, scale, center_on_bounds)

static func hit_spark(position: Vector2, direction: Vector2 = Vector2.UP, scale: float = 0.2) -> void:
	var container: Node = _find_container()
	if container == null:
		return
	var spark: Node2D = HitSparkScript.new() as Node2D
	container.add_child(spark)
	spark.setup(position, direction, scale)

static func score_popup(position: Vector2, value: int, bonus: bool = false) -> void:
	var container: Node = _find_container()
	if container == null:
		return
	var popup: Node2D = ScorePopupScript.new() as Node2D
	container.add_child(popup)
	popup.setup(position, value, bonus)

static func blast_ring(position: Vector2, radius: float, color: Color) -> void:
	var container: Node = _find_container()
	if container == null:
		return
	var ring: Node2D = BlastRingScript.new() as Node2D
	container.add_child(ring)
	ring.setup(position, radius, color)

static func camera_punch(amount: float = 0.03, duration: float = 0.15) -> void:
	var director: CameraDirector = Engine.get_main_loop().get_first_node_in_group(&"camera_director") as CameraDirector
	if director == null:
		return
	director.punch(amount, duration)

static func screen_shake(intensity: float = 1.0, duration: float = 0.3) -> void:
	var container: Node = _find_container()
	if container == null:
		return
	var shake: Node2D = ScreenShakeScript.new() as Node2D
	container.add_child(shake)
	shake.setup(intensity, duration)
