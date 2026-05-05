extends Node

var score: int = 0
var is_game_over: bool = false

func add_score(value: int) -> void:
	score += value

func reset_score() -> void:
	score = 0

func game_over() -> void:
	is_game_over = true
	get_tree().paused = true

func restart_game() -> void:
	score = 0
	is_game_over = false
	get_tree().paused = false
	get_tree().reload_current_scene()

