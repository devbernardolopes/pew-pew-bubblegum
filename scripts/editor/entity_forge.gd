@tool
class_name EntityForge
extends Node2D
## Turns the [Polygon2D] sketches of this scene into real entities: an
## [EntityData]/[BossData] in `resources/entities/` and a packed scene in
## `scenes/entities/`.
##
## The forge only writes the fields it owns: `id`, `polygon`, `color`, `team`,
## and for bosses `center_on_bounds = true` and `dies_on_contact = false`,
## plus the scene's `data` reference and (for bosses) the muzzle markers.
## Everything else comes from the templates once and is left alone on
## re-forging, so anything tuned in the inspector after the first forge
## survives reshaping the polygon.
##
## Every [Polygon2D] in the sketch tree is considered (recursive, any depth):
## a name starting with `Foe` (for example `FoeStar`) makes a foe, a name
## starting with `Boss` (for example `BossNeonBehemoth`) makes a boss, and
## anything else is skipped with a warning.
##
## [code]Check[/code] prints the plan without writing anything; the transform
## buttons move and rotate the selected sketch polygons — or all of them —
## keeping their muzzle markers attached, with undo/redo support. New scenes
## are created from the templates as inherited scenes in the editor (so later
## template changes reach every forged entity); outside the editor they are
## saved as standalone copies.
##
## This script is attached to sketch scenes and only runs in the editor;
## editor calls ([code]EditorInterface[/code] undo/redo, selection and the
## filesystem refresh) are guarded by [code]Engine.is_editor_hint()[/code].


## Default templates: a fresh sketch works with zero setup.
@export_group("Templates")
@export var foe_data_template: EntityData = preload("res://resources/entities/templates/foe_template.tres") as EntityData
@export var boss_data_template: BossData = preload("res://resources/entities/templates/boss_template.tres") as BossData
@export var foe_scene_template: PackedScene = preload("res://scenes/entities/templates/foe_template.tscn") as PackedScene
@export var boss_scene_template: PackedScene = preload("res://scenes/entities/templates/boss_template.tscn") as PackedScene

@export_group("Options")
## When on, shapes (and their markers) are translated so their bounds start at
## (0, 0) when forging.
@export var snap_to_origin: bool = true
## When on, updating a boss scene replaces its muzzle children with the ones
## from the sketch.
@export var overwrite_scene_muzzles: bool = true

@export_group("Actions")
@export_tool_button("Check") var check_button: Callable = _check
@export_tool_button("Forge") var forge_button: Callable = _forge

@export_group("Transform", "move_")
@export_tool_button("^") var move_up_button: Callable = _move_up
@export_tool_button(">") var move_right_button: Callable = _move_right
@export_tool_button("v") var move_down_button: Callable = _move_down
@export_tool_button("<") var move_left_button: Callable = _move_left
@export var move_step: float = 8.0
@export_tool_button("Rotate Left") var rotate_left_button: Callable = _rotate_left
@export_tool_button("Rotate Right") var rotate_right_button: Callable = _rotate_right
## Rotation applied by the rotate buttons, in degrees.
@export_range(0.0, 360.0, 0.5) var rotate_step: float = 15.0


## The entity to forge: one [Polygon2D] sketch of the scene.
class ForgePlan:
	extends RefCounted
	var node: Polygon2D = null
	var is_boss: bool = false
	var id: StringName = &""
	var data_path: String = ""
	var scene_path: String = ""
	var root_name: String = ""
	var points: PackedVector2Array = PackedVector2Array()
	var markers: Array[Vector2] = []


## The polygon points of [param node], translated so their bounds start at
## (0, 0) when [member snap_to_origin] is on.
func _shaped_points(node: Polygon2D) -> PackedVector2Array:
	var points: PackedVector2Array = node.polygon.duplicate()
	if snap_to_origin and not points.is_empty():
		var min_point: Vector2 = points[0]
		for point: Vector2 in points:
			min_point = min_point.min(point)
		if min_point != Vector2.ZERO:
			for i: int in points.size():
				points[i] = points[i] - min_point
	return points


