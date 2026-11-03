class_name WaveData
extends Resource
## A single wave of foes for a stage.

## The foe scene to spawn (e.g. foe_01.tscn, foe_02.tscn).
@export var foe_scene: PackedScene = null
## The entry curve for this wave.
@export var entry_curve: Curve2D = null
## The formation row this wave fills.
@export var row: int = 0
## Seconds between two foes entering from the same side.
@export var spacing: float = 0.25
## The formation layout for this wave.
@export var formation: FormationData = null
## Seconds after the previous wave started before this one begins.
@export var delay: float = 0.0


## Returns the problems found in this wave, each prefixed with [code][error][/code]
## or [code][warning][/code] and naming [param stage_path] and [param wave_index].
## [param foe_cache] keeps one instantiation per distinct [member foe_scene]
## across a whole stage validation; pass the same dictionary for every wave.
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
		elif not foe_info.has_brain:
			issues.append("[error] %s: the root of %s has no FoeBrain child." % [where, describe(foe_scene)])
	if formation == null:
		issues.append("[error] %s: formation is null." % where)
	else:
		if row < 0 or row >= formation.rows:
			issues.append("[error] %s: row %d is outside formation %s, which has %d rows." % [
					where, row, describe(formation), formation.rows])
		if foe_info.get("data") != null:
			var foe_speed: float = foe_info.data.base_speed * foe_info.speed_multiplier
			var peak: float = formation.get_peak_slot_speed()
			if peak >= foe_speed:
				issues.append("[warning] %s: peak slot speed %.1f is not below the foe speed %.1f (formation %s)." % [
						where, peak, foe_speed, describe(formation)])
	if entry_curve == null:
		issues.append("[error] %s: entry_curve is null." % where)
	if spacing < 0.0:
		issues.append("[warning] %s: spacing is negative (%.2f s)." % [where, spacing])
	if delay < 0.0:
		issues.append("[warning] %s: delay is negative (%.2f s)." % [where, delay])
	return issues


## A printable name for [param resource] in a validation message; hand-built
## resources have no path, so the fallback still says what kind of thing it is.
static func describe(resource: Resource) -> String:
	if resource == null:
		return "(null)"
	if not resource.resource_path.is_empty():
		return resource.resource_path
	var script: Script = resource.get_script() as Script
	if script == null:
		return "(unsaved %s)" % resource.get_class()
	return "(unsaved %s)" % script.resource_path.get_file().get_basename()


## Instantiates [param scene] once per distinct scene, reads what validation
## needs and frees it right away, so no foe is ever added to the tree here.
## The dictionary it returns has the keys [code]is_entity[/code],
## [code]has_brain[/code], [code]data[/code], [code]scale_aux[/code] and
## [code]speed_multiplier[/code].
static func get_foe_info(scene: PackedScene, cache: Dictionary) -> Dictionary:
	if cache.has(scene):
		return cache[scene]
	var info: Dictionary = {
		"is_entity": false,
		"has_brain": false,
		"data": null,
		"scale_aux": 1.0,
		"speed_multiplier": 1.0,
	}
	var root: Node = scene.instantiate()
	var entity: Entity = root as Entity
	if entity != null:
		info.is_entity = true
		info.has_brain = entity.get_node_or_null("FoeBrain") is FoeBrain
		info.data = entity.data
		info.scale_aux = entity.scale_aux
		info.speed_multiplier = entity.speed_multiplier
	root.free()
	cache[scene] = info
	return info
