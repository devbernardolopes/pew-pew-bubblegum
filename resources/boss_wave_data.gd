class_name BossWaveData
extends WaveData
## One boss for a stage. The inherited [member foe_scene] is the boss scene and
## [member row] is the top row of its footprint.
##
## [member spacing], [member dive_curves] and the firing flags are ignored: a
## boss never dives, never fills a row and fires through its own [BossPattern].

## How deep a boss may split into pieces (piece of a piece of ... counts).
const MAX_SPLIT_DEPTH: int = 3

@export_group("Boss")
## First column of the boss footprint.
@export var col: int = 0
## Height of the footprint, in formation cells.
@export_range(1, 32) var row_span: int = 3
## Width of the footprint, in formation cells.
@export_range(1, 32) var col_span: int = 4
## Enter along the entry curve mirrored (from the right side).
@export var mirror_entry: bool = false


## Returns the problems found in this boss wave, each prefixed with
## [code][error][/code] or [code][warning][/code] and naming [param stage_path]
## and [param wave_index]. It does not call the base [method WaveData.validate]
## because the row and firing rules of a regular wave do not apply.
func validate(stage_path: String = "", wave_index: int = -1, foe_cache: Dictionary = {}) -> PackedStringArray:
	var issues: PackedStringArray = []
	var where: String = "%s wave %d" % [stage_path, wave_index]
	var foe_info: Dictionary = {}
	if foe_scene == null:
		issues.append("[error] %s: foe_scene is null." % where)
	else:
		foe_info = get_foe_info(foe_scene, foe_cache)
		if not foe_info.is_entity:
			issues.append("[error] %s: the root of %s is not an Entity." % [where, describe(foe_scene)])
		else:
			if not foe_info.has_brain:
				issues.append("[error] %s: the root of %s has no FoeBrain child." % [where, describe(foe_scene)])
			if not foe_info.has_boss_pattern:
				issues.append("[error] %s: the root of %s has no BossPattern child." % [where, describe(foe_scene)])
		if not (foe_info.data is BossData):
			issues.append("[error] %s: the data of %s is not a BossData." % [where, describe(foe_scene)])
	if formation == null:
		issues.append("[error] %s: formation is null." % where)
	else:
		if row < 0 or col < 0 or row + row_span > formation.get_row_count() \
				or col + col_span > formation.get_column_count():
			issues.append("[error] %s: a %dx%d footprint at row %d, column %d does not fit in formation %s (%dx%d)." % [
					where, row_span, col_span, row, col, describe(formation),
					formation.get_column_count(), formation.get_row_count()])
		else:
			var occupied: Vector2i = _find_occupied_cell(formation)
			if occupied.x >= 0:
				issues.append("[warning] %s: cell (%d, %d) of formation %s is inside the boss footprint; carve it out of the layout." % [
						where, occupied.y, occupied.x, describe(formation)])
		if foe_info.get("data") != null:
			var boss_speed: float = foe_info.data.base_speed * foe_info.speed_multiplier
			var peak: float = formation.get_peak_slot_speed()
			if peak >= boss_speed:
				issues.append("[warning] %s: peak slot speed %.1f is not below the boss speed %.1f (formation %s)." % [
						where, peak, boss_speed, describe(formation)])
			issues.append_array(foe_info.data.validate_dash(
					where, foe_info.speed_multiplier, foe_info.scale_aux))
	if entry_curve == null:
		issues.append("[error] %s: entry_curve is null." % where)
	if delay < 0.0:
		issues.append("[warning] %s: delay is negative (%.2f s)." % [where, delay])
	var data: BossData = foe_info.get("data") as BossData
	if data != null:
		issues.append_array(data.validate(where, int(foe_info.get("muzzle_count", 0))))
		if not data.pieces.is_empty() and foe_scene != null:
			issues.append_array(_validate_pieces(data, Vector2i(col_span, row_span), where, foe_cache, 0, [foe_scene]))
	return issues


## Returns the first occupied cell of the formation inside the footprint, as
## [code]Vector2i(col, row)[/code], or [code]Vector2i(-1, -1)[/code] when the
## footprint is free. The footprint itself is not used here; the caller has
## already checked that it fits.
func _find_occupied_cell(_formation: FormationData) -> Vector2i:
	for footprint_row: int in range(row, row + row_span):
		for footprint_col: int in range(col, col + col_span):
			if _formation.has_cell(footprint_row, footprint_col):
				return Vector2i(footprint_col, footprint_row)
	return Vector2i(-1, -1)


## Validates the split tree of [param boss] below [param where]: every piece
## must be a boss that fits inside [param spans] (the parent's footprint, in
## cells), with no cycles and at most [member MAX_SPLIT_DEPTH] levels of
## splitting. [param visited] holds the scenes on the path down to [param boss]
## (the root boss scene is already in it); [param depth] is the depth of
## [param boss] itself.
func _validate_pieces(boss: BossData, spans: Vector2i, where: String, foe_cache: Dictionary, depth: int, visited: Array) -> PackedStringArray:
	var issues: PackedStringArray = []
	for i: int in boss.pieces.size():
		var piece: BossPieceData = boss.pieces[i]
		if piece == null or piece.scene == null:
			continue
		var piece_where: String = "%s piece %d" % [where, i]
		if depth + 1 > MAX_SPLIT_DEPTH:
			issues.append("[error] %s: splits more than %d levels deep." % [piece_where, MAX_SPLIT_DEPTH])
			continue
		if visited.has(piece.scene):
			issues.append("[error] %s: the piece scene %s splits into itself (a cycle)." % [
					piece_where, describe(piece.scene)])
			continue
		if piece.col < 0 or piece.row < 0 \
				or piece.col + piece.col_span > spans.x or piece.row + piece.row_span > spans.y:
			issues.append("[error] %s: the %dx%d footprint at col %d, row %d does not fit in the parent's %dx%d footprint." % [
					piece_where, piece.col_span, piece.row_span, piece.col, piece.row, spans.x, spans.y])
		var info: Dictionary = get_foe_info(piece.scene, foe_cache)
		if not info.is_entity:
			issues.append("[error] %s: the root of %s is not an Entity." % [piece_where, describe(piece.scene)])
		else:
			if not info.has_brain:
				issues.append("[error] %s: the root of %s has no FoeBrain child." % [piece_where, describe(piece.scene)])
			if not info.has_boss_pattern:
				issues.append("[error] %s: the root of %s has no BossPattern child." % [piece_where, describe(piece.scene)])
		var piece_data: BossData = info.get("data") as BossData
		if piece_data == null:
			issues.append("[error] %s: the data of %s is not a BossData." % [piece_where, describe(piece.scene)])
			continue
		issues.append_array(piece_data.validate(piece_where, int(info.get("muzzle_count", 0))))
		if not piece_data.pieces.is_empty():
			var deeper: Array = visited + [piece.scene]
			issues.append_array(_validate_pieces(
					piece_data, Vector2i(piece.col_span, piece.row_span),
					piece_where, foe_cache, depth + 1, deeper))
	return issues
