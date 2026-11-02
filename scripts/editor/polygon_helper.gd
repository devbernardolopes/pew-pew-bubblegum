@tool
extends Node

@export_tool_button("Print Points") var print_points_button: Callable = _print_points


func _print_points() -> void:
	var _node = get_node_or_null(".")
	if not _node:
		return
	if not _node is Polygon2D:
		return
	var _polygon_2d: Polygon2D = _node as Polygon2D
	if not _polygon_2d.polygon:
		return
	if _polygon_2d.polygon.is_empty():
		return
	print("const DECAGON_POLYGON: PackedVector2Array = [")
	for i in _polygon_2d.polygon.size():
		var _point: Vector2 = _polygon_2d.polygon[i]
		print("\tVector2", _point, ",")
	print("]")
