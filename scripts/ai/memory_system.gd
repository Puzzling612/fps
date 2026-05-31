# MemorySystem — keeps three behaviour profiles at different time scales and
# blends them. recent = reactive (short memory), mid = this engagement,
# total = lifelong habit. EMA-based → O(1) memory, real-time safe.
class_name MemorySystem
extends RefCounted

var recent: PlayerProfile = PlayerProfile.new()   # ~last minute  (fast EMA)
var mid:    PlayerProfile = PlayerProfile.new()    # ~last 5 min    (slow EMA)
var total:  PlayerProfile = PlayerProfile.new()    # whole match    (slowest)

# EMA blend factors per tier (per profiler tick). Tuned for ~0.2s ticks.
const A_RECENT := 0.06
const A_MID    := 0.012
const A_TOTAL  := 0.003

var _max_speed: float = 10.0

func set_max_speed(s: float) -> void:
	_max_speed = max(0.01, s)

# ── Kinematic sample (called every profiler tick) ──
func apply_kinematics(speed: float, strafe_signed: float, flipped: bool, near_cover: bool) -> void:
	_km(recent, A_RECENT, speed, strafe_signed, flipped, near_cover)
	_km(mid,    A_MID,    speed, strafe_signed, flipped, near_cover)
	_km(total,  A_TOTAL,  speed, strafe_signed, flipped, near_cover)
	recent.sample_count += 1
	mid.sample_count += 1
	total.sample_count += 1

func _km(p: PlayerProfile, a: float, speed: float, strafe: float, flipped: bool, cover: bool) -> void:
	p.avg_move_speed   = lerp(p.avg_move_speed, speed, a)
	p.strafe_bias      = lerp(p.strafe_bias, strafe, a)
	p.strafe_frequency = lerp(p.strafe_frequency, 1.0 if flipped else 0.0, a)
	p.cover_usage      = lerp(p.cover_usage, 1.0 if cover else 0.0, a)
	p.recompute_tendencies(_max_speed)

func apply_jump() -> void:
	recent.jump_rate = min(1.0, recent.jump_rate + 0.20)
	mid.jump_rate    = min(1.0, mid.jump_rate + 0.10)
	total.jump_rate  = min(1.0, total.jump_rate + 0.05)

func decay_jump() -> void:
	recent.jump_rate = lerp(recent.jump_rate, 0.0, A_RECENT)
	mid.jump_rate    = lerp(mid.jump_rate, 0.0, A_MID)
	total.jump_rate  = lerp(total.jump_rate, 0.0, A_TOTAL)

# ── Combat sample (called when the player fires) ──
func apply_shot(engage_dist: float, is_headshot: bool) -> void:
	_shot(recent, A_RECENT, engage_dist, is_headshot)
	_shot(mid,    A_MID,    engage_dist, is_headshot)
	_shot(total,  A_TOTAL,  engage_dist, is_headshot)

func _shot(p: PlayerProfile, a: float, dist: float, hs: bool) -> void:
	# weight shot-distance EMA a bit faster than kinematics so combat reads update sooner
	var sa: float = clamp(a * 3.0, 0.0, 1.0)
	p.avg_engage_distance = lerp(p.avg_engage_distance, dist, sa)
	p.headshot_ratio      = lerp(p.headshot_ratio, 1.0 if hs else 0.0, sa)
	p.long_shots  = lerp(p.long_shots,  1.0 if dist > 25.0 else 0.0, sa)
	p.close_shots = lerp(p.close_shots, 1.0 if dist < 12.0 else 0.0, sa)
	p.weapon_usage["primary"] = int(p.weapon_usage.get("primary", 0)) + 1
	p.recompute_tendencies(_max_speed)

# ── Blended profile used by the tactical layer ──
# recent 50% + mid 30% + total 20%, but total weight shrinks when low-confidence.
func blended() -> PlayerProfile:
	var out := PlayerProfile.new()
	var wr := 0.5
	var wm := 0.3
	var wt := 0.2 * total.confidence()
	var sum := wr + wm + wt
	if sum < 0.001:
		return out
	wr /= sum; wm /= sum; wt /= sum

	out.avg_engage_distance = recent.avg_engage_distance * wr + mid.avg_engage_distance * wm + total.avg_engage_distance * wt
	out.avg_move_speed = recent.avg_move_speed * wr + mid.avg_move_speed * wm + total.avg_move_speed * wt
	out.strafe_bias = recent.strafe_bias * wr + mid.strafe_bias * wm + total.strafe_bias * wt
	out.strafe_frequency = recent.strafe_frequency * wr + mid.strafe_frequency * wm + total.strafe_frequency * wt
	out.headshot_ratio = recent.headshot_ratio * wr + mid.headshot_ratio * wm + total.headshot_ratio * wt
	out.jump_rate = recent.jump_rate * wr + mid.jump_rate * wm + total.jump_rate * wt
	out.cover_usage = recent.cover_usage * wr + mid.cover_usage * wm + total.cover_usage * wt
	out.long_shots = recent.long_shots * wr + mid.long_shots * wm + total.long_shots * wt
	out.close_shots = recent.close_shots * wr + mid.close_shots * wm + total.close_shots * wt
	out.sample_count = total.sample_count
	out.recompute_tendencies(_max_speed)
	return out
