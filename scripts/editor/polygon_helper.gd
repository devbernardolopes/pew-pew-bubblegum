@tool
extends Node

@export_tool_button("Print Points") var print_polygons_button: Callable = _print_polygons
@export_tool_button("Rotate Polygons") var rotate_polygons_button: Callable = _rotate_polygons


func _print_polygons() -> void:
	var _node = get_node_or_null(".")
	if not _node:
		return
	if not _node is Polygon2D and not _node is Node2D:
		return
	if _node is Polygon2D:
		_print_points(_node as Polygon2D)
	else:
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
	var _name: String = _polygon_2d.name
	var _fixed_name: String = ""
	for i in _name.length():
		if not i == 0 and not _name[i].is_valid_int() and _name[i] == _name[i].to_upper():
			_fixed_name += "_"
		_fixed_name += _name[i].to_upper()
	print("const ", _fixed_name, "_POLYGON: PackedVector2Array = [")
	for i in _polygon_2d.polygon.size():
		var _point: Vector2 = _polygon_2d.polygon[i]
		print("\tVector2", _point, ",")
	print("]")
	print()

## Rotates a PackedVector2Array by a given angle (in radians) around a pivot point.
func _rotate_polygon(polygon: PackedVector2Array, angle: float, pivot: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var rotated_polygon = PackedVector2Array()
	rotated_polygon.resize(polygon.size())
	
	# Pre-calculate sine and cosine for performance
	var cos_a = cos(angle)
	var sin_a = sin(angle)
	
	for i in range(polygon.size()):
		# 1. Translate the point so the pivot is at the origin (0,0)
		var p = polygon[i] - pivot
		
		# 2. Apply the 2D rotation matrix
		var rotated_x = p.x * cos_a - p.y * sin_a
		var rotated_y = p.x * sin_a + p.y * cos_a
		
		# 3. Translate the point back to its original position relative to the pivot
		rotated_polygon[i] = Vector2(rotated_x, rotated_y) + pivot
		
	return rotated_polygon


## Calculates the center (centroid) of a PackedVector2Array
func _get_polygon_center(polygon: PackedVector2Array) -> Vector2:
	var center = Vector2.ZERO
	for p in polygon:
		center += p
	return center / polygon.size()


func _rotate_polygons() -> void:
	var _node = get_node_or_null(".")
	if not _node:
		return
	if not _node is Polygon2D and not _node is Node2D:
		return
	if _node is Polygon2D:
		_node.polygon = _rotate_polygon(_node.polygon, PI, _get_polygon_center(_node.polygon))
	else:
		var _children = _node.get_children()
		for i in _children.size():
			var _child = _children[i]
			if _child is Polygon2D:
				_child.polygon = _rotate_polygon(_child.polygon, PI, _get_polygon_center(_child.polygon))
