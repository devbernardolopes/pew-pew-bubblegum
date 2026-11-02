@tool
extends Node2D

@export var scale_aux: float = 0.25:
	set(v):
		scale_aux = v
		apply_scale_to_children()


func apply_scale_to_children() -> void:
	var children: Array[Node] = find_children("*")
	if not children or children.is_empty():
		return
	for i in children.size():
		if children[i] is Entity:
			var child: Entity = children[i]
			child.scale_aux = scale_aux
