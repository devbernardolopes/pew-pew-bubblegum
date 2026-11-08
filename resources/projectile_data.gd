class_name ProjectileData
extends Resource

@export var id: StringName = &""
## Legacy shape selector. [member polygon] wins when set; this is only the
## legacy fallback used by [method get_polygon] when [member polygon] is empty.
@export var visual: Helpers.VISUAL = Helpers.VISUAL.BULLET
## Shape points in the 128 x 128 box (larger shapes use more). When set, it
## wins over [member visual]; when empty, [member visual] is the legacy fallback.
@export var polygon: PackedVector2Array = PackedVector2Array()
@export var visual_scale: float = 0.25
@export var color: Color = Color.WHITE
@export var base_speed: float = 384.0
@export var base_damage: int = 1

@export_group("Pierce")
## How many entities the projectile may pass through after killing them.
## 0 = normal projectile. The hit after the last pass still deals damage but
## ends the projectile, so pierce_count = 2 can kill up to 3 entities.
@export_range(0, 16, 1) var pierce_count: int = 0
## Damage lost after each entity pierced. 0 = damage stays constant.
@export_range(0, 16, 1) var pierce_damage_falloff: int = 1
## Floor for the damage while piercing, so it never reaches 0.
@export_range(1, 99, 1) var pierce_min_damage: int = 1

@export_group("Explosion")
## When true, the first contact with a valid target explodes the projectile.
@export var explode_on_contact: bool = false
## Blast radius in world pixels (not scaled by visual_scale).
@export_range(0.0, 512.0, 1.0) var explosion_radius: float = 0.0
## Blast damage for a target whose nearest point is at the blast center.
@export_range(0, 99, 1) var explosion_damage: int = 0
## Blast damage for a target whose nearest point is at the rim.
@export_range(0, 99, 1) var explosion_edge_damage: int = 0
## When true (default), the entity that was hit directly also takes the blast
## damage on top of base_damage (additive). Makes big targets such as bosses
## worth aiming at.
@export var explosion_hits_direct_target: bool = true


## Returns this resource's shape: [member polygon] when it is set, otherwise the
## legacy shape of [member visual] from [Helpers]. Always a copy.
func get_polygon() -> PackedVector2Array:
	if not polygon.is_empty():
		return polygon.duplicate()
	return Helpers.get_polygon(visual)


## Returns the problems found in this Projectile's pierce and explosion data,
## each prefixed with [code][warning][/code] and naming [param where].
func validate(where: String = "") -> PackedStringArray:
	var issues: PackedStringArray = []
	var label: String = where if not where.is_empty() else "(unsaved projectile data %s)" % id
	if explode_on_contact and pierce_count > 0:
		issues.append("[warning] %s: explode_on_contact is set but pierce_count is %d; piercing is ignored for exploding projectiles." % [
				label, pierce_count])
	if explode_on_contact and explosion_radius <= 0.0:
		issues.append("[warning] %s: explode_on_contact is set but explosion_radius is %.1f." % [
				label, explosion_radius])
	if explode_on_contact and explosion_damage <= 0 and base_damage <= 0:
		issues.append("[warning] %s: explode_on_contact is set but neither explosion_damage (%d) nor base_damage (%d) damages anything." % [
				label, explosion_damage, base_damage])
	if explode_on_contact and explosion_edge_damage > explosion_damage:
		issues.append("[warning] %s: explosion_edge_damage (%d) exceeds explosion_damage (%d)." % [
				label, explosion_edge_damage, explosion_damage])
	if pierce_count > 0 and pierce_min_damage > base_damage:
		issues.append("[warning] %s: pierce_min_damage (%d) exceeds base_damage (%d); a pierced shot could deal more damage than its first hit." % [
				label, pierce_min_damage, base_damage])
	return issues
