@tool
extends EditorScript
## Gate for the removal of the legacy `visual` field and polygon code: loads
## every `.tres` under `res://resources/` that is an [EntityData] (including
## [BossData]) or a [ProjectileData] and lists every one whose `polygon` is
## empty or has fewer than 3 points. Run from the editor (File > Run). If the
## list is not empty, stop — do not remove the legacy code yet.


func _run() -> void:
	var empty: PackedStringArray = PackedStringArray()
	var total: int = 0
	for path: String in _walk("res://resources"):
		var resource: Resource = ResourceLoader.load(path) as Resource
		if resource == null:
			continue
		if not (resource is EntityData or resource is ProjectileData):
			continue
		total += 1
		var ok: bool = false
		if resource is EntityData:
			ok = _points_of(resource).size() >= 3 and not Geometry2D.triangulate_polygon(_points_of(resource)).is_empty()
		else:
			ok = _points_of(resource).size() >= 3
		if not ok:
			empty.append(path)
	if empty.is_empty():
		print("check_polygons: all %d entity/projectile resources have a polygon of at least 3 points." % total)
		return
	push_warning("check_polygons: %d of %d resources lack a usable polygon:" % [empty.size(), total])
	for path: String in empty:
		print("  %s" % path)
	push_warning("check_polygons: gate NOT passed — do not remove the legacy code yet.")


## The [member EntityData.polygon] of [param resource], or an empty array when
## unset.
func _points_of(resource: Resource) -> PackedVector2Array:
	var raw: Variant = resource.get("polygon")
	if raw == null:
		return PackedVector2Array()
	if raw is PackedVector2Array:
		return (raw as PackedVector2Array).duplicate()
	return PackedVector2Array()


## Recursively collects every `.tres` under [param root].
func _walk(root: String) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var full: String = root + "/" + entry
		if dir.current_is_dir():
			if entry != ".godot":
				paths.append_array(_walk(full))
		elif entry.ends_with(".tres"):
			paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
