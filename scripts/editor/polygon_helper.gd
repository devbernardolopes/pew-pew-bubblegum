@tool
extends Node

@export_tool_button("Save") var save_button: Callable = _save_all
@export_group("Data")
@export_subgroup("Main")
@export var max_health: int = 1
@export var speed_multiplier: float = 1.0
@export var score_value: int = 0
@export var explosion_scale: float = 0.50
@export var sound_profile: SoundProfile = null
@export var tilt_enabled: bool = false
@export var trail_enabled: bool = false
@export var fire_pulse_enabled: bool = false
@export var shake_on_fire_enabled: bool = false
@export var dies_on_contact: bool = true
@export var center_on_bounds: bool = false

@export_subgroup("Tractor Beam")
@export var tractor_beam_enabled: bool = false
@export_range(0.0, 1.0) var tractor_beam_chance: float = 0.3
@export var tractor_beam_open_duration: float = 3.0
@export var tractor_beam_height: float = 400.0
@export var tractor_beam_width: float = 80.0
@export var tractor_beam_grow_duration: float = 1.0
@export var tractor_beam_align_speed: float = 120.0
@export var tractor_beam_pull_speed: float = 90.0
@export var tractor_beam_rescue_bonus: int = 1000

@export_subgroup("Tilt")
@export_range(0.0, 70.0, 0.5, "suffix:°") var tilt_max_angle: float = 50.5
@export_range(0.0, 0.01, 0.0005) var tilt_perspective: float = 0.004
@export_range(1.0, 40.0) var tilt_response: float = 15.0
@export var tilt_affects_collision: bool = false

@export_subgroup("Trail")
@export_range(2.0, 64.0) var trail_spacing: float = 32.0
@export_range(0.05, 1.0) var trail_lifetime: float = 0.25
@export_range(0.0, 1.0) var trail_alpha: float = 0.15

@export_subgroup("Drift")
@export var drift_enabled: bool = false
@export_range(0.0, 16.0, 0.5) var drift_distance_ships: float = 0.5

@export_group("Transform", "move_")
@export_tool_button("^") var move_up_button: Callable = _move_polygons_up
@export_tool_button(">") var move_right_button: Callable = _move_polygons_right
@export_tool_button("v") var move_down_button: Callable = _move_polygons_down
@export_tool_button("<") var move_left_button: Callable = _move_polygons_left
@export var move_step: float = 8.0
## Rotation of the polygon in degress.
## 0 is NORTH, 90 is RIGHT, 180 is DOWN, 270 is LEFT.
@export_range(0.0, 360.0, 0.5) var move_polygon_rotation: float = 0.00:
	set(v):
		move_polygon_rotation = v
		_rotate_polygons(v)
@export_tool_button("Print Points") var print_polygons_button: Callable = _print_polygons


func _get_all() -> Array[Polygon2D]:
	#var file = FileAccess.open("res://resources/cinematics/boss.entrance.tres", FileAccess.READ_WRITE)
	#if not file: pass
	var result: Array[Polygon2D] = []
	var _node = get_node_or_null(".")
	if not _node:
		return result
	if not _node is Polygon2D and not _node is Node2D:
		return result
	if _node is Polygon2D:
		result.append(_node)
		return result
	else:
		var _children = _node.get_children()
		for i in _children.size():
			var _child = _children[i]
			if _child is Polygon2D:
				result.append(_child)
		return result

func _get_name(_polygon_2d: Polygon2D) -> String:
	if not _polygon_2d:
		return ""
	if not _polygon_2d.polygon:
		return ""
	if _polygon_2d.polygon.is_empty():
		return ""
	var _name: String = _polygon_2d.name
	var _fixed_name: String = ""
	for i in _name.length():
		if not i == 0 and not _name[i].is_valid_int() and _name[i] == _name[i].to_upper():
			_fixed_name += "_"
		_fixed_name += _name[i].to_upper()
	return _fixed_name


