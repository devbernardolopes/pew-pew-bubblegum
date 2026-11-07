class_name ScreenShake
extends Node2D
## Delegates to the scene's [CameraDirector], which owns the decaying shake;
## this node only forwards the call and frees itself. With no camera in the
## scene it frees itself without doing anything, as before.

func setup(intensity: float = 1.0, duration: float = 0.3) -> void:
	var director: CameraDirector = get_tree().get_first_node_in_group(&"camera_director") as CameraDirector
	if director != null:
		director.shake(intensity, duration)
	queue_free()
