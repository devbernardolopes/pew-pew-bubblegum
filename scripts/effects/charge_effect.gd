class_name ChargeEffect
extends Node2D
## Code-drawn charge particles converging on a muzzle, in the style of the
## other effects. [Entity] creates one per charge-enabled ship, as a child of
## the ship positioned at the charge weapon's [method Weapon.get_muzzle_local],
## and drives it with [method set_progress] every frame; progress 0 hides it.
## Particle data is pooled in arrays: no node is instantiated per particle.

## Seconds the ready pulse ring stays visible.
const PULSE_DURATION: float = 0.18
## Particle radius in pixels.
const PARTICLE_RADIUS: float = 2.5
## Inward speed multiplier, slow at the start of the charge, fast at the end.
const SPEED_MIN: float = 0.6
const SPEED_MAX: float = 3.0

var _progress: float = 0.0
var _ready_state: bool = false
var _was_ready: bool = false
var _pulse_left: float = 0.0
## The entity colour particles are mixed from towards white.
var _base_color: Color = Color.WHITE
var _ring_radius: float = 26.0
var _particles_min: int = 3
var _particles_max: int = 28
## Pooled per-particle state, indexed by particle.
var _angles: PackedFloat32Array = PackedFloat32Array()
var _distances: PackedFloat32Array = PackedFloat32Array()
var _speed_factors: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	visible = false


func _physics_process(delta: float) -> void:
	if _progress <= 0.0:
		return
	_ensure_pool()
	var eased: float = _eased_progress()
	var count: int = _active_count(eased)
	var speed: float = _ring_radius * lerpf(SPEED_MIN, SPEED_MAX, eased)
	for i: int in count:
		_distances[i] -= speed * _speed_factors[i] * delta
		if _distances[i] < PARTICLE_RADIUS * 2.0:
			_respawn(i)
	if _pulse_left > 0.0:
		_pulse_left = maxf(_pulse_left - delta, 0.0)
	queue_redraw()


## Sets the charge configuration from the owning Entity's [EntityData].
func configure(base_color: Color, ring_radius: float, particles_min: int, particles_max: int) -> void:
	_base_color = base_color
	_ring_radius = maxf(ring_radius, 4.0)
	_particles_min = maxi(particles_min, 0)
	_particles_max = maxi(particles_max, _particles_min)
	_ensure_pool()


## Shows the charge at [param progress] (0..1); 0 hides it. [param ready]
## marks the threshold: a one-shot pulse plays when it is first reached, then
## a steady brighter state is held until the progress drops again.
func set_progress(progress: float, is_ready: bool) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	_ready_state = is_ready and _progress >= 1.0
	if _progress <= 0.0:
		_was_ready = false
		_pulse_left = 0.0
		visible = false
		return
	visible = true
	if _ready_state and not _was_ready:
		_pulse_left = PULSE_DURATION
	_was_ready = _ready_state
	queue_redraw()


func _draw() -> void:
	if _progress <= 0.0:
		return
	var eased: float = _eased_progress()
	var color: Color = _base_color.lerp(Color.WHITE, 0.35 + 0.65 * eased)
	if _ready_state:
		color = color.lerp(Color.WHITE, 0.5)
	var alpha: float = lerpf(0.15, 1.0, eased)
	var count: int = _active_count(eased)
	for i: int in count:
		var pos: Vector2 = Vector2(cos(_angles[i]), sin(_angles[i])) * _distances[i]
		draw_circle(pos, PARTICLE_RADIUS, Color(color, alpha))
	if _pulse_left > 0.0:
		var pulse: float = 1.0 - _pulse_left / PULSE_DURATION
		var radius: float = lerpf(PARTICLE_RADIUS * 2.0, _ring_radius, pulse)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(Color.WHITE, (1.0 - pulse) * alpha), 2.0)
	elif _ready_state:
		draw_arc(Vector2.ZERO, PARTICLE_RADIUS * 3.0, 0.0, TAU, 24, Color(Color.WHITE, alpha), 1.5)


## Early charge stays subtle: the eased progress drives count, speed, alpha.
func _eased_progress() -> float:
	return ease(_progress, -2.0)


func _active_count(eased: float) -> int:
	return clampi(int(roundf(lerpf(float(_particles_min), float(_particles_max), eased))), 0, _angles.size())


func _ensure_pool() -> void:
	if _angles.size() >= _particles_max:
		return
	while _angles.size() < _particles_max:
		_angles.append(0.0)
		_distances.append(0.0)
		_speed_factors.append(1.0)
		_respawn(_angles.size() - 1)


func _respawn(index: int) -> void:
	_angles[index] = randf() * TAU
	_distances[index] = _ring_radius * randf_range(0.7, 1.0)
	_speed_factors[index] = randf_range(0.7, 1.3)