## The muzzle markers of [param node] in child order, shifted the same way as
## its points so they stay on the shape.
func _shaped_markers(node: Polygon2D) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var shift: Vector2 = Vector2.ZERO
	if snap_to_origin and not node.polygon.is_empty():
		var min_point: Vector2 = node.polygon[0]
		for point: Vector2 in node.polygon:
			min_point = min_point.min(point)
		shift = -min_point
	for child: Node in node.get_children():
		var marker: Marker2D = child as Marker2D
		if marker != null:
			out.append(marker.position + shift)
	return out


## PascalCase to snake_case: `BossNeonBehemoth` becomes `boss_neon_behemoth`.
func _snake(pascal: String) -> String:
	var out: String = ""
	for i: int in pascal.length():
		var ch: String = pascal[i]
		if i > 0 and ch == ch.to_upper() and ch != ch.to_lower():
			out += "_"
		out += ch.to_lower()
	return out


## Every [Polygon2D] of this sketch tree, recursive and in tree order.
func _sketch_polygons() -> Array[Polygon2D]:
	var result: Array[Polygon2D] = []
	var as_object: Object = self
	if as_object is Polygon2D:
		result.append(as_object as Polygon2D)
		return result
	_collect_polygons(self, result)
	return result


## Appends every [Polygon2D] below [param node] to [param into].
func _collect_polygons(node: Node, into: Array[Polygon2D]) -> void:
	for child: Node in node.get_children():
		if child is Polygon2D:
			into.append(child as Polygon2D)
		_collect_polygons(child, into)


## Builds the forge plan for every sketch polygon, with all errors and
## warnings; two entities resolving to the same id are an error.
func _plan() -> Dictionary:
	var plans: Array = []
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()
	var seen_ids: Dictionary = {}
	for node: Polygon2D in _sketch_polygons():
		var plan := ForgePlan.new()
		plan.node = node
		if node.name.begins_with("Boss"):
			plan.is_boss = true
		elif node.name.begins_with("Foe"):
			plan.is_boss = false
		else:
			warnings.append("skipping \"%s\": the name must start with \"Foe\" or \"Boss\"." % node.name)
			continue
		var snake: String = _snake(node.name)
		if plan.is_boss:
			plan.id = snake.trim_prefix("boss_") as StringName
			plan.data_path = "res://resources/entities/bosses/%s/%s.tres" % [plan.id, plan.id]
			plan.scene_path = "res://scenes/entities/bosses/%s/boss_%s.tscn" % [plan.id, plan.id]
			plan.root_name = node.name
		else:
			plan.id = snake as StringName
			plan.data_path = "res://resources/entities/%s.tres" % plan.id
			plan.scene_path = "res://scenes/entities/%s.tscn" % plan.id
			plan.root_name = "Foe"
		if seen_ids.has(plan.id):
			errors.append("duplicate id \"%s\": \"%s\" and \"%s\" resolve to the same id." % [
					plan.id, seen_ids[plan.id], node.name])
			continue
		seen_ids[plan.id] = node.name
		plan.points = _shaped_points(node)
		plan.markers = _shaped_markers(node)
		if not plan.is_boss and not plan.markers.is_empty():
			warnings.append("\"%s\": foe muzzle markers are ignored." % node.name)
		plans.append(plan)
	for error: String in errors:
		push_error(error)
	for warning: String in warnings:
		push_warning(warning)
	return {"plans": plans, "errors": errors, "warnings": warnings}


## Prints the plan of every entity, one line per entity, without writing
## anything.
func _check() -> void:
	var report: Dictionary = _plan()
	var plans: Array = report["plans"] as Array
	for plan: ForgePlan in plans:
		var action: String = "create" if not ResourceLoader.exists(plan.data_path) else "update"
		print("CHECK (%s): data=%s, scene=%s (points: %d, muzzles: %d)" % [
				action, plan.data_path, plan.scene_path, plan.points.size(), plan.markers.size()])
	print("check: %d entities, %d errors, %d warnings; nothing was written." % [
			plans.size(), (report["errors"] as PackedStringArray).size(),
			(report["warnings"] as PackedStringArray).size()])


