class_name BossPieceData
extends Resource
## One piece a boss splits into when it dies: the scene of the piece and where
## it belongs inside the parent's formation footprint.

## The boss scene of this piece (an Entity with FoeBrain and BossPattern).
@export var scene: PackedScene = null
## Footprint of the piece in formation cells, relative to the top-left cell of
## the parent's footprint. It must lie inside the parent's footprint.
@export var col: int = 0
@export var row: int = 0
@export_range(1, 32) var col_span: int = 1
@export_range(1, 32) var row_span: int = 1
## Where the piece starts, in pixels in the parent's local space (unscaled, like
## muzzle positions): where it sits inside the parent's shape.
@export var spawn_offset: Vector2 = Vector2.ZERO
