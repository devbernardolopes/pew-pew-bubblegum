@tool
class_name StageBuilder
extends RefCounted
## Builds a [StageData] from short text names, resolves every asset through
## [ContentLibrary], validates the result, and saves it.
##
## Sticky defaults ([method formation], [method music], [method entry],
## [method dives], [method delay]) apply to every wave added after the call
## until changed again; a per-wave option overrides a sticky default, and a
## missing option uses the sticky default. A missing sticky default leaves
## the [WaveData] default untouched.
##
## Per-wave options go in a dictionary (GDScript has no named arguments):
## [code]row()[/code]/[code]rows()[/code] accept [code]entry[/code] (String),
## [code]dives[/code] (Array of names), [code]delay[/code] (float),
## [code]spacing[/code] (float), [code]formation[/code] (String),
## [code]phase[/code] (float, maps to [member WaveData.sway_start_phase_deg]),
## [code]fire_on_entry[/code] (bool), [code]fire_in_formation[/code] (bool) and
## [code]entry_shots[/code] (int); [code]boss()[/code] accepts [code]row[/code]
## (int, default 0), [code]row_span[/code] (int), [code]col_span[/code] (int),
## [code]mirror[/code] (bool, maps to [member BossWaveData.mirror_entry]),
## [code]entry[/code], [code]delay[/code], [code]formation[/code] and
## [code]cinematic[/code] (String). Boss waves ignore [code]dives[/code],
## [code]spacing[/code] and the firing flags: passing them is a warning.
##
## This is an editor-only helper; it is never referenced from gameplay
## scripts. Editor calls ([code]EditorInterface[/code]) are guarded by
## [code]Engine.is_editor_hint()[/code].


## Valid [code]row()[/code]/[code]rows()[/code] option keys.
const ROW_OPTIONS: Array[String] = [
	"entry", "dives", "delay", "spacing", "formation", "phase",
	"fire_on_entry", "fire_in_formation", "entry_shots",
]

## Valid [code]boss()[/code] option keys.
const BOSS_OPTIONS: Array[String] = [
	"row", "row_span", "col_span", "mirror", "entry", "delay", "formation",
	"cinematic", "dives", "spacing", "fire_on_entry", "fire_in_formation",
	"entry_shots",
]

## The error list of the last build (lookup and option errors).
var _errors: PackedStringArray = PackedStringArray()

## The warning list of the last build (builder warnings, e.g. ignored boss
## options).
var _warnings: PackedStringArray = PackedStringArray()

var _stage_name: String = ""
var _output_path: String = ""
var _journey_name: String = ""

var _sticky_formation: String = ""
var _sticky_music: String = ""
var _sticky_entry: String = ""
var _sticky_dives: Array = []
var _sticky_delay: float = 0.0

var _waves: Array = []


## Creates a builder for the stage named [param stage_name]; the default
## output path is [code]res://resources/stages/stage_&lt;stage_name&gt;.tres[/code].
func _init(stage_name: String) -> void:
	_stage_name = stage_name
	_output_path = "res://resources/stages/stage_%s.tres" % stage_name


## Sticky default: applies to every wave added after the call, until changed.
func formation(name: String) -> StageBuilder:
	_sticky_formation = name
	return self


## Sticky default: the stage's music stream, resolved by name.
func music(name: String) -> StageBuilder:
	_sticky_music = name
	return self


## Sticky default: applies to every wave added after the call, until changed.
func entry(name: String) -> StageBuilder:
	_sticky_entry = name
	return self


## Sticky default: the dive curves ([param names] are asset names) of every
## wave added after the call, until changed.
func dives(names: Array) -> StageBuilder:
	_sticky_dives = names.duplicate()
	return self


## Sticky default: applies to every wave added after the call, until changed.
func delay(seconds: float) -> StageBuilder:
	_sticky_delay = seconds
	return self


## Appends a regular wave of [param foe] filling [param row_index].
func row(foe: String, row_index: int, options: Dictionary = {}) -> StageBuilder:
	_waves.append({
		"kind": "row",
		"foe": foe,
		"row": row_index,
		"options": options,
		"sticky": _sticky_snapshot(),
	})
	return self


## Appends one wave per foe in [param foes]: [code]foes[i][/code] fills the
## row [param first_row] + i, all with the same [param options].
func rows(foes: Array, first_row: int, options: Dictionary = {}) -> StageBuilder:
	for i: int in foes.size():
		row(foes[i] as String, first_row + i, options.duplicate())
	return self