## Forges every entity of the plan and writes the data and scene files.
func _forge() -> void:
	var report: Dictionary = _plan()
	var plans: Array = report["plans"] as Array
	var total_errors: int = (report["errors"] as PackedStringArray).size()
	var total_warnings: int = (report["warnings"] as PackedStringArray).size()
	if total_errors > 0:
		print("forge: wrote nothing because of %d errors." % total_errors)
		return
	var created: int = 0
	var updated: int = 0
	for plan: ForgePlan in plans:
		if plan.points.size() < 3:
			push_error("forge \"%s\": the polygon has %d points, fewer than 3." % [plan.id, plan.points.size()])
			total_errors += 1
			continue
		if Geometry2D.triangulate_polygon(plan.points).is_empty():
			push_error("forge \"%s\": the polygon cannot be triangulated." % plan.id)
			total_errors += 1
			continue
		var was_create: bool = not ResourceLoader.exists(plan.data_path)
		var issues: PackedStringArray = _forge_entity(plan)
		var entity_errors: int = 0
		for issue: String in issues:
			if issue.begins_with("[error]"):
				push_error(issue)
				entity_errors += 1
			elif issue.begins_with("[warning]"):
				push_warning(issue)
				total_warnings += 1
		total_errors += entity_errors
		if entity_errors == 0:
			if was_create:
				created += 1
			else:
				updated += 1
	print("forged %d entities (%d created, %d updated), %d errors, %d warnings" % [
			created + updated, created, updated, total_errors, total_warnings])
	if Engine.is_editor_hint():
		var fs = EditorInterface.get_resource_filesystem()
		for plan: ForgePlan in plans:
			fs.update_file(plan.data_path)
			fs.update_file(plan.scene_path)


## Writes one entity: its data file first, then its scene. Returns the
## validation issues of the data and the scene steps; an entity with an
## [code][error][/code] issue leaves nothing written behind.
func _forge_entity(plan: ForgePlan) -> PackedStringArray:
	var issues: PackedStringArray = PackedStringArray()
	var template: EntityData = (boss_data_template if plan.is_boss else foe_data_template) as EntityData
	var is_create: bool = not ResourceLoader.exists(plan.data_path)
	var data: EntityData = template.duplicate(true) as EntityData if is_create \
			else ResourceLoader.load(plan.data_path) as EntityData
	if data == null:
		issues.append("[error] forge \"%s\": could not load %s." % [plan.id, plan.data_path])
		return issues
	data.id = plan.id
	data.polygon = plan.points.duplicate()
	data.color = plan.node.color
	data.team = Helpers.TEAM.FOE
	if plan.is_boss:
		data.center_on_bounds = true
		data.dies_on_contact = false
	issues.append_array(_validate_polygon(data, plan.id, plan))
	if _has_error(issues):
		return issues
	DirAccess.make_dir_recursive_absolute(plan.data_path.get_base_dir())
	var err: Error = ResourceSaver.save(data, plan.data_path)
	if err != OK:
		issues.append("[error] forge \"%s\": could not save %s (error %s)." % [plan.id, plan.data_path, err])
		return issues
	# Reload the data from disk so the scene references the saved file instead
	# of embedding the in-memory resource (which has no path yet).
	data = ResourceLoader.load(plan.data_path) as EntityData
	issues.append_array(_forge_scene(plan, data))
	if _has_error(issues):
		return issues
	return issues


## Whether any issue of [param issues] is an [code][error][/code] line.
func _has_error(issues: PackedStringArray) -> bool:
	for issue: String in issues:
		if issue.begins_with("[error]"):
			return true
	return false


