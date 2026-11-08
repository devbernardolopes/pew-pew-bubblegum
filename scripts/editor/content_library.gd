@tool
class_name ContentLibrary
extends RefCounted
## Resolves an asset by a short name from a small set of content folders.
## Names are compared normalized: lowercase, spaces and hyphens are treated
## as underscores, and the extension is ignored.
##
## This is an editor-only helper used by [StageBuilder]; it is never
## referenced from gameplay scripts.


## Static cached index: category -> Array of {path, stem} dictionaries.
static var _index: Dictionary = {}


## One entry per category: folder (scanned recursively), accepted
## extensions, and the prefixes tried before the bare name.
static func _categories() -> Dictionary:
	return {
		&"scene": {
			"folder": "res://scenes/entities/",
			"extensions": [".tscn"],
			"prefixes": ["foe_", "boss_"],
			"type": "PackedScene",
		},
		&"entry": {
			"folder": "res://resources/curves/entries/",
			"extensions": [".tres"],
			"prefixes": ["entry_"],
			"type": "Curve2D",
		},
		&"dive": {
			"folder": "res://resources/curves/dives/",
			"extensions": [".tres"],
			"prefixes": ["dive_"],
			"type": "Curve2D",
		},
		&"formation": {
			"folder": "res://resources/formations/",
			"extensions": [".tres"],
			"prefixes": ["formation_", "form_"],
			"type": "FormationData",
		},
		&"cinematic": {
			"folder": "res://resources/cinematics/",
			"extensions": [".tres"],
			"prefixes": [],
			"type": "CinematicData",
		},
		&"music": {
			"folder": "res://assets/musics/",
			"extensions": [".mp3", ".ogg", ".wav"],
			"prefixes": [],
			"type": "AudioStream",
		},
		&"stage": {
			"folder": "res://resources/stages/",
			"extensions": [".tres"],
			"prefixes": ["stage_"],
			"type": "StageData",
		},
		&"journey": {
			"folder": "res://resources/journeys/",
			"extensions": [".tres"],
			"prefixes": [],
			"type": "JourneyData",
		},
	}


## The normalized form of a name or stem: lowercase, spaces and hyphens
## treated as underscores, and the extension ignored.
static func normalize(name: String) -> String:
	var stem: String = name.get_file().get_basename()
	return stem.to_lower().replace(" ", "_").replace("-", "_")


## Drops the cached index; the next lookup rescans the folders.
static func refresh() -> void:
	_index.clear()


## Returns the path of [param query] in [param category], or "" when it is not
## found (or ambiguous). Pushes no error.
static func find_path(category: StringName, query: String) -> String:
	var result: Dictionary = _resolve(category, query)
	return result.get("path", "") as String


## Loads the asset named by [param query] in [param category]. Appends a human
## error to [param errors] and returns null on failure (not found, ambiguous,
## unloadable, or wrong resource type).
static func load_resource(category: StringName, query: String, errors: PackedStringArray) -> Resource:
	var result: Dictionary = _resolve(category, query)
	if result.has("error"):
		errors.append(result["error"] as String)
		return null
	var path: String = result["path"] as String
	var resource: Resource = ResourceLoader.load(path) as Resource
	if resource == null:
		errors.append("%s \"%s\" at %s could not be loaded." % [category, query, path])
		return null
	var expected: String = (_categories().get(category, {}) as Dictionary).get("type", "") as String
	if not _is_type(resource, expected):
		errors.append("%s \"%s\" at %s is a %s, not a %s." % [
				category, query, path, _type_name(resource), expected])
		return null
	return resource


## Whether [param resource] is of the named [param type_name].
static func _is_type(resource: Resource, type_name: String) -> bool:
	match type_name:
		"PackedScene":
			return resource is PackedScene
		"Curve2D":
			return resource is Curve2D
		"FormationData":
			return resource is FormationData
		"CinematicData":
			return resource is CinematicData
		"AudioStream":
			return resource is AudioStream
		"StageData":
			return resource is StageData
		"JourneyData":
			return resource is JourneyData
	return true


## A printable type name of [param resource] for error messages.
static func _type_name(resource: Resource) -> String:
	var script: Script = resource.get_script() as Script
	if script != null:
		var path: String = script.resource_path
		var base: String = path.get_file().get_basename()
		return base
	return resource.get_class()


