@tool
class_name CinematicData
extends Resource
## How a boss entrance plays: the camera eases out to [member zoom] while a
## ceasefire ([CombatGate]) holds fire until the boss (or another condition)
## is in place, then the camera eases back to 1.0. Null on a [BossWaveData]
## means no cinematic and unchanged behaviour.

enum CeasefireUntil { BOSS_IN_FORMATION, ALL_WAVES_FORMED, FIXED_DURATION }

## Zoom at the widest point of the cinematic; below 1.0 shows more than the
## base play area.
@export_range(0.5, 1.0, 0.01) var zoom: float = 0.85
## Seconds the zoom-out takes.
@export_range(0.0, 10.0, 0.05, "suffix:s") var zoom_out_time: float = 1.0
## Seconds the camera holds at [member zoom] once the release condition met.
@export_range(0.0, 10.0, 0.05, "suffix:s") var hold_time: float = 0.5
## Seconds the zoom back to 1.0 takes.
@export_range(0.0, 10.0, 0.05, "suffix:s") var zoom_in_time: float = 1.0
@export var trans: Tween.TransitionType = Tween.TRANS_SINE
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

@export_group("Ceasefire")
## Whether the hero's fire is locked for the cinematic.
@export var lock_hero_fire: bool = true
## Whether the foes' fire is locked for the cinematic.
@export var lock_foe_fire: bool = true
## What the ceasefire waits for before the hold starts.
@export var ceasefire_until: CeasefireUntil = CeasefireUntil.BOSS_IN_FORMATION
## Used only by FIXED_DURATION, counted from the start of the cinematic.
@export_range(0.0, 60.0, 0.1, "suffix:s") var ceasefire_duration: float = 4.0
## Safety net for every mode: the condition counts as met at this time even
## if it never happened (a stuck boss must not soft-lock the stage).
@export_range(1.0, 60.0, 0.1, "suffix:s") var max_duration: float = 12.0


## Returns the problems found in this cinematic, each prefixed with
## [code][error][/code] or [code][warning][/code] and naming [param where].
func validate(where: String) -> PackedStringArray:
	var issues: PackedStringArray = []
	if zoom < 0.5 or zoom > 1.0:
		issues.append("[error] %s: zoom %.2f is outside 0.5 to 1.0." % [where, zoom])
	if ceasefire_until == CeasefireUntil.FIXED_DURATION and ceasefire_duration <= 0.0:
		issues.append("[warning] %s: ceasefire_until is FIXED_DURATION but ceasefire_duration is %.2f s." % [
				where, ceasefire_duration])
	if max_duration < zoom_out_time:
		issues.append("[warning] %s: max_duration (%.2f s) is shorter than zoom_out_time (%.2f s)." % [
				where, max_duration, zoom_out_time])
	if not lock_hero_fire and not lock_foe_fire:
		issues.append("[warning] %s: both lock flags are false, so the ceasefire does nothing." % where)
	return issues


## Warns when [param wave]'s entry curve starts inside the area the zoom-out
## reveals but outside the base play area: waiting foes and the entry would be
## visible as they appear. Both the curve start and its mirrored version are
## checked, because foes wait on either side.
func validate_entry_reveal(wave: WaveData, wave_index: int, stage_path: String) -> PackedStringArray:
	var issues: PackedStringArray = []
	if wave == null or wave.entry_curve == null:
		return issues
	var game_size: Vector2 = Helpers.get_game_size()
	var visible: Rect2 = CameraDirector.visible_rect_for(zoom, game_size)
	var base: Rect2 = Rect2(Vector2.ZERO, game_size)
	var points: PackedVector2Array = wave.entry_curve.get_baked_points()
	if points.is_empty():
		return issues
	var start: Vector2 = points[0]
	var mirrored: Vector2 = Vector2(game_size.x - start.x, start.y)
	for point: Vector2 in [start, mirrored]:
		if visible.has_point(point) and not base.has_point(point):
			var margin_x: float = maxf(-point.x, point.x - game_size.x)
			var margin_y: float = maxf(-point.y, point.y - game_size.y)
			issues.append("[warning] %s: entry curve of wave %d starts inside the area revealed by the zoom-out (margin %.1f px horizontal, %.1f px vertical); waiting foes and the entry will be visible as they appear. Lower the zoom or start the curve further out." % [
					stage_path, wave_index, margin_x, margin_y])
			break
	return issues
