# Tactical director: coordinates enemies around the player and, crucially, turns
# the (already-computed) player profile into VISIBLE counter-play on the map.
# - Encircles the player in slots; back-of-view slots are "flank" → those sprint.
# - Reads the player's heat-map "home zone" and routes a flanker through the
#   nearest concealed FLANK_ENTRY so it emerges behind that zone.
# - If the player favours HIGH GROUND (camps a tower/roof or fights at range),
#   sends a marksman to contest it (push them off, or seize an opposing perch).
# All map knowledge comes from `tactical_points` markers placed by the LevelBuilder,
# so nothing here is hard-coded to a specific arena.

extends Node

@export var slot_count: int = 8
@export var slot_radius: float = 10.0
@export var reassign_interval: float = 0.5
@export var min_enemies_before_objective: int = 3
@export var flank_interval: float = 6.0
@export var highground_interval: float = 7.0

@export var profiler_tick_interval: float = 0.2
@export var debug_profile_log: bool = false

var _reassign_timer: float = 0.3
var _flank_timer: float = 2.0
var _highground_timer: float = 3.5
var _flank_ref: WeakRef = null
var _highground_ref: WeakRef = null

# Cached tactical-point markers (placed by LevelBuilder into group tactical_points).
var _tactical: Array = []

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
var difficulty: float = 1.0
var _hp_accum: float = 0.0
var _hp_samples: int = 0
var _kills_this_wave: int = 0
var _wave_time: float = 0.0

func _ready() -> void:
	add_to_group("ai_director")
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)
	call_deferred("_cache_tactical")

func _cache_tactical() -> void:
	_tactical = get_tree().get_nodes_in_group("tactical_points")

# Called by enemies on death so DDA can gauge kill speed.
func report_kill() -> void:
	_kills_this_wave += 1

func _on_round_started(_n: int) -> void:
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
	var c: float = profiler.memory.total.confidence()
	if perf > 0.65:
		difficulty += 0.03 * c
	elif perf < 0.45:
		difficulty -= 0.10
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
		current_profile = profiler.memory.blended()
		shared_hot_zones = profiler.top_hot_zones(3)
		shared_predicted_pos = profiler.predict_next_position()
		if debug_profile_log:
			_debug_log_timer -= dt
			if _debug_log_timer <= 0.0:
				_debug_log_timer = 2.0
				print("[Profiler] ", profiler.debug_snapshot())

	# ── Encirclement + adaptive objectives ──
	_reassign_timer -= delta
	_flank_timer -= delta
	_highground_timer -= delta
	if _reassign_timer <= 0.0:
		_reassign_timer = reassign_interval
		_reassign_slots()
	if _flank_timer <= 0.0:
		_flank_timer = flank_interval
		_maybe_flank()
	if _highground_timer <= 0.0:
		_highground_timer = highground_interval
		_maybe_contest_highground()

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

	# Anticipation: center the encirclement ring slightly ahead of the player,
	# toward the profiler's predicted position — a moving player runs INTO the
	# net instead of away from it. Confidence-gated so early-game rings stay
	# honest (centered on the player).
	var ring_center: Vector3 = player_pos
	var conf: float = current_profile.confidence()
	if conf > 0.1 and shared_predicted_pos != Vector3.ZERO:
		var ahead := shared_predicted_pos
		ahead.y = player_pos.y
		# Cap the lead so a bad prediction can't drag the ring absurdly far.
		var lead := (ahead - player_pos).limit_length(slot_radius * 0.5)
		ring_center = player_pos + lead * (0.6 * conf)

	# Habitual-route direction: the player's hottest heatmap zone. Slots that sit
	# between the player and that zone get tagged "flank" (sprint + cutoff) so the
	# squad camps the route the player keeps falling back to.
	var hot_dir := Vector3.ZERO
	if not shared_hot_zones.is_empty():
		var to_hot: Vector3 = shared_hot_zones[0] - player_pos
		to_hot.y = 0
		# Only meaningful when the hot zone isn't the spot the player is standing on.
		if to_hot.length() > slot_radius * 0.5:
			hot_dir = to_hot.normalized()

	# Build slot positions around the (anticipated) ring center
	var slots: Array[Vector3] = []
	for i in slot_count:
		var ang: float = TAU * float(i) / float(slot_count)
		slots.append(ring_center + Vector3(cos(ang) * slot_radius, 0, sin(ang) * slot_radius))

	# Skip enemies that have an active objective or are already perched high up.
	var active: Array = []
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		if (e as Node3D).global_position.y > 5.0: continue
		active.append(e)

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
			var to_slot: Vector3 = slot - player_pos
			to_slot.y = 0
			var dir_to_slot: Vector3 = to_slot.normalized() if to_slot.length() > 0.001 else Vector3.FORWARD
			var dot: float = view_forward.dot(dir_to_slot)
			var role: String = "flank" if dot < -0.15 else "encircle"
			# Heatmap cutoff: a slot sitting on the player's habitual route is a
			# flank position too, even if it's in front of their view — the point
			# is to be waiting there when they rotate back to it.
			if role == "encircle" and hot_dir != Vector3.ZERO and hot_dir.dot(dir_to_slot) > 0.7:
				role = "flank"
			best.assign_slot(slot, role)