## Returns the shortest unambiguous query for each file in [param category],
## sorted. Files that have no unambiguous query are listed by their stem.
static func list_names(category: StringName) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _entries(category):
		var path: String = entry["path"] as String
		var stem: String = entry["stem"] as String
		var best: String = stem
		for candidate: String in _candidate_queries(category, stem):
			if candidate.length() >= best.length():
				continue
			if _resolve(category, candidate).get("path", "") as String == path:
				best = candidate
		names.append(best)
	names.sort()
	return names


## Returns every index entry of [param category] ({path, stem}), building the
## cache on first use.
static func _entries(category: StringName) -> Array:
	if not _index.has(category):
		var category_info: Dictionary = _categories().get(category, {})
		var entries: Array = []
		if not category_info.is_empty():
			_scan(category_info["folder"] as String,
					category_info["extensions"] as Array, entries)
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["path"] as String) < (b["path"] as String))
		_index[category] = entries
	return _index[category] as Array


## Recursively collects the files of [param folder] with an accepted
## extension into [param entries] (skipping .import and .uid files).
static func _scan(folder: String, extensions: Array, entries: Array) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var full: String = folder + entry
		if dir.current_is_dir():
			_scan(full + "/", extensions, entries)
		else:
			if not entry.ends_with(".import") and not entry.ends_with(".uid"):
				for ext: String in extensions:
					if entry.to_lower().ends_with(ext):
						entries.append({
							"path": full,
							"stem": normalize(entry),
						})
						break
		entry = dir.get_next()
	dir.list_dir_end()


## The queries that can resolve to a file with the normalized [param stem]:
## the stem itself, and the stem with each tried prefix stripped.
static func _candidate_queries(category: StringName, stem: String) -> PackedStringArray:
	var queries: PackedStringArray = PackedStringArray([stem])
	var prefixes: Array = (_categories().get(category, {}) as Dictionary).get("prefixes", [])
	for prefix: String in prefixes:
		if stem.begins_with(prefix):
			queries.append(stem.substr(prefix.length()))
	return queries


## Resolves [param query] to {path, stem} or {error}. Matching order is the
## exact normalized stem first, then each prefix + query. More than one match
## at the same level is an ambiguity error listing the paths.
static func _resolve(category: StringName, query: String) -> Dictionary:
	var normalized: String = normalize(query)
	var probes: PackedStringArray = PackedStringArray([normalized])
	var prefixes: Array = (_categories().get(category, {}) as Dictionary).get("prefixes", [])
	for prefix: String in prefixes:
		probes.append(prefix + normalized)
	for probe: String in probes:
		var matches: Array = []
		for entry: Dictionary in _entries(category):
			if entry["stem"] as String == probe:
				matches.append(entry)
		if matches.size() == 1:
			return matches[0]
		if matches.size() > 1:
			var paths: PackedStringArray = PackedStringArray()
			for entry: Dictionary in matches:
				paths.append(entry["path"] as String)
			return {"error": "ambiguous %s \"%s\" matches: %s" % [
					category, query, ", ".join(paths)]}
	var suggestions: PackedStringArray = _suggestions(category, normalized)
	var near: String = ", ".join(suggestions)
	return {"error": "unknown %s \"%s\". Did you mean: %s?" % [category, query, near]}


## The 3 closest short names of [param category] to [param normalized] by
## [method String.similarity] (the shortest query of each file, as in
## [method list_names]).
static func _suggestions(category: StringName, normalized: String) -> PackedStringArray:
	var scored: Array = []
	for entry: Dictionary in _entries(category):
		var stem: String = entry["stem"] as String
		var short: String = stem
		for candidate: String in _candidate_queries(category, stem):
			if candidate.length() < short.length():
				short = candidate
		scored.append({"name": short, "score": normalized.similarity(short)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]) or (float(a["score"]) == float(b["score"]) and (a["name"] as String) < (b["name"] as String)))
	var out: PackedStringArray = PackedStringArray()
	for i: int in mini(3, scored.size()):
		out.append(scored[i]["name"] as String)
	return out
