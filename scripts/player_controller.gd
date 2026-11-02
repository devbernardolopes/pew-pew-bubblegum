class_name PlayerController
extends EntityController


func get_direction_h() -> float:
	return Input.get_axis("left", "right")