## Appends a boss wave of [param boss_name] at column [param col].
func boss(boss_name: String, col: int, options: Dictionary = {}) -> StageBuilder:
	_waves.append({
		"kind": "boss",
		"foe": boss_name,
		"col": col,
		"options": options,
		"sticky": _sticky_snapshot(),
	})
	return self


## The sticky defaults in effect right now; each wave snapshots them when it
## is added, so later sticky changes do not rewrite earlier waves.
func _sticky_snapshot() -> Dictionary:
	return {
		"formation": _sticky_formation,
		"entry": _sticky_entry,
		"dives": _sticky_dives.duplicate(),
		"delay": _sticky_delay,
	}


## Overrides the output path of [method save].
func to(path: String) -> StageBuilder:
	_output_path = path
	return self


## Also appends the saved stage to the journey named [param journey_name],
## if it is not already in it.
func journey(journey_name: String) -> StageBuilder:
	_journey_name = journey_name
	return self


## Builds the stage, validates it, and writes it to the output path.
## Refuses to write (returns [constant ERR_INVALID_DATA]) when there are
## lookup or option errors, or when [method StageData.validate] reports
## errors, unless [param force] is true (which only bypasses
## [code]validate()[/code] errors, never lookup errors).
func save(force: bool = false) -> Error:
	ContentLibrary.refresh()
	_errors.clear()
	_warnings.clear()
	var journey_resource: JourneyData = null
	var journey_path: String = ""
	if not _journey_name.is_empty():
		var journey_errors: PackedStringArray = PackedStringArray()
		var found: Resource = ContentLibrary.load_resource(&"journey", _journey_name, journey_errors)
		if found == null:
			for issue: String in journey_errors:
				_errors.append("journey \"%s\": %s" % [_journey_name, issue])
		else:
			journey_resource = found as JourneyData
			journey_path = ContentLibrary.find_path(&"journey", _journey_name)
	var music_stream: AudioStream = null
	if not _sticky_music.is_empty():
		var music_errors: PackedStringArray = PackedStringArray()
		music_stream = ContentLibrary.load_resource(&"music", _sticky_music, music_errors) as AudioStream
		if music_stream == null:
			for issue: String in music_errors:
				_errors.append("stage %s: %s" % [_stage_name, issue])
	var stage: StageData = _build_stage()
	if stage == null:
		_print_problems()
		return ERR_INVALID_DATA
	stage.music_stream = music_stream
	var issues: PackedStringArray = stage.validate()
	var validate_errors: int = 0
	var validate_warnings: int = 0
	for issue: String in issues:
		if issue.begins_with("[error]"):
			push_error(issue)
			validate_errors += 1
		elif issue.begins_with("[warning]"):
			push_warning(issue)
			validate_warnings += 1
	_print_problems()
	if not _errors.is_empty():
		print("stage_%s: NOT WRITTEN (%d errors, %d warnings)" % [
				_stage_name, _errors.size() + validate_errors, _warnings.size() + validate_warnings])
		return ERR_INVALID_DATA
	if validate_errors > 0 and not force:
		print("stage_%s: NOT WRITTEN (%d errors, %d warnings)" % [
				_stage_name, _errors.size() + validate_errors, _warnings.size() + validate_warnings])
		return ERR_INVALID_DATA
	if not _write(stage):
		return ERR_UNAVAILABLE
	if journey_resource != null:
		var saved_stage: StageData = ResourceLoader.load(_output_path) as StageData
		var to_append: StageData = saved_stage if saved_stage != null else stage
		if not _stage_in(journey_resource, to_append):
			journey_resource.stages.append(to_append)
			var err: Error = ResourceSaver.save(journey_resource, journey_path)
			if err != OK:
				push_error("StageBuilder: could not save the journey at %s (error %s)" % [journey_path, err])
	print("stage_%s: %d waves, %d errors, %d warnings -> %s" % [
			_stage_name, _waves.size(), validate_errors + _errors.size(),
			validate_warnings + _warnings.size(), _output_path])
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_output_path)
		if journey_resource != null:
			EditorInterface.get_resource_filesystem().update_file(journey_path)
	return OK


## Builds the [StageData] of every recorded wave, resolving all assets and
## options. Returns null only if the stage itself cannot be built.
func _build_stage() -> StageData:
	var stage: StageData = StageData.new()
	var waves: Array[WaveData] = []
	for i: int in _waves.size():
		var spec: Dictionary = _waves[i] as Dictionary
		var foe_name: String = spec.get("foe", "") as String
		var label: String = "wave %d (%s)" % [i, foe_name]
		var wave: WaveData = _build_wave(spec, label)
		if wave != null:
			waves.append(wave)
	stage.waves = waves
	return stage


