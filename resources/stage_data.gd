@tool
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
	issues.append_array(_validate_formations())
	issues.append_array(_validate_overlaps(path, foe_cache))
	issues.append_array(_validate_cinematic(path))
	return issues


## Warns about stages with more than one boss cinematic (only the first is
## used) and checks every wave's entry curve against the revealed area of the
## stage's boss cinematic.
func _validate_cinematic(path: String) -> PackedStringArray:
	var issues: PackedStringArray = []
	var cinematic: CinematicData = null
	var cinematic_wave: int = -1
	for i: int in waves.size():
		var boss: BossWaveData = waves[i] as BossWaveData
		if boss != null and boss.cinematic != null:
			if cinematic == null:
				cinematic = boss.cinematic
				cinematic_wave = i
			else:
				issues.append("[warning] %s: more than one boss wave has a cinematic (waves %d and %d); only the first is used." % [
						path, cinematic_wave, i])
	if cinematic == null:
		return issues
	for i: int in waves.size():
		var wave: WaveData = waves[i]
		if wave != null:
			issues.append_array(cinematic.validate_entry_reveal(wave, i, path))
	return issues


## Validates every distinct formation of the stage once, so a formation shared
## by several waves is not reported several times.
func _validate_formations() -> PackedStringArray:
	var issues: PackedStringArray = []
	var formations: Dictionary = {}
	for wave: WaveData in waves:
		if wave != null and wave.formation != null:
			formations[wave.formation] = true
	for formation: FormationData in formations:
		issues.append_array(formation.validate())
	return issues


## Reports waves that would share a slot, or that would visually overlap
## because their formations sit too close together. Boss footprints are checked
## separately, since they claim a rectangle of cells instead of a row.
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
			if a is BossWaveData or b is BossWaveData:
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
	issues.append_array(_validate_boss_overlaps(path))
	return issues


## Reports regular waves that fill cells inside a boss footprint, and boss
## footprints that intersect each other, within the same formation.
func _validate_boss_overlaps(path: String) -> PackedStringArray:
	var issues: PackedStringArray = []
	for i: int in waves.size():
		var boss: BossWaveData = waves[i] as BossWaveData
		if boss == null or boss.formation == null:
			continue
		for j: int in waves.size():
			if i == j:
				continue
			var other: WaveData = waves[j]
			if other == null or other.formation != boss.formation:
				continue
			var other_boss: BossWaveData = other as BossWaveData
			if other_boss != null:
				if j > i and _boss_footprints_intersect(boss, other_boss):
					issues.append("[warning] %s: bosses of waves %d and %d claim overlapping cells of formation %s." % [
							path, i, j, WaveData.describe(boss.formation)])
				continue
			if other.row < boss.row or other.row >= boss.row + boss.row_span:
				continue
			var clash: int = _first_column_in_span(other.formation, other.row, boss.col, boss.col_span)
			if clash >= 0:
				issues.append("[warning] %s: wave %d fills row %d (column %d) of formation %s inside the footprint of boss wave %d." % [
						path, j, other.row, clash, WaveData.describe(boss.formation), i])
	return issues


## The first occupied column of [param row] that lies in the span, or -1.
func _first_column_in_span(formation: FormationData, row: int, col: int, col_span: int) -> int:
	for column: int in formation.get_row_columns(row):
		if column >= col and column < col + col_span:
			return column
	return -1


## Whether two boss footprints share at least one cell.
func _boss_footprints_intersect(a: BossWaveData, b: BossWaveData) -> bool:
	var rows_overlap: bool = a.row < b.row + b.row_span and b.row < a.row + a.row_span
	var cols_overlap: bool = a.col < b.col + b.col_span and b.col < a.col + a.col_span
	return rows_overlap and cols_overlap


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
