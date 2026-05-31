# PlayerProfiler — the squad's single shared observation engine.
# Samples player kinematics, records combat events, builds a position
# heatmap and predicts the player's next position. Owns the MemorySystem.
#
# Step 1 scope: OBSERVE ONLY. Nothing here changes enemy behaviour yet;
# the tactical layer (Step 2) reads memory.blended() / hot zones later.
class_name PlayerProfiler
extends RefCounted

const CELL_SIZE := 4.0
const HEATMAP_DECAY := 0.985
const HOT_ZONE_MIN_WEIGHT := 0.6

var memory := MemorySystem.new()

var _player: Node3D = null
var _prev_pos: Vector3 = Vector3.ZERO
var _prev_strafe_sign: int = 0
var _was_grounded: bool = true
var _heatmap: Dictionary = {}      # Vector3i cell -> weight
var _last_seen_pos: Vector3 = Vector3.ZERO
var _last_seen_vel: Vector3 = Vector3.ZERO
var _initialized := false

func setup(player: Node3D, player_max_speed: float) -> void:
	_player = player
	_prev_pos = player.global_position
	memory.set_max_speed(player_max_speed)
	_initialized = true
	if not GameManager.weapon_fired.is_connected(on_weapon_fired):
		GameManager.weapon_fired.connect(on_weapon_fired)

func is_ready() -> bool:
	return _initialized and is_instance_valid(_player)

# ── Per-tick kinematic observation (driven by EnemyDirector) ──
func observe(dt: float) -> void:
	if not is_ready() or dt <= 0.0:
		return
	var pos: Vector3 = _player.global_position
	var vel: Vector3 = (pos - _prev_pos) / dt
	var horiz := Vector3(vel.x, 0.0, vel.z)
	var speed := horiz.length()

	# Strafe: project velocity onto the player's right axis
	var right: Vector3 = _player.global_transform.basis.x
	right.y = 0.0
	var strafe_signed := 0.0
	if right.length() > 0.001 and speed > 0.1:
		strafe_signed = clamp(right.normalized().dot(horiz) / max(speed, 0.01), -1.0, 1.0)
	var cur_sign := signi(int(sign(strafe_signed))) if absf(strafe_signed) > 0.25 else 0
	var flipped := cur_sign != 0 and _prev_strafe_sign != 0 and cur_sign != _prev_strafe_sign
	if cur_sign != 0:
		_prev_strafe_sign = cur_sign

	# Jump detection (rising edge off the floor)
	var grounded: bool = _player.is_on_floor() if _player.has_method("is_on_floor") else true
	if _was_grounded and not grounded and vel.y > 2.5:
		memory.apply_jump()
	_was_grounded = grounded
	memory.decay_jump()

	var near_cover := _near_cover(pos)
	memory.apply_kinematics(speed, strafe_signed, flipped, near_cover)

	_update_heatmap(pos)
	_last_seen_pos = pos
	_last_seen_vel = horiz
	_prev_pos = pos

# ── Combat observation ──
func on_weapon_fired(from: Vector3, _to: Vector3, _hit_enemy: bool, is_headshot: bool) -> void:
	if not is_ready():
		return
	# Only the PLAYER's shots originate near the player; enemy shots come from elsewhere.
	if from.distance_to(_player.global_position) > 2.5:
		return
	var engage_dist := _nearest_enemy_distance()
	memory.apply_shot(engage_dist, is_headshot)

func _nearest_enemy_distance() -> float:
	var best := 14.0
	var found := false
	for e in _player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d: float = (e as Node3D).global_position.distance_to(_player.global_position)
		if not found or d < best:
			best = d
			found = true
	return best

# ── Cover proxy: short rays around the player at chest height ──
func _near_cover(pos: Vector3) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var origin := pos + Vector3(0, 0.9, 0)
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 2.0)
		q.exclude = [_player.get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty():
			return true
	return false

# ── Heatmap & prediction ──
func _update_heatmap(pos: Vector3) -> void:
	var cell := _cell(pos)
	_heatmap[cell] = float(_heatmap.get(cell, 0.0)) + 1.0
	# Periodic decay so stale zones fade (cheap: only touched on tick).
	for k in _heatmap.keys():
		_heatmap[k] = float(_heatmap[k]) * HEATMAP_DECAY
		if _heatmap[k] < 0.05:
			_heatmap.erase(k)

func _cell(pos: Vector3) -> Vector3i:
	return Vector3i(int(floor(pos.x / CELL_SIZE)), 0, int(floor(pos.z / CELL_SIZE)))

func _cell_center(c: Vector3i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL_SIZE, 0.5, (c.z + 0.5) * CELL_SIZE)

func top_hot_zones(n: int) -> Array[Vector3]:
	var cells := _heatmap.keys()
	cells.sort_custom(func(a, b): return float(_heatmap[a]) > float(_heatmap[b]))
	var out: Array[Vector3] = []
	for c in cells:
		if float(_heatmap[c]) < HOT_ZONE_MIN_WEIGHT:
			break
		out.append(_cell_center(c))
		if out.size() >= n:
			break
	return out

func predict_next_position(lookahead: float = 1.0) -> Vector3:
	# Linear extrapolation of last-seen motion, nudged toward the hottest zone.
	var pred := _last_seen_pos + _last_seen_vel * lookahead
	var hot := top_hot_zones(1)
	if not hot.is_empty():
		pred = pred.lerp(hot[0], 0.25)
	return pred

func last_seen_position() -> Vector3:
	return _last_seen_pos

func debug_snapshot() -> Dictionary:
	var s := memory.blended().snapshot()
	s["hot_zones"] = top_hot_zones(3).size()
	return s
