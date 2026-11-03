extends Node
## Loads the centralized translation resource so all scripts can use tr("KEY").

func _ready() -> void:
	var path: String = "res://resources/localization/strings.po"
	if FileAccess.file_exists(path):
		var translation: Translation = load(path) as Translation
		if translation != null:
			TranslationServer.add_translation(translation)