## Builds one wave from its spec, appending every problem to the error and
## warning lists. Returns null if the spec is too broken to build a wave.
func _build_wave(spec: Dictionary, label: String) -> WaveData:
	var is_boss: bool = (spec["kind"] as String) == "boss"
	var foe_name: String = spec["foe"] as String
	var options: Dictionary = spec.get("options", {}) as Dictionary
	var valid_keys: Array = BOSS_OPTIONS if is_boss else ROW_OPTIONS
	for key: String in options:
		if not valid_keys.has(key):
			_errors.append("%s: unknown option \"%s\" (valid keys: %s)" % [
					label, key, ", ".join(valid_keys)])
	var wave: WaveData = null
	if is_boss:
		wave = BossWaveData.new()
	else:
		wave = WaveData.new()
	wave.foe_scene = _load_labeled(&"scene", foe_name, label) as PackedScene
	var snapshot: Dictionary = spec.get("sticky", {}) as Dictionary
	var sticky_entry: String = snapshot.get("entry", "") as String
	var sticky_formation: String = snapshot.get("formation", "") as String
	var entry_name: String = _resolve_option(options, "entry", sticky_entry, label)
	wave.entry_curve = _load_curve(&"entry", entry_name, label)
	var formation_name: String = _resolve_option(options, "formation", sticky_formation, label)
	wave.formation = _load_formation(formation_name, label)
	if wave.entry_curve == null and entry_name.is_empty():
		_errors.append("%s: no entry curve (no option and no sticky default)." % label)
	if wave.formation == null and formation_name.is_empty():
		_errors.append("%s: no formation (no option and no sticky default)." % label)
	if is_boss:
		_apply_boss_options(wave as BossWaveData, options, label, foe_name, spec, snapshot)
	else:
		_apply_row_options(wave, options, label, spec, snapshot)
	return wave


## Resolves a string option: a per-wave value wins, the sticky default is
## the fallback, and a missing value stays "".
func _resolve_option(options: Dictionary, key: String, sticky: String, label: String) -> String:
	if not options.has(key):
		return sticky
	var value: Variant = options[key]
	if not (value is String):
		_errors.append("%s: option \"%s\" must be a String name." % [label, key])
		return ""
	return value as String


## Applies the row-wave options of [param options] to [param wave], falling
## back to the sticky defaults snapshotted when the wave was added.
func _apply_row_options(wave: WaveData, options: Dictionary, label: String, spec: Dictionary, snapshot: Dictionary) -> void:
	wave.row = int(spec.get("row", 0))
	if options.has("delay"):
		if not _is_number(options["delay"]):
			_errors.append("%s: option \"delay\" must be a number (seconds)." % label)
		else:
			wave.delay = float(options["delay"])
	else:
		wave.delay = float(snapshot.get("delay", 0.0))
	if options.has("spacing"):
		if not _is_number(options["spacing"]):
			_errors.append("%s: option \"spacing\" must be a number (seconds)." % label)
		else:
			wave.spacing = float(options["spacing"])
	if options.has("phase"):
		if not _is_number(options["phase"]):
			_errors.append("%s: option \"phase\" must be a number (degrees)." % label)
		else:
			wave.sway_start_phase_deg = float(options["phase"])
	var dive_names: Array = snapshot.get("dives", []) as Array
	if options.has("dives"):
		if not (options["dives"] is Array):
			_errors.append("%s: option \"dives\" must be an Array of names." % label)
			dive_names = []
		else:
			dive_names = options["dives"] as Array
	wave.dive_curves.clear()
	for dive_name: String in dive_names:
		var curve: Curve2D = _load_curve(&"dive", dive_name, label)
		if curve != null:
			wave.dive_curves.append(curve)
	if options.has("fire_on_entry"):
		if not (options["fire_on_entry"] is bool):
			_errors.append("%s: option \"fire_on_entry\" must be a bool." % label)
		else:
			wave.fire_on_entry = bool(options["fire_on_entry"])
	if options.has("fire_in_formation"):
		if not (options["fire_in_formation"] is bool):
			_errors.append("%s: option \"fire_in_formation\" must be a bool." % label)
		else:
			wave.fire_in_formation = bool(options["fire_in_formation"])
	if options.has("entry_shots"):
		if not (options["entry_shots"] is int):
			_errors.append("%s: option \"entry_shots\" must be an int." % label)
		else:
			wave.entry_shots = int(options["entry_shots"])


