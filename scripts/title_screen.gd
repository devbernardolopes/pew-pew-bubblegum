extends Control

func _ready() -> void:
	if MusicPlayer != null and MusicPlayer.title_music != null:
		MusicPlayer.play_music(MusicPlayer.title_music)
