# Waits a few frames then captures a screenshot.
extends Node

@export var look_at_target: Vector3 = Vector3.ZERO

func _ready() -> void:
	print("CAPTURE_READY_CALLED")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for i in range(3):
		await get_tree().process_frame
	var cam := get_node_or_null("Camera3D") as Camera3D
	if cam:
		cam.make_current()
		if look_at_target != Vector3.ZERO:
			cam.look_at(look_at_target, Vector3.UP)
		print("CAPTURE_CAMERA_ACTIVATED")
	for i in range(8):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://map_preview.png")
	print("CAPTURE_SAVE_RESULT:", err)
	print("PREVIEW_SAVED")
	get_tree().quit()
