extends Polygon2D
## A conical tractor beam that grows downward from a parent FoeBrain.
## The brain changes [member polygon] over time so no external texture is needed.

@onready var brain: FoeBrain = get_parent() as FoeBrain
## How many seconds the cone takes to grow to full height.
@export var grow_duration: float = 1.0
## Maximum cone width, in pixels.
@export var cone_width: float = 80.0
## Maximum cone height/length, in pixels.
@export var cone_height: float = 400.0

var _elapsed: float = 0.0
var _full: bool = false


func is_full() -> bool:
	return _full

func _process(delta: float) -> void:
	if brain == null or brain.get_parent() == null:
		visible = false
		return

	if brain.state != FoeBrain.State.TRACTOR_BEAM:
		visible = false
		return

	visible = true
	_elapsed += delta
	var progress: float = clampf(_elapsed / grow_duration, 0.0, 1.0)
	_full = progress >= 1.0

	# Cone points downward from the entity: top narrow at muzzle, bottom wide.
	var height: float = progress * cone_height  # max cone length in pixels
	var top_w: float = 4.0
	var bot_w: float = cone_width * progress
	polygon = PackedVector2Array([
		Vector2(-top_w / 2.0, 0.0),
		Vector2(top_w / 2.0, 0.0),
		Vector2(bot_w / 2.0, height),
		Vector2(-bot_w / 2.0, height)
	])

	# Keep the cone anchored at the foe's muzzle (nose position, matching Weapon).
	var entity: Entity = brain.get_parent() as Entity
	if is_instance_valid(entity):
		var muzzle_offset: Vector2 = Vector2.ZERO
		# Try to read muzzle_offset from a sibling Weapon if present.
		for child in entity.get_children():
			if child is Weapon:
				muzzle_offset = child.muzzle_offset
		global_position = entity.to_global(Vector2.UP * Helpers.ENTITY_HALF_WIDTH * entity.scale_aux + muzzle_offset)
