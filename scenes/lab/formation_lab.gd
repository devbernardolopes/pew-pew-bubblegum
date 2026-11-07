@tool
extends Node2D

@export var formation_name: StringName = &"":
	set(v):
		formation_name = v

@export_tool_button("Save") var save_button: Callable = _save_formation

@onready var sketchpad: TileMapLayer = $Sketchpad


func _save_formation() -> void:
	if not sketchpad:
		return
	
