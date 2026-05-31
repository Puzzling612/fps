extends Node

signal round_started(round_number: int)
signal player_health_changed(current: int, maximum: int)
signal ammo_changed(magazine: int, magazine_size: int, reserve: int)
signal weapon_changed(weapon_name: String)
signal weapon_unlocked(weapon_name: String)
signal reload_started(duration: float)
signal reload_finished
signal weapon_fired(from: Vector3, to: Vector3, hit_enemy: bool, is_headshot: bool)
signal player_damaged(amount: int)
signal game_over_triggered
signal score_changed(value: int)

var score: int = 0
var current_round: int = 0
var is_game_over: bool = false
var player: Node = null

func register_player(p: Node) -> void:
	player = p

func add_score(value: int) -> void:
	score += value
	score_changed.emit(score)

func start_round(n: int) -> void:
	current_round = n
	round_started.emit(n)

func game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_triggered.emit()
	get_tree().paused = true

func restart_game() -> void:
	score = 0
	current_round = 0
	is_game_over = false
	player = null
	get_tree().paused = false
	get_tree().reload_current_scene()
