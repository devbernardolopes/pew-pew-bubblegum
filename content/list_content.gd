@tool
extends EditorScript
## Lists every content category of [ContentLibrary] with its short names, so
## you can see which names a stage builder script may use. Run from the
## editor (File > Run).


func _run() -> void:
	ContentLibrary.refresh()
	var categories: Array[StringName] = [
		&"scene", &"entry", &"dive", &"formation",
		&"cinematic", &"music", &"stage", &"journey",
	]
	for category: StringName in categories:
		print("== %s ==" % category)
		var names: PackedStringArray = ContentLibrary.list_names(category)
		for name: String in names:
			print("  %s" % name)
