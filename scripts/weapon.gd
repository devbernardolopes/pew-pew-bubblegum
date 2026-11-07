class_name Weapon
extends Node
## Spawns [Projectile]s from its parent [Entity].
## The Weapon is team-agnostic: the projectile takes the shooter's team, so a
## foe with a Weapon fires towards its own nose without any extra code.

## The projectile to fire; a null value disables firing.
@export var projectile_data: ProjectileData = null
## Maximum number of bullets alive at the same time.
@export var max_in_flight: int = 4
## Extra tweak in the Entity's local space, added to the nose position.
@export var muzzle_offset: Vector2 = Vector2.ZERO
## Identity of this weapon among its Entity's weapons. The first Weapon
## child of an Entity is the primary, whatever id it carries.
@export var weapon_id: StringName = &"primary"
## When true, fired projectiles take the shooter's colour (today's behaviour);
## when false, they keep [member ProjectileData.color].
@export var override_color: bool = true

var _in_flight: int = 0
var _entity: Entity = null


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("Weapon must be a child of an Entity; firing disabled.")
	if projectile_data != null:
		var owner_name: String = _entity.name if _entity != null else &"(orphan weapon)"
		for issue: String in projectile_data.validate("Weapon %s of Entity %s" % [weapon_id, owner_name]):
			push_warning(issue)


## Fires one projectile from the nose of the shooter.
## A zero [param direction] fires along the nose; a non-zero one is normalized
## and used instead.
## Returns false when the weapon is out of bullets or misconfigured.
func fire(direction: Vector2 = Vector2.ZERO) -> bool:
	if _entity == null:
		return false
	return _launch(_entity.to_global(get_muzzle_local()), direction)


## Whether [method fire] would launch a projectile right now: data set, owner
## ready, the in-flight pool not full, and the [CombatGate] open for its team.
func can_fire() -> bool:
	if projectile_data == null or _entity == null or _in_flight >= max_in_flight:
		return false
	if _entity.data != null and not CombatGate.is_open_for(_entity.data.team):
		return false
	return true


## The nose position in the Entity's local space, shared by [method fire] and
## the charge effect.
func get_muzzle_local() -> Vector2:
	var scale: float = _entity.scale_aux if _entity != null else 1.0
	return Vector2.UP * Helpers.ENTITY_HALF_WIDTH * scale + muzzle_offset


## Fires one projectile from [param global_origin] along [param direction].
## Bosses use it to shoot from each of their muzzles; the shots still share this
## weapon's [member max_in_flight] pool.
## Returns false when the weapon is out of bullets or misconfigured.
func fire_from(global_origin: Vector2, direction: Vector2) -> bool:
	return _launch(global_origin, direction)


## Shared body of [method fire] and [method fire_from]. [param direction] is
## already in world space; a zero one falls back to the shooter's nose.
func _launch(global_origin: Vector2, direction: Vector2) -> bool:
	# The ceasefire gate is checked first: a gated shot changes no counters
	# and has no side effects, so callers retrying on a false return keep
	# their budgets and pattern steps.
	if _entity != null and _entity.data != null and not CombatGate.is_open_for(_entity.data.team):
		return false
	if projectile_data == null or _in_flight >= max_in_flight:
		return false
	if _entity == null or _entity.data == null:
		return false
	var container: Node = get_tree().get_first_node_in_group(&"projectiles")
	if container == null:
		push_error("Weapon.fire(): no node in the \"projectiles\" group.")
		return false
	var projectile: Projectile = Projectile.new()
	container.add_child(projectile)
	var shot_direction: Vector2 = Vector2.UP.rotated(_entity.global_rotation)
	if direction != Vector2.ZERO:
		shot_direction = direction.normalized()
	projectile.launch(projectile_data, _entity.data.team, _entity, global_origin, shot_direction)
	if override_color:
		projectile.set_color(_entity.data.color)
	_entity.play_fire_feedback()
	_in_flight += 1
	projectile.tree_exited.connect(_on_projectile_gone)
	_entity.shots_fired += 1
	# Play fire sound from entity's sound profile
	if _entity.data != null and _entity.data.sound_profile != null and _entity.data.sound_profile.fire != null:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.stream = _entity.data.sound_profile.fire
		player.bus = &"SFX"
		get_tree().current_scene.add_child(player)
		player.play()
		player.finished.connect(func() -> void: player.queue_free())
	return true


func _on_projectile_gone() -> void:
	_in_flight = maxi(_in_flight - 1, 0)
