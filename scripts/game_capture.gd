# Lets the game run for a few seconds, then captures a screenshot from the player's POV.
extends Node

func _ready() -> void:
	# Wait ~7 seconds — round 1 should spawn enemies in this window
	await get_tree().create_timer(7.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://game_capture.png")
	# Also log enemy positions
	var enemies := get_tree().get_nodes_in_group("enemies")
	print("ENEMIES_ALIVE:", enemies.size())
	for i in enemies.size():
		var e: Node3D = enemies[i]
		print("E", i, "_POS:", e.global_position, " STATE:", e.get("state"), " ROLE:", e.get("role"))
	print("CAPTURED")
	get_tree().quit()
