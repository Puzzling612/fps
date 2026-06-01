# Tactical director: coordinates enemies around the player.
# - Distributes them in slots around the player (encirclement).
# - Tags slots behind the player's view as "flank" → those enemies sprint.
# - Periodically assigns one enemy a watchtower-seizing objective.

extends Node

@export var slot_count: int = 8
@export var slot_radius: float = 10.0
@export var reassign_interval: float = 0.5
@export var ladder_base: Vector3 = Vector3(-15.0, 0.5, -30.0)  # ladder approach
@export var watchtower_top: Vector3 = Vector3(-18.0, 8.3, -30.0)
@export var objective_reassign_interval: float = 3.0
@export var min_enemies_before_objective: int = 1

@export var profiler_tick_interval: float = 0.2
@export var debug_profile_log: bool = false

var _reassign_timer: float = 0.3
var _objective_timer: float = 1.5
var _objective_enemy: WeakRef = null

# ─── Adaptive AI: shared player observation ──────────────────
var profiler := PlayerProfiler.new()
var _profiler_timer: float = 0.0
var _profiler_setup_done: bool = false
var _debug_log_timer: float = 0.0

# Shared tactical readouts (refreshed each profiler tick, read by all enemies)
var current_profile: PlayerProfile = PlayerProfile.new()
var shared_hot_zones: Array[Vector3] = []
var shared_predicted_pos: Vector3 = Vector3.ZERO

# ─── Dynamic Difficulty Adjustment (DDA) ─────────────────────
# Quantitative knob D ∈ [0.75, 1.30]; scales enemy dmg/accuracy/spawn rate.
var difficulty: float = 1.0
var _hp_accum: float = 0.0
var _hp_samples: int = 0
var _kills_this_wave: int = 0
var _wave_time: float = 0.0

func _ready() -> void:
	add_to_group("ai_director")
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)

# Called by enemies on death so DDA can gauge kill speed.
func report_kill() -> void:
	_kills_this_wave += 1

func _on_round_started(_n: int) -> void:
	# A new wave begins → evaluate performance of the wave that just ended.
	if _hp_samples > 0:
		_recompute_difficulty()
	_hp_accum = 0.0
	_hp_samples = 0
	_kills_this_wave = 0
	_wave_time = 0.0

func _recompute_difficulty() -> void:
	var avg_hp := _hp_accum / float(max(1, _hp_samples))
	var kill_speed := clampf(float(_kills_this_wave) / max(1.0, _wave_time) / 1.5, 0.0, 1.0)
	var hs: float = profiler.memory.blended().headshot_ratio
	var perf := 0.5 * avg_hp + 0.3 * kill_speed + 0.2 * hs
	var c: float = profiler.memory.total.confidence()   # soften early adjustments
	if perf > 0.65:
		difficulty += 0.03 * c          # too easy → tighten (gentle, gated by confidence)
	elif perf < 0.45:
		difficulty -= 0.10              # too hard → ease faster (protect the player)
	difficulty = clampf(difficulty, 0.75, 1.15)

func _setup_profiler_if_needed() -> void:
	if _profiler_setup_done:
		return
	var player = GameManager.player
	if not is_instance_valid(player):
		return
	var max_spd: float = 10.0
	if player.get("speed") != null:
		max_spd = float(player.speed) * float(player.get("sprint_multiplier") if player.get("sprint_multiplier") != null else 1.0)
	profiler.setup(player, max_spd)
	_profiler_setup_done = true

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	# ── DDA: accumulate player-performance samples ──
	_wave_time += delta
	var pl = GameManager.player
	if is_instance_valid(pl) and pl.get("max_health") != null and int(pl.max_health) > 0:
		_hp_accum += float(pl.current_health) / float(pl.max_health)
		_hp_samples += 1

	# ── Profiler tick (observation + shared readouts) ──
	_setup_profiler_if_needed()
	_profiler_timer -= delta
	if _profiler_timer <= 0.0 and profiler.is_ready():
		var dt := profiler_tick_interval
		_profiler_timer = profiler_tick_interval
		profiler.observe(dt)
		# Refresh shared tactical readouts for the squad
		current_profile = profiler.memory.blended()
		shared_hot_zones = profiler.top_hot_zones(3)
		shared_predicted_pos = profiler.predict_next_position()
		if debug_profile_log:
			_debug_log_timer -= dt
			if _debug_log_timer <= 0.0:
				_debug_log_timer = 2.0
				print("[Profiler] ", profiler.debug_snapshot())

	_reassign_timer -= delta
	_objective_timer -= delta
	if _reassign_timer <= 0.0:
		_reassign_timer = reassign_interval
		_reassign_slots()
	if _objective_timer <= 0.0:
		_objective_timer = objective_reassign_interval
		_try_assign_objective()

# ─── Encirclement: slot allocation ──────────────────────────
func _reassign_slots() -> void:
	var player = GameManager.player
	if not is_instance_valid(player):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		return

	var player_pos: Vector3 = player.global_position
	var view_forward: Vector3 = -player.global_transform.basis.z
	view_forward.y = 0
	if view_forward.length() < 0.001:
		view_forward = Vector3.FORWARD
	view_forward = view_forward.normalized()

	# Build slot positions around the player
	var slots: Array[Vector3] = []
	for i in slot_count:
		var ang: float = TAU * float(i) / float(slot_count)
		slots.append(player_pos + Vector3(cos(ang) * slot_radius, 0, sin(ang) * slot_radius))

	# Only consider enemies that have NO active objective AND aren't already perched
	# high up (watchtower occupants stay there and shoot — no need to encircle).
	var active: Array = []
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		if (e as Node3D).global_position.y > 5.0: continue
		active.append(e)

	# Greedy assignment: each slot picks the nearest unassigned enemy
	var assigned := {}
	for slot in slots:
		var best: Node = null
		var best_d: float = INF
		for e in active:
			if assigned.has(e): continue
			var d: float = (e as Node3D).global_position.distance_to(slot)
			if d < best_d:
				best_d = d
				best = e
		if best:
			assigned[best] = slot
			# Determine role: if the slot is behind the player view, it's a flank position
			var to_slot: Vector3 = slot - player_pos
			to_slot.y = 0
			var dir_to_slot: Vector3 = to_slot.normalized() if to_slot.length() > 0.001 else Vector3.FORWARD
			var dot: float = view_forward.dot(dir_to_slot)
			var role: String = "flank" if dot < -0.15 else "encircle"
			best.assign_slot(slot, role)

# ─── Watchtower objective ───────────────────────────────────
func _try_assign_objective() -> void:
	if _objective_enemy != null and _objective_enemy.get_ref():
		return  # someone is already pursuing the objective
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() < min_enemies_before_objective:
		return
	# Pick the enemy currently nearest to the ladder base (most efficient route)
	var best: Node = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		var d: float = (e as Node3D).global_position.distance_to(ladder_base)
		if d < best_d:
			best_d = d
			best = e
	if best == null: return
	best.assign_objective(ladder_base)
	_objective_enemy = weakref(best)