## The polygon checks of forge step 3: [method EntityData.validate_polygon]
## (at least 3 points, and the explosion shards need the triangulation), and
## for bosses also [method BossData.validate] with the muzzle count.
func _validate_polygon(data: EntityData, where: String, plan: ForgePlan) -> PackedStringArray:
	var issues: PackedStringArray = PackedStringArray()
	issues.append_array(data.validate_polygon(where))
	if data is BossData:
		issues.append_array((data as BossData).validate(where, plan.markers.size()))
	return issues


## Writes the entity scene: created from the scene template when missing,
## updated in place otherwise (only `data` and, for bosses, the muzzles).
## Updating patches the file's text, because repacking an instance only
## writes the properties changed since instantiation and would silently drop
## every other override of the scene (e.g. a hand-tuned
## [code]speed_multiplier[/code] on the root).
## Returns [param text] — the packed scene file of [param plan] — with the
## two owned changes applied: the `data` reference of the scene root and, for
## bosses when [member overwrite_scene_muzzles] is on, the muzzle nodes.
## Everything else is left byte-identical.
func _patched_scene_text(plan: ForgePlan, text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var data_id: String = _ext_id_for(lines, plan.data_path)
	if data_id.is_empty():
		data_id = _new_ext_id(lines, plan)
		lines.insert(1, "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]" % [plan.data_path, data_id])
	var root_index: int = _root_node_index(lines)
	if root_index >= 0:
		var i: int = root_index + 1
		var replaced: bool = false
		while i < lines.size() and not lines[i].begins_with("[node"):
			if lines[i].begins_with("data = "):
				lines[i] = "data = ExtResource(\"%s\")" % data_id
				replaced = true
				break
			i += 1
		if not replaced:
			lines.insert(root_index + 1, "data = ExtResource(\"%s\")" % data_id)
	if plan.is_boss and overwrite_scene_muzzles:
		var scale_aux: float = _file_scale_aux(lines)
		var data: EntityData = ResourceLoader.load(plan.data_path) as EntityData
		var pivot: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH
		if data != null and data.center_on_bounds:
			pivot = Helpers.get_points_center(plan.points)
		var kept: PackedStringArray = PackedStringArray()
		var dropping: bool = false
		var empty_run: int = 0
		for line: String in lines:
			if line.begins_with("[node"):
				dropping = _is_muzzle_child_line(line)
			if dropping:
				continue
			if line == "":
				empty_run += 1
				if empty_run > 1:
					continue
			else:
				empty_run = 0
			kept.append(line)
		lines = kept
		for j: int in plan.markers.size():
			var local: Vector2 = (plan.markers[j] - pivot) * scale_aux
			if j > 0:
				lines.append("")
			lines.append("[node name=\"Muzzle%d\" type=\"Marker2D\" parent=\"Muzzles\"]" % (j + 1))
			lines.append("position = Vector2(%f, %f)" % [local.x, local.y])
	var out: String = "\n".join(lines)
	if not out.ends_with("\n"):
		out += "\n"
	return out


## The `scale_aux` property of the scene root stored in [param lines], or
## 1.0 when the root does not record one.
func _file_scale_aux(lines: PackedStringArray) -> float:
	var root_index: int = _root_node_index(lines)
	if root_index < 0:
		return 1.0
	var i: int = root_index + 1
	while i < lines.size() and not lines[i].begins_with("[node"):
		if lines[i].begins_with("scale_aux = "):
			return float(lines[i].trim_prefix("scale_aux = "))
		i += 1
	return 1.0


## Whether the `[node ...]` line [param line] declares a muzzle child of a
## `Muzzles` node — including unnamed `@Marker2D@N` children left behind by
## earlier pack-based saves.
func _is_muzzle_child_line(line: String) -> bool:
	if line.begins_with("[node name=\"Muzzles\""):
		return false
	var named: bool = (line.begins_with("[node name=\"Muzzle") or line.begins_with("[node name=\"@Marker2D@"))
	return named and line.contains(" parent=\"Muzzles\"")


## The ext-resource id of [param path], or "" when it is not referenced yet.
## Matches ` id="` with a leading space so the `uid="..."` attribute of the
## same line never collides.
func _ext_id_for(lines: PackedStringArray, path: String) -> String:
	for line: String in lines:
		if line.begins_with("[ext_resource") and line.contains("path=\"%s\"" % path):
			var start: int = line.find(" id=\"")
			if start < 0:
				continue
			var end: int = line.find("\"", start + 5)
			if end < 0:
				continue
			return line.substr(start + 5, end - (start + 5))
	return ""


## A fresh, valid ext-resource id (e.g. `1_neon_behemoth`).
func _new_ext_id(lines: PackedStringArray, plan: ForgePlan) -> String:
	var candidate: String = "1_%s" % plan.id
	var n: int = 0
	while _id_taken(lines, candidate):
		n += 1
		candidate = "1_%s%d" % [plan.id, n]
	return candidate


## Whether any ext-resource already uses [param id].
func _id_taken(lines: PackedStringArray, id: String) -> bool:
	for line: String in lines:
		if line.begins_with("[ext_resource") and line.contains(" id=\"%s\"" % id):
			return true
	return false


## The index of the first `[node ...]` line, where the scene root lives.
func _root_node_index(lines: PackedStringArray) -> int:
	for i: int in lines.size():
		if lines[i].begins_with("[node"):
			return i
	return -1


func _forge_scene(plan: ForgePlan, data: EntityData) -> PackedStringArray:
	var issues: PackedStringArray = PackedStringArray()
	if ResourceLoader.exists(plan.scene_path):
		var text: String = FileAccess.get_file_as_string(plan.scene_path)
		if text.is_empty():
			issues.append("[error] forge \"%s\": could not read %s." % [plan.id, plan.scene_path])
			return issues
		var patched: String = _patched_scene_text(plan, text)
		if patched == text:
			print("forge \"%s\": %s unchanged." % [plan.id, plan.scene_path])
			return issues
		var file: FileAccess = FileAccess.open(plan.scene_path, FileAccess.WRITE)
		if file == null:
			issues.append("[error] forge \"%s\": could not open %s for writing." % [plan.id, plan.scene_path])
			return issues
		file.store_string(patched)
		file.close()
		return issues
	var template: PackedScene = (boss_scene_template if plan.is_boss else foe_scene_template) as PackedScene
	var instance: Node = null
	if Engine.is_editor_hint():
		print("forge \"%s\": creating %s as an inherited scene of %s." % [
				plan.id, plan.scene_path, template.resource_path])
		instance = template.instantiate(PackedScene.GEN_EDIT_STATE_MAIN_INHERITED)
		if instance == null:
			print("forge \"%s\": the inherited creation failed; saving a standalone copy instead." % plan.id)
			instance = template.instantiate()
	else:
		print("forge \"%s\": creating %s as a standalone copy of %s." % [
				plan.id, plan.scene_path, template.resource_path])
		instance = template.instantiate()
	if instance == null:
		issues.append("[error] forge \"%s\": could not instantiate the scene template." % plan.id)
		return issues
	instance.name = plan.root_name
	instance.set("data", data)
	if plan.is_boss:
		_write_muzzles(instance, plan)
	var re_packed := PackedScene.new()
	var pk: Error = re_packed.pack(instance)
	instance.free()
	if pk != OK:
		issues.append("[error] forge \"%s\": could not pack %s (error %s)." % [plan.id, plan.scene_path, pk])
		return issues
	DirAccess.make_dir_recursive_absolute(plan.scene_path.get_base_dir())
	var err: Error = ResourceSaver.save(re_packed, plan.scene_path)
	if err != OK:
		issues.append("[error] forge \"%s\": could not save %s (error %s)." % [plan.id, plan.scene_path, err])
	return issues


## Replaces the `Muzzles` children of a boss [param instance] with the muzzle
## positions of [param plan], converted the way [method Entity._refresh_shape]
## does: `(marker.position - pivot) * scale_aux`, where [code]pivot[/code] is
## the polygon's bounds center when the data has [code]center_on_bounds[/code]
## and `Vector2.ONE * Helpers.ENTITY_HALF_WIDTH` otherwise. [code]scale_aux[/code]
## is read from the instantiated scene root.
func _write_muzzles(instance: Node, plan: ForgePlan) -> void:
	var muzzles: Node = instance.get_node_or_null("Muzzles")
	if muzzles == null:
		return
	for child: Node in muzzles.get_children():
		child.free()
	var scale_aux: float = float(instance.get("scale_aux"))
	var data: EntityData = instance.get("data") as EntityData
	var pivot: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH
	if data != null and data.center_on_bounds:
		pivot = Helpers.get_points_center(plan.points)
	for i: int in plan.markers.size():
		var marker: Marker2D = Marker2D.new()
		marker.name = "Muzzle%d" % (i + 1)
		marker.position = (plan.markers[i] - pivot) * scale_aux
		muzzles.add_child(marker)
		marker.owner = instance


## The sketch polygons the transform tools act on: the selected ones when any
## are selected in the editor, all of them otherwise.
func _transform_targets() -> Array[Polygon2D]:
	if Engine.is_editor_hint():
		var selection: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
		var selected: Array[Polygon2D] = []
		for node: Node in selection:
			if node is Polygon2D and node in _sketch_polygons():
				selected.append(node as Polygon2D)
		if not selected.is_empty():
			return selected
	return _sketch_polygons()


## Applies [param transform] to the points and marker positions of every
## target polygon, through the editor's undo/redo stack.
func _transform_all(label: String, _transform: Callable) -> void:
	if not Engine.is_editor_hint():
		return
	var targets: Array[Polygon2D] = _transform_targets()
	if targets.is_empty():
		return
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	undo_redo.create_action(label)
	for node: Polygon2D in targets:
		var old_points: PackedVector2Array = node.polygon.duplicate()
		var new_points: PackedVector2Array = _transform.call(old_points, Helpers.get_points_center(old_points))
		undo_redo.add_do_property(node, &"polygon", new_points)
		undo_redo.add_undo_property(node, &"polygon", old_points)
		for child: Node in node.get_children():
			var marker: Marker2D = child as Marker2D
			if marker == null:
				continue
			var old_position: Vector2 = marker.position
			var new_position: Vector2 = _transform.call(PackedVector2Array([old_position]),
					Helpers.get_points_center(old_points))[0]
			undo_redo.add_do_property(marker, &"position", new_position)
			undo_redo.add_undo_property(marker, &"position", old_position)
	undo_redo.commit_action()


## Moves the target polygons in [param direction] by [member move_step].
func _move(direction: Vector2) -> void:
	_transform_all("Move Sketch Polygons %s" % str(direction), func(points: PackedVector2Array, _center: Vector2) -> PackedVector2Array:
		var moved: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in points:
			moved.append(point + direction * move_step)
		return moved)


func _move_up() -> void:
	_move(Vector2.UP)


func _move_right() -> void:
	_move(Vector2.RIGHT)


func _move_down() -> void:
	_move(Vector2.DOWN)


func _move_left() -> void:
	_move(Vector2.LEFT)


## Rotates the target polygons of [param degrees] around their own bounds
## center; their markers rotate with them.
func _rotate(degrees: float) -> void:
	_transform_all("Rotate Sketch Polygons %s°" % degrees, func(points: PackedVector2Array, center: Vector2) -> PackedVector2Array:
		var angle: float = deg_to_rad(degrees)
		var cos_a: float = cos(angle)
		var sin_a: float = sin(angle)
		var rotated: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in points:
			var offset: Vector2 = point - center
			rotated.append(Vector2(offset.x * cos_a - offset.y * sin_a,
					offset.x * sin_a + offset.y * cos_a) + center)
		return rotated)


func _rotate_left() -> void:
	_rotate(rotate_step)


func _rotate_right() -> void:
	_rotate(-rotate_step)
