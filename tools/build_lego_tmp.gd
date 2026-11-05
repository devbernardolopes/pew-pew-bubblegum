extends SceneTree

func _add_uid(path: String) -> void:
	var fa: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = fa.get_as_text()
	fa.close()
	if text.begins_with("[gd_scene format=3 uid=") or text.begins_with("[gd_resource"):
		# gd_resource: check header line for uid=
		var line_end: int = text.find("\n")
		var header: String = text.substr(0, line_end)
		if header.contains("uid="):
			print(path, " already has header uid")
			return
	# header has no uid
	var id: int = ResourceUID.create_id()
	var uid_str: String = ResourceUID.id_to_text(id)
	var first_nl: int = text.find("\n")
	var header: String = text.substr(0, first_nl)
	# insert before closing ]
	var idx: int = header.rfind("]")
	var new_header: String = header.substr(0, idx) + " uid=\"" + uid_str + "\"" + header.substr(idx)
	text = new_header + text.substr(first_nl)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(path, " -> ", uid_str)

func _init() -> void:
	_add_uid("res://scenes/entities/boss_01_left.tscn")
	_add_uid("res://scenes/entities/boss_01_center.tscn")
	_add_uid("res://scenes/entities/boss_01_right.tscn")
	_add_uid("res://scenes/entities/boss_01_lego.tscn")
	_add_uid("res://resources/stages/stage_boss_split_demo.tres")
	quit(0)
