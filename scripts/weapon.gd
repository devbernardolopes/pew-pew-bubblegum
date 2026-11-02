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

var _in_flight: int = 0
var _entity: Entity = null


func _ready() -> void:
	_entity = get_parent() as Entity
	if _entity == null:
		push_error("Weapon must be a child of an Entity; firing disabled.")


## Fires one projectile from the nose of the shooter.
## A zero [param direction] fires along the nose; a non-zero one is normalized
## and used instead.
## Returns false when the weapon is out of bullets or misconfigured.
func fire(direction: Vector2 = Vector2.ZERO) -> bool:
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
	var nose: Vector2 = _entity.to_global(Vector2.UP * Helpers.ENTITY_HALF_WIDTH * _entity.scale_aux + muzzle_offset)
	var shot_direction: Vector2 = Vector2.UP.rotated(_entity.global_rotation)
	if direction != Vector2.ZERO:
		shot_direction = direction.normalized()
	projectile.launch(projectile_data, _entity.data.team, _entity, nose, shot_direction)
	projectile.set_color(_entity.color)
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
