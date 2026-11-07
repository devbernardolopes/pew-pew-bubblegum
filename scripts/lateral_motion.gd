class_name LateralMotion
extends RefCounted
## Horizontal momentum drift: while a direction is held the velocity is
## exactly the top speed (no acceleration ramp, instant reversal), and when
## the input ends the ship slides to rest with a constant deceleration
## authored so the slide from full speed covers a fixed distance. The owner
## applies the returned displacement through its screen-edge clamp and then
## reports how much of it was actually allowed.

## Position difference below this is treated as the clamp blocking the motion.
const POSITION_EPSILON: float = 0.001

## Current horizontal velocity in pixels per second.
var velocity: float = 0.0


## The requested x displacement for this physics frame, before the clamp.
## [param direction] is the lateral input (-1..1 in practice, but any value
## is scaled by [param top_speed]); [param drift_distance_px] is how far the
## ship slides from full speed to rest when the input ends.
func step(direction: float, delta: float, top_speed: float, drift_distance_px: float) -> float:
	if direction != 0.0:
		velocity = direction * top_speed
		return velocity * delta
	if drift_distance_px <= 0.0 or velocity == 0.0:
		velocity = 0.0
		return 0.0
	var decel: float = top_speed * top_speed / (2.0 * drift_distance_px)
	var new_velocity: float = move_toward(velocity, 0.0, decel * delta)
	var displacement: float = (velocity + new_velocity) * 0.5 * delta
	velocity = new_velocity
	return displacement


## Tells the motion how much of [param requested] the clamp actually allowed:
## a blocked move zeroes the velocity (no sticking, no bounce).
func report(requested: float, moved: float) -> void:
	if absf(moved) < absf(requested) - POSITION_EPSILON:
		velocity = 0.0


## Forgets any slide in progress (death, capture, dash, ...).
func reset() -> void:
	velocity = 0.0


## Whether the ship is currently sliding or being driven.
func is_moving() -> bool:
	return velocity != 0.0
