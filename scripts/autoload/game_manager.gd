extends Node

signal round_started(round_number: int)
signal player_health_changed(current: int, maximum: int)
signal ammo_changed(magazine: int, magazine_size: int, reserve: int)
signal weapon_changed(weapon_name: String)
signal weapon_unlocked(weapon_name: String)
signal reload_started(duration: float)
signal reload_finished
signal weapon_fired(from: Vector3, to: Vector3, hit_enemy: bool, is_headshot: bool)
signal ads_changed(active: bool, scoped: bool)
signal enemy_killed(was_headshot: bool)
signal player_damaged(amount: int)
signal player_explosion_hit(amount: int)
signal grenades_changed(count: int)
signal player_hit_dir(angle: float)
signal game_over_triggered
signal game_won_triggered
signal score_changed(value: int)

var score: int = 0
var current_round: int = 0
var start_wave: int = 1
var win_wave: int = 10          # clearing this wave wins the run (unless infinite)
var infinite_mode: bool = false # endless: no victory, waves keep escalating
var is_game_over: bool = false
var is_won: bool = false
var player: Node = null

var _hitstop_t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hitstop fires only on a KILL, never on every hit — otherwise fast-firing
	# weapons (SMG/AR) would stutter constantly while spraying a target.
	enemy_killed.connect(_on_enemy_killed_hitstop)

func _process(delta: float) -> void:
	if _hitstop_t > 0.0:
		_hitstop_t -= delta / maxf(Engine.time_scale, 0.001)
		if _hitstop_t <= 0.0:
			_hitstop_t = 0.0
			Engine.time_scale = 1.0
	# On the end screens (paused), Enter/Space returns to the main menu.
	if (is_game_over or is_won) and Input.is_action_just_pressed("ui_accept"):
		restart_game()

func _on_enemy_killed_hitstop(was_headshot: bool) -> void:
	if was_headshot:
		Engine.time_scale = 0.05
		_hitstop_t = 0.08
	else:
		Engine.time_scale = 0.18
		_hitstop_t = 0.045

func register_player(p: Node) -> void:
	player = p

func add_score(value: int) -> void:
	score += value
	score_changed.emit(score)

func start_round(n: int) -> void:
	current_round = n
	round_started.emit(n)

func game_over() -> void:
	if is_game_over or is_won:
		return
	is_game_over = true
	game_over_triggered.emit()
	get_tree().paused = true

func game_win() -> void:
	if is_won or is_game_over:
		return
	is_won = true
	game_won_triggered.emit()
	get_tree().paused = true

func launch_game(wave: int, infinite: bool = false) -> void:
	score = 0
	start_wave = wave
	current_round = wave - 1
	infinite_mode = infinite
	is_game_over = false
	is_won = false
	player = null
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func restart_game() -> void:
	score = 0
	start_wave = 1
	current_round = 0
	infinite_mode = false
	is_game_over = false
	is_won = false
	player = null
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
