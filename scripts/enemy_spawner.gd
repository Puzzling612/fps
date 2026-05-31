extends Node3D

@export var enemy_scene: PackedScene
@export var base_enemy_count: int = 5
@export var per_round_increment: int = 2
@export var max_concurrent: int = 5
@export var base_spawn_interval: float = 2.5
@export var min_spawn_interval: float = 0.6
@export var interval_decay_per_round: float = 0.15
@export var round_break_time: float = 4.0
@export var first_round_delay: float = 2.0

var spawn_points: Array[Node3D] = []
var enemies_remaining_in_round: int = 0
var alive_enemies: int = 0
var spawn_timer: float = 0.0
var between_rounds: bool = true
var break_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemy_spawner")
	for child in get_children():
		if child is Node3D:
			spawn_points.append(child)
	break_timer = first_round_delay

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	if between_rounds:
		break_timer -= delta
		if break_timer <= 0.0:
			_start_next_round()
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0 and enemies_remaining_in_round > 0 and alive_enemies < max_concurrent:
		_spawn_one()
		spawn_timer = _current_interval()

func _current_interval() -> float:
	var r = max(1, GameManager.current_round)
	return max(min_spawn_interval, base_spawn_interval - (r - 1) * interval_decay_per_round)

func _start_next_round() -> void:
	var n = GameManager.current_round + 1
	enemies_remaining_in_round = base_enemy_count + (n - 1) * per_round_increment
	spawn_timer = 0.0
	between_rounds = false
	GameManager.start_round(n)

func _spawn_one() -> void:
	if enemy_scene == null or spawn_points.is_empty():
		return
	var player_pos := Vector3.ZERO
	if is_instance_valid(GameManager.player):
		player_pos = GameManager.player.global_position

	var shuffled = spawn_points.duplicate()
	shuffled.shuffle()
	var best: Node3D = shuffled[0]
	var best_dist: float = (best.global_position - player_pos).length()
	for p in shuffled:
		var d = (p.global_position - player_pos).length()
		if d > best_dist:
			best = p
			best_dist = d

	var enemy = enemy_scene.instantiate()

	# ── Wave-scaled balance + DDA injection ──
	var w: int = max(1, GameManager.current_round)
	var d: float = 1.0
	var dirs := get_tree().get_nodes_in_group("ai_director")
	if not dirs.is_empty() and dirs[0].get("difficulty") != null:
		d = float(dirs[0].difficulty)
	enemy.max_health         = WaveBalance.enemy_hp(w)
	enemy.attack_damage      = int(round(WaveBalance.enemy_dmg(w) * d))
	enemy.attack_interval    = WaveBalance.enemy_interval(w)
	enemy.aim_spread_deg     = WaveBalance.enemy_spread(w) / sqrt(d)
	enemy.headshot_multiplier = WaveBalance.headshot_mult(w)

	get_tree().current_scene.add_child(enemy)
	enemy.global_position = best.global_position + Vector3(0, 1.0, 0)
	enemies_remaining_in_round -= 1
	alive_enemies += 1

func _on_enemy_died() -> void:
	alive_enemies = max(0, alive_enemies - 1)
	if alive_enemies <= 0 and enemies_remaining_in_round <= 0:
		between_rounds = true
		break_timer = round_break_time