## Applies the boss-wave options of [param options] to [param wave]. The
## options a boss ignores (dives, spacing, firing flags) are warnings.
func _apply_boss_options(wave: BossWaveData, options: Dictionary, label: String, foe_name: String, spec: Dictionary, snapshot: Dictionary) -> void:
	wave.col = int(spec.get("col", 0))
	if options.has("row"):
		if not (options["row"] is int):
			_errors.append("%s: option \"row\" must be an int." % label)
		else:
			wave.row = int(options["row"])
	if options.has("row_span"):
		if not (options["row_span"] is int):
			_errors.append("%s: option \"row_span\" must be an int." % label)
		else:
			wave.row_span = int(options["row_span"])
	if options.has("col_span"):
		if not (options["col_span"] is int):
			_errors.append("%s: option \"col_span\" must be an int." % label)
		else:
			wave.col_span = int(options["col_span"])
	if options.has("mirror"):
		if not (options["mirror"] is bool):
			_errors.append("%s: option \"mirror\" must be a bool." % label)
		else:
			wave.mirror_entry = bool(options["mirror"])
	if options.has("delay"):
		if not _is_number(options["delay"]):
			_errors.append("%s: option \"delay\" must be a number (seconds)." % label)
		else:
			wave.delay = float(options["delay"])
	else:
		wave.delay = float(snapshot.get("delay", 0.0))
	if options.has("cinematic"):
		var cinematic_name: String = _resolve_option(options, "cinematic", "", label)
		if not cinematic_name.is_empty():
			wave.cinematic = _load_cinematic(cinematic_name, label)
	for ignored: String in ["dives", "spacing", "fire_on_entry", "fire_in_formation", "entry_shots"]:
		if options.has(ignored):
			_warnings.append("%s: boss (\"%s\") ignores the \"%s\" option." % [label, foe_name, ignored])


## Loads an asset of [param category] named [param query], prefixing every
## lookup error with [param label]. Returns null on failure.
func _load_labeled(category: StringName, query: String, label: String) -> Resource:
	var errors: PackedStringArray = PackedStringArray()
	var resource: Resource = ContentLibrary.load_resource(category, query, errors)
	if resource == null:
		for issue: String in errors:
			_errors.append("%s: %s" % [label, issue])
	return resource


## Loads an entry/dive curve by name, or null (with a labeled error).
func _load_curve(category: StringName, name: String, label: String) -> Curve2D:
	return _load_labeled(category, name, label) as Curve2D if not name.is_empty() else null


## Loads a formation by name, or null (with a labeled error).
func _load_formation(name: String, label: String) -> FormationData:
	if name.is_empty():
		return null
	return _load_labeled(&"formation", name, label) as FormationData


## Loads a cinematic by name, or null (with a labeled error).
func _load_cinematic(name: String, label: String) -> CinematicData:
	if name.is_empty():
		return null
	return _load_labeled(&"cinematic", name, label) as CinematicData


## Whether [param value] is an int or a float (an option that takes seconds
## or degrees).
func _is_number(value: Variant) -> bool:
	return value is int or value is float


## Whether the journey already references [param stage] (by instance or by
## saved path), so it is never appended twice.
func _stage_in(journey_resource: JourneyData, stage: StageData) -> bool:
	for existing: StageData in journey_resource.stages:
		if existing == stage:
			return true
		if existing != null and existing.resource_path == _output_path:
			return true
	return false


## Prints every collected problem (builder errors and warnings) at once.
func _print_problems() -> void:
	for error: String in _errors:
		push_error(error)
	for warning: String in _warnings:
		push_warning(warning)


## Writes [param stage] to the output path, updating in place when the file
## already exists so the stage keeps its UID and every journey reference.
func _write(stage: StageData) -> bool:
	if ResourceLoader.exists(_output_path):
		var existing: StageData = ResourceLoader.load(_output_path) as StageData
		if existing != null:
			existing.waves = stage.waves
			existing.music_stream = stage.music_stream
			var err: Error = ResourceSaver.save(existing, _output_path)
			if err != OK:
				push_error("StageBuilder: could not save %s (error %s)" % [_output_path, err])
				return false
			return true
		push_warning("StageBuilder: %s is not a readable stage; overwriting it." % _output_path)
	var base_dir: String = _output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(base_dir):
		var mk: Error = DirAccess.make_dir_recursive_absolute(base_dir)
		if mk != OK:
			push_error("StageBuilder: could not create %s (error %s)" % [base_dir, mk])
			return false
	var err: Error = ResourceSaver.save(stage, _output_path)
	if err != OK:
		push_error("StageBuilder: could not save %s (error %s)" % [_output_path, err])
		return false
	return true


