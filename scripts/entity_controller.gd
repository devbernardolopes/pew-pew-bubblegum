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


## The weapon the controller asks the shooter to fire this frame, or [code]&""[/code]
## for no shot. Foe controllers keep the default: [code]&"primary"[/code] when
## [method wants_fire] is true.
func get_fire_request() -> StringName:
	return &"primary" if wants_fire() else &""


## Charge progress (0..1) of the controller's current charge, 0 when not charging.
func get_charge_progress() -> float:
	return 0.0


## Whether the controller's current charge reached its threshold.
func is_charge_ready() -> bool:
	return false


func get_move_intent() -> Vector2:
	return get_move_vector()
