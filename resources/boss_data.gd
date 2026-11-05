class_name BossData
extends EntityData
## Behavior of a boss: a big foe that survives ramming and changes position and
## firing pattern as it loses health. The phases are read by [BossPattern].

## Health phases, from full health down. The first one should start at 1.0.
@export var phases: Array[BossPhaseData] = []
## Pieces the boss splits into when it dies.
@export var pieces: Array[BossPieceData] = []


func _init() -> void:
	dies_on_contact = false
	center_on_bounds = true


## Returns the problems found in this boss data, each prefixed with
## [code][error][/code] or [code][warning][/code] and naming [param where].
## [param muzzle_count] is the number of muzzles found in the boss scene.
func validate(where: String, muzzle_count: int) -> PackedStringArray:
	var issues: PackedStringArray = []
	if phases.is_empty():
		issues.append("[error] %s: the boss has no health phase." % where)
		return issues
	var previous: float = INF
	for i: int in phases.size():
		var phase: BossPhaseData = phases[i]
		if phase == null:
			issues.append("[error] %s: phase %d is null." % [where, i])
			continue
		if phase.health_below >= previous:
			issues.append("[error] %s: phase %d starts at %.2f, not below the previous phase's %.2f." % [
					where, i, phase.health_below, previous])
		previous = phase.health_below
		if phase.fire_pattern == BossPhaseData.FirePattern.NONE:
			continue
		if phase.fire_interval <= 0.0:
			issues.append("[error] %s: phase %d fires with a fire_interval of %.2f s." % [
					where, i, phase.fire_interval])
		if muzzle_count == 0:
			issues.append("[error] %s: phase %d fires, but the boss scene has no muzzle." % [where, i])
		for index: int in phase.muzzle_indices:
			if index < 0 or index >= muzzle_count:
				issues.append("[error] %s: phase %d uses muzzle index %d, but the boss scene has %d muzzles." % [
						where, i, index, muzzle_count])
	if phases[0] != null and phases[0].health_below < 1.0:
		issues.append("[warning] %s: the first phase starts at %.2f, so the boss never uses its full health." % [
				where, phases[0].health_below])
	if dies_on_contact:
		issues.append("[warning] %s: dies_on_contact is on, so ramming the hero destroys the boss." % where)
	if not center_on_bounds:
		issues.append("[warning] %s: center_on_bounds is off, so the boss is not centered on its shape." % where)
	if max_health <= 1:
		issues.append("[warning] %s: max_health is %d, so the boss has no health to phase through." % [
				where, max_health])
	for i: int in pieces.size():
		var piece: BossPieceData = pieces[i]
		if piece == null:
			issues.append("[error] %s piece %d: the piece is null." % [where, i])
			continue
		if piece.scene == null:
			issues.append("[error] %s piece %d: the piece scene is null." % [where, i])
	for i: int in pieces.size():
		var first: BossPieceData = pieces[i]
		if first == null:
			continue
		for j: int in range(i + 1, pieces.size()):
			var second: BossPieceData = pieces[j]
			if second == null:
				continue
			if _rectangles_overlap(first, second):
				issues.append("[warning] %s: pieces %d and %d overlap." % [where, i, j])
	return issues


## Whether the footprints of two pieces (in parent-relative cells) intersect.
func _rectangles_overlap(first: BossPieceData, second: BossPieceData) -> bool:
	var ax1: int = first.col
	var ay1: int = first.row
	var ax2: int = first.col + first.col_span
	var ay2: int = first.row + first.row_span
	var bx1: int = second.col
	var by1: int = second.row
	var bx2: int = second.col + second.col_span
	var by2: int = second.row + second.row_span
	return ax1 < bx2 and bx1 < ax2 and ay1 < by2 and by1 < ay2
