extends Node

func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		if event.is_action("escape"):
			get_tree().quit()
