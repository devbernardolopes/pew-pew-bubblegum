class_name StageData
extends Resource
## A stage is an ordered list of waves.

@export var waves: Array[WaveData] = []
@export var music_stream: AudioStream = null


## Returns every problem found in this stage, each prefixed with [code][error][/code]
## or [code][warning][/code] and naming this stage's resource path and wave index.
## Errors would crash or silently skip a wave; warnings only look wrong.
func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	var path: String = resource_path if not resource_path.is_empty() else "(unsaved stage)"
	if waves.is_empty():
		issues.append("[error] %s: the stage has no waves." % path)
		return issues
	# The cache keeps one foe scene instantiation per distinct scene for the
	# whole stage, so validation never builds the same foe twice.
	var foe_cache: Dictionary = {}
	for i: int in waves.size():
		var wave: WaveData = waves[i]
		if wave == null:
			issues.append("[error] %s wave %d: the wave is null." % [path, i])
			continue
		issues.append_array(wave.validate(path, i, foe_cache))
	issues.append_array(_validate_overlaps(path, foe_cache))
	return issues


## Reports waves that would share a slot, or that would visually overlap
## because their formations sit too close together.
func _validate_overlaps(path: String, foe_cache: Dictionary) -> PackedStringArray:
	var issues: PackedStringArray = []
	for i: int in waves.size():
		var a: WaveData = waves[i]
		if a == null or a.formation == null:
			continue
		for j: int in range(i + 1, waves.size()):
			var b: WaveData = waves[j]
			if b == null or b.formation == null:
				continue
			if a.formation == b.formation:
				if a.row == b.row:
					issues.append("[warning] %s: waves %d and %d both fill row %d of formation %s." % [
							path, i, j, a.row, WaveData.describe(a.formation)])
				continue
			var scale_a: float = _foe_scale(a, foe_cache)
			var scale_b: float = _foe_scale(b, foe_cache)
			if scale_a <= 0.0 or scale_b <= 0.0:
				continue
			var foe_size: float = Helpers.ENTITY_WIDTH * maxf(scale_a, scale_b)
			var distance: float = absf(float(a.row) * a.formation.spacing.y - float(b.row) * b.formation.spacing.y)
			if distance >= foe_size:
				continue
			if not _rows_overlap_horizontally(a.formation, b.formation):
				continue
			issues.append("[warning] %s: waves %d (row %d) and %d (row %d) are %.1f px apart vertically, less than the %.1f px foe size." % [
					path, i, a.row, j, b.row, distance, foe_size])
	return issues


## Returns the foe size factor of [param wave]'s scene, or 0.0 when the scene
## cannot provide one.
func _foe_scale(wave: WaveData, foe_cache: Dictionary) -> float:
	if wave.foe_scene == null:
		return 0.0
	var info: Dictionary = WaveData.get_foe_info(wave.foe_scene, foe_cache)
	if not info.is_entity:
		return 0.0
	return info.scale_aux


## Tells whether two formations, both centered on the same origin, share any
## horizontal extent while they sway.
func _rows_overlap_horizontally(a: FormationData, b: FormationData) -> bool:
	var a_min: float = -a.get_half_width() - a.sway_amplitude
	var a_max: float = a.get_half_width() + a.sway_amplitude
	var b_min: float = -b.get_half_width() - b.sway_amplitude
	var b_max: float = b.get_half_width() + b.sway_amplitude
	return a_min < b_max and b_min < a_max
