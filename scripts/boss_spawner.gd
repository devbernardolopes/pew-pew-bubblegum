class_name BossSpawner
extends RefCounted
## Spawns bosses and their death pieces. Static-only, so a deferred split bound
## to [method _spawn_pieces] survives the dying parent (see hazard 2 of the
## Lego-boss plan): the parent's [BossPattern] is freed the frame it dies.

## Pieces requested by [method request_split] that are not spawned yet. Added to
## [method StageDirector._count_live_foes] so the stage cannot clear between the
## parent's death and the deferred spawn.
static var pending_pieces: int = 0


## Spawns one boss of [param scene] into [param container], anchored on the
## [param footprint] rectangle of [param formation]. With a [param curve] the
## boss enters normally (the [method StageDirector._spawn_boss] path); without
## one it starts at [param origin] and settles (the piece path). Returns the
## entity, or null when it cannot be built.
static func spawn(scene: PackedScene, container: Node, formation: Formation, footprint: Rect2i, entered: Callable, curve: Curve2D = null, mirror: bool = false, origin: Transform2D = Transform2D.IDENTITY) -> Entity:
	if scene == null or container == null or formation == null:
		push_error("BossSpawner.spawn(): scene, container and formation must not be null.")
		return null
	var entity: Entity = scene.instantiate() as Entity
	if entity == null:
		push_error("BossSpawner.spawn(): the root of %s is not an Entity." % scene.resource_path)
		return null
	container.add_child(entity)
	var anchor: Marker2D = formation.create_anchor(footprint.position.y, footprint.position.x, footprint.size.y, footprint.size.x)
	var brain: FoeBrain = entity.get_node_or_null(^"FoeBrain") as FoeBrain
	var pattern: BossPattern = entity.get_node_or_null(^"BossPattern") as BossPattern
	if brain == null or pattern == null:
		push_error("BossSpawner.spawn(): the boss scene needs both a FoeBrain and a BossPattern child.")
		entity.queue_free()
		return null
	if curve != null:
		brain.setup(curve, mirror, anchor, 0.0, [])
	else:
		entity.global_transform = origin
		brain.setup_settle(anchor)
	pattern.setup(anchor, formation, footprint, entered)
	if entered.is_valid():
		brain.entered_formation.connect(entered)
	return entity


## Synchronous half of a boss split, called from the parent's [method
## BossPattern._on_entity_died]. Counts the usable pieces into [member
## pending_pieces] right away (hazard 1) and defers the real spawn through a
## static [Callable] (hazard 2). Captures everything the deferred half needs,
## because the parent is freed the same frame.
static func request_split(parent: Entity, data: BossData, container: Node, formation: Formation, footprint: Rect2i, entered: Callable) -> void:
	var pieces: Array[BossPieceData] = []
	for piece: BossPieceData in data.pieces:
		if piece != null and piece.scene != null:
			pieces.append(piece)
	if pieces.is_empty():
		return
	pending_pieces += pieces.size()
	var world: Transform2D = parent.global_transform
	_spawn_pieces.bind(pieces, world, container, formation, footprint, entered).call_deferred()


## Deferred half of a split. Every piece is its own guarded spawn; the pending
## counter always goes down by one per piece, success or not, and never below
## 0. Does not touch the parent: [param world] already holds its transform.
static func _spawn_pieces(pieces: Array[BossPieceData], world: Transform2D, container: Node, formation: Formation, footprint: Rect2i, entered: Callable) -> void:
	for piece: BossPieceData in pieces:
		if not is_instance_valid(container) or not is_instance_valid(formation):
			pending_pieces = maxi(pending_pieces - 1, 0)
			continue
		var rect: Rect2i = Rect2i(
			footprint.position + Vector2i(piece.col, piece.row),
			Vector2i(piece.col_span, piece.row_span))
		var start: Transform2D = Transform2D(world.get_rotation(), world * piece.spawn_offset)
		spawn(piece.scene, container, formation, rect, entered, null, false, start)
		pending_pieces = maxi(pending_pieces - 1, 0)