## Compares two stages: wave count, each wave's type, [member WaveData.foe_scene],
## [member WaveData.entry_curve], [member WaveData.formation], (boss)
## [member BossWaveData.cinematic] (by [code]resource_path[/code]),
## [member WaveData.dive_curves] (paths, in order), [member WaveData.row],
## [member WaveData.delay], [member WaveData.spacing],
## [member WaveData.sway_start_phase_deg], the firing flags,
## [member WaveData.entry_shots], the boss fields ([member BossWaveData.col],
## [member BossWaveData.row_span], [member BossWaveData.col_span],
## [member BossWaveData.mirror_entry]) and [member StageData.music_stream]
## (path). Returns one line per difference, empty when identical.
static func diff_stages(a: StageData, b: StageData) -> PackedStringArray:
	var diffs: PackedStringArray = PackedStringArray()
	if (a == null) != (b == null):
		diffs.append("stage null-ness differs (a=%s, b=%s)" % [str(a == null), str(b == null)])
		return diffs
	if a.waves.size() != b.waves.size():
		diffs.append("wave count differs (a=%d, b=%d)" % [a.waves.size(), b.waves.size()])
	for i: int in mini(a.waves.size(), b.waves.size()):
		var wa: WaveData = a.waves[i]
		var wb: WaveData = b.waves[i]
		var label: String = "wave %d" % i
		diffs.append_array(_diff_wave(label, wa, wb))
	_different(diffs, "music_stream", _path_of(a.music_stream), _path_of(b.music_stream))
	return diffs


## Compares one pair of waves of [param label].
static func _diff_wave(label: String, wa: WaveData, wb: WaveData) -> PackedStringArray:
	var diffs: PackedStringArray = PackedStringArray()
	if (wa == null) != (wb == null):
		diffs.append("%s: null-ness differs (a=%s, b=%s)" % [label, str(wa == null), str(wb == null)])
		return diffs
	var type_a: String = "BossWaveData" if wa is BossWaveData else "WaveData"
	var type_b: String = "BossWaveData" if wb is BossWaveData else "WaveData"
	_different(diffs, "%s type" % label, type_a, type_b)
	_different(diffs, "%s foe_scene" % label, _path_of(wa.foe_scene), _path_of(wb.foe_scene))
	_different(diffs, "%s entry_curve" % label, _path_of(wa.entry_curve), _path_of(wb.entry_curve))
	_different(diffs, "%s formation" % label, _path_of(wa.formation), _path_of(wb.formation))
	_different(diffs, "%s cinematic" % label, _path_of(wa.get("cinematic") as Resource), _path_of(wb.get("cinematic") as Resource))
	_different(diffs, "%s dive_curves" % label, _dive_paths(wa), _dive_paths(wb))
	_different(diffs, "%s row" % label, str(wa.row), str(wb.row))
	_different(diffs, "%s delay" % label, "%.4f" % wa.delay, "%.4f" % wb.delay)
	_different(diffs, "%s spacing" % label, "%.4f" % wa.spacing, "%.4f" % wb.spacing)
	_different(diffs, "%s sway_start_phase_deg" % label,
			"%.4f" % wa.sway_start_phase_deg, "%.4f" % wb.sway_start_phase_deg)
	_different(diffs, "%s fire_on_entry" % label, str(wa.fire_on_entry), str(wb.fire_on_entry))
	_different(diffs, "%s fire_in_formation" % label, str(wa.fire_in_formation), str(wb.fire_in_formation))
	_different(diffs, "%s entry_shots" % label, str(wa.entry_shots), str(wb.entry_shots))
	_different(diffs, "%s col" % label, str(wa.get("col")), str(wb.get("col")))
	_different(diffs, "%s row_span" % label, str(wa.get("row_span")), str(wb.get("row_span")))
	_different(diffs, "%s col_span" % label, str(wa.get("col_span")), str(wb.get("col_span")))
	_different(diffs, "%s mirror_entry" % label, str(wa.get("mirror_entry")), str(wb.get("mirror_entry")))
	return diffs


## Appends a difference line to [param diffs] when [param a] and [param b]
## differ.
static func _different(diffs: PackedStringArray, what: String, a: String, b: String) -> void:
	if a != b:
		diffs.append("%s differs (a=%s, b=%s)" % [what, a, b])


## The [code]resource_path[/code] of [param resource], or "&lt;null&gt;" when it is
## null.
static func _path_of(resource: Resource) -> String:
	if resource == null:
		return "<null>"
	return resource.resource_path


## The dive-curve paths of [param wave], joined, in order.
static func _dive_paths(wave: WaveData) -> String:
	var paths: PackedStringArray = PackedStringArray()
	for curve: Curve2D in wave.dive_curves:
		paths.append(_path_of(curve))
	return ", ".join(paths)
