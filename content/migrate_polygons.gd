@tool
extends EditorScript
## One-time migrator: copies each [EntityData]/[ProjectileData] resource's
## legacy [member visual] shape into its [member polygon] under res://resources/.
## Run from the editor (File > Run). Leave [const DRY_RUN] as true until the
## printed list has been reviewed; only then flip it and run again.


## Resources with these ids are skipped (authored by hand; [member visual] is
## only the default).
const SKIP_IDS: Array[StringName] = [&"boss_neon_behemoth"]

## When true, only print what would change and write nothing.
const DRY_RUN: bool = true


func _run() -> void:
	var changed: int = 0
	var skipped: int = 0
	var total: int = 0
	var tres_paths: PackedStringArray = _walk("res://resources")
	for path: String in tres_paths:
		var resource: Resource = ResourceLoader.load(path) as Resource
		if resource == null:
			continue
		if not (resource is EntityData or resource is ProjectileData):
			continue
		total += 1
		var id: StringName = resource.get("id")
		if SKIP_IDS.has(id):
			print("SKIP %s (%s): id %s is skipped" % [path, _visual_name(resource), id])
			skipped += 1
			continue
		var existing: PackedVector2Array = _polygon_of(resource)
		if not existing.is_empty():
			print("SKIP %s (%s): polygon already set (%d points)" % [
					path, _visual_name(resource), existing.size()])
			skipped += 1
			continue
		var shape: PackedVector2Array = Helpers.get_polygon(resource.get("visual"))
		print("MIGRATE %s (%s): %d points" % [path, _visual_name(resource), shape.size()])
		if DRY_RUN:
			changed += 1
			continue
		resource.set("polygon", shape)
		var err: Error = ResourceSaver.save(resource, path)
		if err != OK:
			push_error("migrate_polygons: failed to save %s (error %s)" % [path, err])
			continue
		print("SAVED %s" % path)
		changed += 1
	print(_embedded_data_warnings())
	print("migrate_polygons: total=%d changed=%d skipped=%d dry_run=%s" % [
			total, changed, skipped, DRY_RUN])
	if DRY_RUN:
		print("migrate_polygons: dry run, nothing was written.")


## The [member EntityData.polygon] of [param resource], or an empty array when
## it is unset. Some resources store `polygon = null` in their file, so the
## value must never be cast with `as` without a null check.
func _polygon_of(resource: Resource) -> PackedVector2Array:
	var raw: Variant = resource.get("polygon")
	if raw == null:
		return PackedVector2Array()
	if raw is PackedVector2Array:
		return (raw as PackedVector2Array).duplicate()
	push_warning("migrate_polygons: %s has an unexpected polygon value of type %s; treating it as unset." % [
			resource.resource_path, typeof(raw)])
	return PackedVector2Array()


## Human-readable name of a [member visual] enum value.
func _visual_name(resource: Resource) -> String:
	var visual_value: int = int(resource.get("visual"))
	for key: String in Helpers.VISUAL:
		if int(Helpers.VISUAL[key]) == visual_value:
			return key
	return "visual=%d" % visual_value


## Recursively collects every .tres file under [param root].
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


## Warns about .tscn embedded EntityData/ProjectileData sub-resources with an
## empty polygon, which this migrator cannot save in place.
func _embedded_data_warnings() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var tscn_paths: PackedStringArray = _walk_tscn("res://scenes")
	for path: String in tscn_paths:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text: String = file.get_as_text()
		file.close()
		var is_data_scene: bool = text.contains("EntityData") or text.contains("ProjectileData")
		if not is_data_scene:
			continue
		lines.append("EMBEDDED-DATA %s: mentions EntityData/ProjectileData, check for an embedded sub-resource with an empty polygon (migrator cannot save it)" % path)
	return "\n".join(lines)


## Recursively collects every .tscn file under [param root].
func _walk_tscn(root: String) -> PackedStringArray:
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
				paths.append_array(_walk_tscn(full))
		elif entry.ends_with(".tscn"):
			paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
