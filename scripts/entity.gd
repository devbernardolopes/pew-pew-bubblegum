@tool
class_name Entity
extends Area2D
## Visuals is a north-facing Polygon2D filled with a color.
## Collision shape is a CollisionPolygon2D matching visual.

@export var data: EntityData = null:
	set(v):
		data = v
		_refresh_shape()

## The Color used to fill the Polygon2D of this Entity instance
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		if visual:
			visual.color = v

## A little helper so that I can set [param scale] quickly in the Inspector
@export var scale_aux: float = 0.25:
	set(v):
		scale_aux = v
		_refresh_shape()

@export var speed_multiplier: float = 1.0

@export_tool_button("Center") var center_button: Callable = _center_entity

var collision: CollisionPolygon2D = null
var visual: Polygon2D = null
var controller: EntityController = null
var shots_fired: int = 0
var shots_hit: int = 0
var is_dead: bool = false


func _ready() -> void:
	collision = CollisionPolygon2D.new()
	visual = Polygon2D.new()
	add_child(collision)
	add_child(visual)
	_refresh_shape()
	if not Engine.is_editor_hint():
		if controller == null:
			controller = _find_controller()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not data:
		return
	if controller == null:
		return
	if is_dead:
		return
	var dir: float = controller.get_direction_h()
	position.x += dir * data.base_speed * speed_multiplier * delta
	position.x = clampf(position.x, 
			Helpers.ENTITY_HALF_WIDTH * scale_aux, 
			get_viewport_rect().size.x - (Helpers.ENTITY_HALF_WIDTH * scale_aux))


func _center_entity() -> void:
	# The editor viewport is not the game viewport, so read the project setting.
	var viewport_width: float = float(ProjectSettings.get_setting(&"display/window/size/viewport_width"))
	position.x = viewport_width / 2.0


func _refresh_shape() -> void:
	if not data or not collision:
		return
	var points: PackedVector2Array = Helpers.get_polygon(data.visual)
	collision.polygon = points
	visual.polygon = points
	collision.scale = Vector2.ONE * scale_aux
	visual.scale = Vector2.ONE * scale_aux
	# Center the collision and the polygon in the Area2D on both axes, so that
	# the Entity pivots around the center of its shape.
	collision.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.position = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * scale_aux * -1.0
	visual.color = color
	_apply_layers()


## Assigns the physics layers of this Entity according to its team.
## Only one side of an interaction lists the other in its mask, otherwise
## every hit fires twice.
func _apply_layers() -> void:
	match data.team:
		Helpers.TEAM.FRIEND:
			collision_layer = PhysicsLayers.FRIEND
			collision_mask = 0
		Helpers.TEAM.FOE:
			collision_layer = PhysicsLayers.FOE
			collision_mask = PhysicsLayers.FRIEND
		Helpers.TEAM.NEUTRAL:
			collision_layer = 0
			collision_mask = 0


func _find_controller() -> EntityController:
	for child: Node in get_children():
		if child is EntityController:
			return child as EntityController
	return null