func _save_all() -> void:
	var _nodes: Array[Polygon2D] = _get_all()
	if not _nodes or _nodes.is_empty():
		return
	for n in _nodes.size():
		var _polygon_2d: Polygon2D = _nodes[n]
		var _fixed_name: String = _get_name(_polygon_2d)
		if not _fixed_name:
			return
		if _fixed_name.begins_with("BOSS"):
			var _boss_data: BossData = BossData.new()
			#_boss_data.speed_multiplier: float = 1.0
			#_boss_data.dies_on_contact: bool = true
			#_boss_data.center_on_bounds: bool = false
			_boss_data.center_on_bounds = true
			_boss_data.color = _polygon_2d.color
			_boss_data.dies_on_contact = false
			_boss_data.id = _fixed_name.to_lower()
			_boss_data.team = Helpers.TEAM.FOE
			_boss_data.max_health = max_health
			_boss_data.score_value = score_value
			_boss_data.explosion_scale = explosion_scale
			_boss_data.sound_profile = sound_profile
			_boss_data.tilt_enabled = tilt_enabled
			_boss_data.trail_enabled = trail_enabled
			_boss_data.shake_on_fire_enabled = shake_on_fire_enabled
			var resource_save_result: Error = ResourceSaver.save(_boss_data, "res://resources/entities/bosses/" + _fixed_name.to_lower() + ".tres")
			#print(resource_save_result)
		elif _fixed_name.begins_with("FOE"):
			pass
		else:
			return


func _move_polygons(direction: Vector2 = Vector2.RIGHT) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var _nodes: Array[Polygon2D] = _get_all()
	if not _nodes or _nodes.is_empty():
		return result 
	for n in _nodes.size():
		var _polygon_2d: Polygon2D = _nodes[n]
		result.resize(_polygon_2d.polygon.size())
		for j in range(_polygon_2d.polygon.size()):
			var p = _polygon_2d.polygon[j] + (direction * move_step)
			result[j] = p
	return result


func _move_polygons_up() -> void:
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Move Polygons Up")
	undo_redo.add_do_property(self, &"polygon", _move_polygons(Vector2.UP))
	undo_redo.add_undo_property(self, &"polygon", self.polygon)
	undo_redo.commit_action()


func _move_polygons_right() -> void:
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Move Polygons Right")
	undo_redo.add_do_property(self, &"polygon", _move_polygons(Vector2.RIGHT))
	undo_redo.add_undo_property(self, &"polygon", self.polygon)
	undo_redo.commit_action()


func _move_polygons_down() -> void:
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Move Polygons Down")
	undo_redo.add_do_property(self, &"polygon", _move_polygons(Vector2.DOWN))
	undo_redo.add_undo_property(self, &"polygon", self.polygon)
	undo_redo.commit_action()


func _move_polygons_left() -> void:
	var undo_redo = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action("Move Polygons Left")
	undo_redo.add_do_property(self, &"polygon", _move_polygons(Vector2.LEFT))
	undo_redo.add_undo_property(self, &"polygon", self.polygon)
	undo_redo.commit_action()


func _print_polygons() -> void:
	var _nodes: Array[Polygon2D] = _get_all()
	if not _nodes or _nodes.is_empty():
		return
	for n in _nodes.size():
		var _polygon_2d: Polygon2D = _nodes[n]
		var _fixed_name: String = _get_name(_polygon_2d)
		if not _fixed_name:
			return
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


func _rotate_polygons(angle_deg: float = 0.00) -> void:
	var _node = get_node_or_null(".")
	if not _node:
		return
	if not _node is Polygon2D and not _node is Node2D:
		return
	var _angle: float = deg_to_rad(angle_deg)
	if _node is Polygon2D:
		_node.polygon = _rotate_polygon(_node.polygon, _angle, _get_polygon_center(_node.polygon))
	else:
		var _children = _node.get_children()
		for i in _children.size():
			var _child = _children[i]
			if _child is Polygon2D:
				_child.polygon = _rotate_polygon(_child.polygon, _angle, _get_polygon_center(_child.polygon))
