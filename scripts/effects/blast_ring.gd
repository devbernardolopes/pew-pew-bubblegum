class_name BlastRing
extends Node2D

const POINTS: int = 48
const DURATION: float = 0.25


## Expanding ring whose final radius is exactly [param radius], so players can
## read the explosion area.
func setup(_position: Vector2, radius: float, color: Color) -> void:
	global_position = _position
	var points: PackedVector2Array = []
	points.resize(POINTS)
	for i: int in POINTS:
		var ang: float = (float(i) / float(POINTS)) * TAU
		points[i] = Vector2(cos(ang) * radius, sin(ang) * radius)
	var disc: Polygon2D = Polygon2D.new()
	disc.polygon = points
	var bright: Color = color
	bright.v = minf(bright.v + 0.3, 1.0)
	bright.a = 0.6
	disc.color = bright
	disc.scale = Vector2.ONE * 0.2
	add_child(disc)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(disc, ^"scale", Vector2.ONE, DURATION)
	tween.tween_property(disc, ^"modulate:a", 0.0, DURATION)
	tween.chain().tween_callback(func() -> void: queue_free())
