class_name ScreenShake
extends Node2D

func setup(intensity: float = 1.0, duration: float = 0.3) -> void:
	# Find the scene's Camera2D; if none, skip.
	var root: Node = Engine.get_main_loop().get_root()
	var scene_root: Node = root.get_child(root.get_child_count() - 1)
	var camera: Camera2D = null
	# Try to find an existing Camera2D in the current scene
	for node: Node in scene_root.get_children(true):
		if node is Camera2D:
			camera = node as Camera2D
			break
	if camera == null:
		queue_free()
		return

	var tween: Tween = create_tween()
	var steps: int = 8
	for i in range(steps):
		var offset: Vector2 = Vector2(randf_range(-intensity, intensity) * 10.0, randf_range(-intensity, intensity) * 10.0)
		tween.tween_property(camera, ^"offset", offset, duration / float(steps)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, ^"offset", Vector2.ZERO, duration / float(steps) * 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func(): queue_free())
