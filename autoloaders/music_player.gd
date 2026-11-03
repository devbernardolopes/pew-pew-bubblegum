extends Node

const BUS_MUSIC: StringName = &"Music"

@export var crossfade_duration: float = 1.5
@export var game_over_music: AudioStream = null
@export var title_music: AudioStream = null

var _current_music: AudioStream = null
var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null
var _tween: Tween = null


func _ready() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_a.bus = BUS_MUSIC
	add_child(_player_a)

	_player_b = AudioStreamPlayer.new()
	_player_b.bus = BUS_MUSIC
	add_child(_player_b)

	_active_player = _player_a


func play_music(stream: AudioStream, fade_time: float = crossfade_duration, loop: bool = false) -> void:
	if stream == null or stream == _current_music:
		return

	_current_music = stream

	var next_player: AudioStreamPlayer = _player_b if _active_player == _player_a else _player_a

	next_player.stream = stream
	var _properties: Array[Dictionary] = next_player.stream.get_property_list()
	if _properties and not _properties.is_empty():
		for i in _properties.size():
			var _property: Dictionary = _properties[i]
			if _property.get("name") == "loop":
				next_player.stream.set("loop", loop)
	next_player.volume_db = -80.0
	next_player.play()

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(false)

	# Fade out current
	_tween.tween_property(_active_player, ^"volume_db", -80.0, fade_time)
	# Fade in new
	_tween.tween_property(next_player, ^"volume_db", 0.0, fade_time)

	_tween.tween_callback(Callable(self, "_finish_crossfade").bind(next_player))


func _finish_crossfade(next_player: AudioStreamPlayer) -> void:
	var old_player: AudioStreamPlayer = _active_player
	_active_player = next_player
	if old_player and is_instance_valid(old_player):
		old_player.stop()
		old_player.stream = null
