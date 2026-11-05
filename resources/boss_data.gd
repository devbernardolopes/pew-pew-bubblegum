class_name BossData
extends EntityData
## Behavior of a boss: a big foe that survives ramming and changes position and
## firing pattern as it loses health. The phases are read by [BossPattern].

## Health phases, from full health down. The first one should start at 1.0.
@export var phases: Array[BossPhaseData] = []


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
	return issues
