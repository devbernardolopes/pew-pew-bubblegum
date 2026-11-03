extends Control

func _ready() -> void:
	var label: Label = get_node_or_null("Label") as Label
	if label != null:
		label.text = tr("TITLE_TEXT")
	if MusicPlayer != null and MusicPlayer.title_music != null:
		MusicPlayer.play_music(MusicPlayer.title_music)