# ─── Adaptive: flank the player's home zone ─────────────────
# Routes one enemy through the concealed FLANK_ENTRY most directly BEHIND the
# player and nearest their heat-map home zone, so it emerges where they don't
# expect. The route walls force a path through the lane → it reads as a flank.
func _maybe_flank() -> void:
	# Block only while a flanker is still travelling its route; once it arrives
	# (objective cleared) or dies, the next interval dispatches a fresh one.
	if _flank_ref != null:
		var f = _flank_ref.get_ref()
		if f != null and is_instance_valid(f) and f.get("has_objective"):
			return
	var player = GameManager.player
	if not is_instance_valid(player):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() < min_enemies_before_objective:
		return
	var entries := _points_of("FLANK_ENTRY")
	if entries.is_empty():
		return

	var home := _home_zone(player)
	var view: Vector3 = -player.global_transform.basis.z
	view.y = 0
	view = view.normalized() if view.length() > 0.01 else Vector3.FORWARD

	var best: Node = null
	var best_score: float = -INF
	for e in entries:
		var to_e: Vector3 = (e as Node3D).global_position - player.global_position
		to_e.y = 0
		if to_e.length() < 0.01:
			continue
		var behind: float = -view.dot(to_e.normalized())            # 1 = directly behind
		var dist_home: float = (e as Node3D).global_position.distance_to(home)
		var score: float = behind * 1.5 - dist_home * 0.04
		if score > best_score:
			best_score = score
			best = e
	if best == null:
		return

	var access: Vector3 = best.get_meta("access", (best as Node3D).global_position)
	var picked := _nearest_free_enemy(enemies, access)
	if picked == null:
		return
	picked.assign_objective((best as Node3D).global_position, false)
	_flank_ref = weakref(picked)

# ─── Adaptive: contest high ground ──────────────────────────
# Only fires when the player actually leans on high ground (camps a perch or
# fights at long range). Pushes them off the perch they're on, or seizes an
# opposing one for a counter-sniping sightline. Prefers a marksman.
func _maybe_contest_highground() -> void:
	if _highground_ref != null and _highground_ref.get_ref():
		return
	var player = GameManager.player
	if not is_instance_valid(player):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() < min_enemies_before_objective:
		return
	var highs := _points_of("HIGH_GROUND")
	if highs.is_empty():
		return

	var player_high: bool = player.global_position.y > 3.0
	var prof := current_profile
	var sniper: bool = prof != null and (prof.sniper_tendency > 0.5 or prof.avg_engage_distance > 20.0)
	if not player_high and not sniper:
		return

	var target: Node = null
	if player_high:
		# Push them off whichever perch they're standing on.
		var bd: float = INF
		for h in highs:
			var d: float = (h as Node3D).global_position.distance_to(player.global_position)
			if d < bd:
				bd = d; target = h
	else:
		# Seize the perch farthest from their home zone → a fresh counter-sightline.
		var home := _home_zone(player)
		var bd: float = -INF
		for h in highs:
			var d: float = (h as Node3D).global_position.distance_to(home)
			if d > bd:
				bd = d; target = h
	if target == null:
		return

	var climb: bool = bool(target.get_meta("climb", false))
	var access: Vector3 = target.get_meta("access", (target as Node3D).global_position)
	var obj: Vector3 = access if climb else (target as Node3D).global_position
	var picked := _nearest_free_enemy(enemies, access, 2)   # prefer MARKSMAN
	if picked == null:
		picked = _nearest_free_enemy(enemies, access)
	if picked == null:
		return
	picked.assign_objective(obj, climb)
	_highground_ref = weakref(picked)

# ─── Helpers ─────────────────────────────────────────────────
func _points_of(kind: String) -> Array:
	var out: Array = []
	for t in _tactical:
		if is_instance_valid(t) and String(t.get_meta("kind", "")) == kind:
			out.append(t)
	return out

func _home_zone(player) -> Vector3:
	if not shared_hot_zones.is_empty():
		return shared_hot_zones[0]
	return (player as Node3D).global_position

func _nearest_free_enemy(enemies: Array, near: Vector3, prefer_type: int = -1) -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e): continue
		if e.get("has_objective"): continue
		if (e as Node3D).global_position.y > 5.0: continue   # already perched
		if prefer_type >= 0 and int(e.get("enemy_type")) != prefer_type: continue
		var d: float = (e as Node3D).global_position.distance_to(near)
		if d < best_d:
			best_d = d
			best = e
	return best
