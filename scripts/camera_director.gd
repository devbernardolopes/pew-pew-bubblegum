class_name CameraDirector
extends Camera2D
## The scene's only camera: centered on the actual viewport rect, with
## decaying random shake and non-stacking zoom punches composed over a
## cinematic base zoom. Zoom is always derived in [_process] from
## [_base_zoom] and [_punch]; tweens animate those floats, never [member zoom].
## Gameplay never reads the camera, so zoom changes only what is drawn.

## Global multiplier applied to every shake at once.
@export var shake_scale: float = 1.0
## Hard clamp for the shake offset, in pixels.
@export var max_shake_offset: float = 12.0

var _base_zoom: float = 1.0
var _punch: float = 0.0
var _base_zoom_tween: Tween = null
var _punch_tween: Tween = null
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_time_left: float = 0.0


func _ready() -> void:
	add_to_group(&"camera_director")
	_recenter()
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_recenter):
		viewport.size_changed.connect(_recenter)


func _process(delta: float) -> void:
	zoom = Vector2.ONE * _base_zoom * (1.0 + _punch)
	if _shake_time_left > 0.0:
		_shake_time_left -= delta
		if _shake_time_left <= 0.0:
			_shake_time_left = 0.0
			_shake_intensity = 0.0
			offset = Vector2.ZERO
		else:
			var decayed: float = _shake_intensity * (_shake_time_left / _shake_duration) * shake_scale
			var random_offset: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * decayed * 10.0
			offset = Vector2(clampf(random_offset.x, -max_shake_offset, max_shake_offset),
					clampf(random_offset.y, -max_shake_offset, max_shake_offset))


## The world rect visible at [param zoom], centered on the viewport center.
## Used to validate cinematic zooms against the play area.
static func visible_rect_for(_zoom: float, viewport_size: Vector2) -> Rect2:
	var safe_zoom: float = maxf(_zoom, 0.001)
	var size: Vector2 = viewport_size / safe_zoom
	var center: Vector2 = viewport_size / 2.0
	return Rect2(center - size / 2.0, size)


## Tweens the cinematic base zoom towards [param target] over [param duration];
## a non-positive duration sets it instantly.
func set_base_zoom(target: float, duration: float, trans: Tween.TransitionType = Tween.TRANS_SINE, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	if _base_zoom_tween != null:
		_base_zoom_tween.kill()
		_base_zoom_tween = null
	if duration <= 0.0:
		_base_zoom = target
		return
	_base_zoom_tween = create_tween()
	_base_zoom_tween.tween_property(self, ^"_base_zoom", target, duration).set_trans(trans).set_ease(ease_type)


## The current cinematic base zoom, without any punch.
func get_base_zoom() -> float:
	return _base_zoom


## A quick zoom punch: rises to [param amount] over about 30% of
## [param duration] and returns to zero over the rest. A running punch is
## replaced only by an [param amount] at least as strong as the current one;
## punches never stack.
func punch(amount: float = 0.03, duration: float = 0.15) -> void:
	if _punch_tween != null and amount < _punch:
		return
	if _punch_tween != null:
		_punch_tween.kill()
		_punch_tween = null
	var safe_duration: float = maxf(duration, 0.001)
	_punch_tween = create_tween()
	_punch_tween.tween_property(self, ^"_punch", amount, safe_duration * 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, ^"_punch", 0.0, safe_duration * 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A decaying random shake. A running shake is replaced only by an
## [param intensity] at least as strong as its current decayed intensity;
## shakes never sum.
func shake(intensity: float = 1.0, duration: float = 0.3) -> void:
	var current: float = _shake_intensity * (_shake_time_left / _shake_duration) if _shake_duration > 0.0 else 0.0
	if intensity < current:
		return
	_shake_intensity = intensity
	_shake_duration = maxf(duration, 0.001)
	_shake_time_left = _shake_duration


## Restores the resting framing instantly: no tweens, zoom 1.0, no shake.
func reset() -> void:
	if _base_zoom_tween != null:
		_base_zoom_tween.kill()
		_base_zoom_tween = null
	if _punch_tween != null:
		_punch_tween.kill()
		_punch_tween = null
	_base_zoom = 1.0
	_punch = 0.0
	_shake_intensity = 0.0
	_shake_duration = 0.0
	_shake_time_left = 0.0
	offset = Vector2.ZERO
	zoom = Vector2.ONE


func _recenter() -> void:
	global_position = get_viewport_rect().size / 2.0
