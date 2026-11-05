@tool
extends Node

@export_tool_button("Print Points") var print_polygons_button: Callable = _print_polygons


func _print_polygons() -> void:
	var _node = get_node_or_null(".")
	if not _node:
		return
	if not _node is Polygon2D or not _node is Node2D:
		return
	if _node is Node2D:
		var _children = _node.get_children()
		for i in _children.size():
			var _child = _children[i]
			if _child is Polygon2D:
				_print_points(_child)


func _print_points(_polygon_2d: Polygon2D) -> void:
	if not _polygon_2d:
		return
	if not _polygon_2d.polygon:
		return
	if _polygon_2d.polygon.is_empty():
		return
	#var _name: String = name.to_upper()
	var _name: String = name
	var _fixed_name: String = ""
	for i in _name.length():
		_fixed_name += _name[i].to_upper()
		if not i == 0 and not _name[i].is_valid_int() and _name[i] == _name[i].to_upper():
			_fixed_name += "_"
	print("const ", _fixed_name, "_POLYGON: PackedVector2Array = [")
	for i in _polygon_2d.polygon.size():
		var _point: Vector2 = _polygon_2d.polygon[i]
		print("\tVector2", _point, ",")
	print("]")
	print()
