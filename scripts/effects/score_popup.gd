class_name ScorePopup
extends Node2D

func setup(_position: Vector2, value: int, bonus: bool = false) -> void:
	global_position = _position
	var label: Label = Label.new()
	label.text = tr("SCORE_POPUP_FORMAT") % value
	label.add_theme_font_size_override("font_size", 16)
	if bonus:
		label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.5
	label.anchor_bottom = 0.5
	label.position = Vector2.ZERO
	add_child(label)

	var tween: Tween = create_tween()
	tween.tween_property(label, ^"position:y", -40.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): queue_free())
