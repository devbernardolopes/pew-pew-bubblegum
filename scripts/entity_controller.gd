class_name EntityController
extends Node


func get_move_vector() -> Vector2:
	return Vector2.ZERO


func get_move_vector_h() -> Vector2:
	return Vector2.ZERO


func get_direction_h() -> float:
	return 0.0


## Returns true on the frame the controller asks the shooter to fire.
func wants_fire() -> bool:
	return false


func get_move_intent() -> Vector2:
	return get_move_vector()
